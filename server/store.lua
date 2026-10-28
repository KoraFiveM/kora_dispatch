-- The authoritative call registry. Everything a client sees about a call comes
-- from here; a client never invents, mutates or expires a call locally.
--
-- Calls are kept per SERVICE (a kora_core job type). That partitioning is not
-- cosmetic: it is what makes "police and EMS are two separate calls" work, since
-- each service gets its own feed, its own history and its own retention budget.
-- A busy police shift can never push an ambulance call out of the EMS history.

Dispatch = Dispatch or {}
Dispatch.store = {}

-- service -> { callId -> call }, plus a creation-ordered id list per service so
-- retention can drop the oldest without sorting.
local byService = {}
local orderByService = {}

-- Flat id -> call, so getCall/updateCall are O(1) without knowing the service.
local byId = {}

local nextId = 0

---@param service string
---@return table calls, integer[] order
local function bucket(service)
    byService[service] = byService[service] or {}
    orderByService[service] = orderByService[service] or {}
    return byService[service], orderByService[service]
end

---Drops calls beyond the retention budget for one service.
---
---Only CLOSED or EXPIRED calls are ever dropped. A live call is never evicted
---no matter how far over budget the service is -- silently deleting an active
---emergency because fifty routine ones came in first would be the worst
---possible failure for this system.
---@param service string
---@param now integer
local function prune(service, now)
    local calls, order = bucket(service)

    local kept = {}
    for _, id in ipairs(order) do
        local call = calls[id]
        if call then
            local dead = call.closedAt or now >= call.expiresAt
            local stale = dead and (now - (call.closedAt or call.expiresAt)) > Config.history.ttl
            if stale then
                calls[id] = nil
                byId[id] = nil
            else
                kept[#kept + 1] = id
            end
        end
    end

    -- Over budget: drop the oldest dead calls first, oldest-first through the
    -- creation order, until either the budget is met or only live calls remain.
    local excess = #kept - Config.history.max
    if excess > 0 then
        local survivors = {}
        for _, id in ipairs(kept) do
            local call = calls[id]
            local dead = call.closedAt or now >= call.expiresAt
            if excess > 0 and dead then
                excess = excess - 1
                calls[id] = nil
                byId[id] = nil
            else
                survivors[#survivors + 1] = id
            end
        end
        kept = survivors
    end

    orderByService[service] = kept
end

---Inserts a normalised call and returns the stored record.
---@param normalised table Output of Dispatch.calls.normalise.
---@param service string
---@param jobs string[] Concrete job names this call was resolved to.
---@param origin string Resource that raised it.
---@return table call
function Dispatch.store.insert(normalised, service, jobs, origin)
    local now = GetGameTimer()
    nextId = nextId + 1

    local call = {
        id = nextId,
        service = service,
        jobs = jobs,
        code = normalised.code,
        title = normalised.title,
        message = normalised.message,
        priority = normalised.priority,
        coords = normalised.coords,
        icon = normalised.icon,
        sound = normalised.sound,
        onAccept = normalised.onAccept,
        data = normalised.data,
        origin = origin,
        createdAt = now,
        expiresAt = now + normalised.ttl,
        closedAt = nil,
        closeReason = nil,
        units = {},
    }

    local calls, order = bucket(service)
    calls[call.id] = call
    order[#order + 1] = call.id
    byId[call.id] = call

    prune(service, now)

    return call
end

---@param id integer
---@return table|nil
function Dispatch.store.get(id)
    return byId[tonumber(id) or -1]
end

---Every call for a service, newest first.
---@param service string
---@param filter { activeOnly: boolean|nil, job: string|nil }|nil
---@return table[]
function Dispatch.store.list(service, filter)
    filter = filter or {}
    local calls, order = bucket(service)
    local now = GetGameTimer()

    local out = {}
    -- Reverse creation order: newest first is what both the feed and the
    -- history list want, and reversing here means no consumer sorts.
    for index = #order, 1, -1 do
        local call = calls[order[index]]
        if call then
            local include = true
            if filter.activeOnly and not Dispatch.calls.isLive(call, now) then include = false end
            if include and filter.job then
                include = false
                for _, job in ipairs(call.jobs) do
                    if job == filter.job then include = true break end
                end
            end
            if include then out[#out + 1] = call end
        end
    end

    return out
end

---@param service string
---@return string[]
function Dispatch.store.services()
    local out = {}
    for service in pairs(byService) do out[#out + 1] = service end
    return out
end

---Applies a shallow patch to a call. Only fields a caller is allowed to revise
---after the fact are accepted -- id/service/jobs/createdAt are identity, and
---letting an update rewrite them would silently move a call between feeds.
local PATCHABLE = {
    code = true, title = true, message = true, priority = true,
    icon = true, sound = true, data = true,
}

---@param id integer
---@param patch table
---@return table|nil call, string|nil error
function Dispatch.store.update(id, patch)
    local call = Dispatch.store.get(id)
    if not call then return nil, 'no such call' end
    if call.closedAt then return nil, 'call is closed' end
    if type(patch) ~= 'table' then return nil, 'patch must be a table' end

    -- Validate before mutating: a half-applied patch that then errors would
    -- leave the call in a state no caller asked for.
    if patch.priority ~= nil and not Config.priorities[math.floor(tonumber(patch.priority) or 0)] then
        return nil, 'unknown priority'
    end

    local duration = patch.duration
    if duration ~= nil then
        duration = tonumber(duration)
        if not duration or duration <= 0 then return nil, 'duration must be a positive number' end
    end

    for key, value in pairs(patch) do
        if PATCHABLE[key] then call[key] = value end
    end

    if patch.coords ~= nil then
        call.coords = Dispatch.calls.toCoords(patch.coords)
    end

    -- Re-basing the deadline (rather than extending from now) keeps "how long
    -- has this been open" honest while still letting an escalation to priority 1
    -- buy the call the longer life its new severity deserves.
    if patch.priority then
        call.priority = math.floor(tonumber(patch.priority))
        call.expiresAt = call.createdAt + (duration or Config.priorities[call.priority].ttl)
    elseif duration then
        call.expiresAt = call.createdAt + duration
    end

    return call
end

---@param id integer
---@param reason string|nil
---@return table|nil call, string|nil error
function Dispatch.store.close(id, reason)
    local call = Dispatch.store.get(id)
    if not call then return nil, 'no such call' end
    if call.closedAt then return call end

    call.closedAt = GetGameTimer()
    call.closeReason = type(reason) == 'string' and reason or nil

    return call
end

---Records a unit's state against a call. `nil` state detaches them.
---@param id integer
---@param src integer
---@param state string|nil
---@param unit table|nil Roster record, cached on the call so history still shows who attended after they log off.
---@return table|nil call, string|nil error
function Dispatch.store.setUnitState(id, src, state, unit)
    local call = Dispatch.store.get(id)
    if not call then return nil, 'no such call' end

    if state == nil then
        call.units[tostring(src)] = nil
        return call
    end

    if not Dispatch.calls.isLive(call, GetGameTimer()) then return nil, 'call is no longer active' end
    if not Dispatch.calls.isValidState(state) then return nil, 'invalid unit state' end

    -- Keyed by STRING source. This table is json-encoded on its way to the NUI,
    -- and a sparse integer-keyed Lua table encodes as an object with string keys
    -- anyway -- keying it as strings from the start means the Lua side and the
    -- browser side agree instead of one of them silently missing every lookup.
    local key = tostring(src)
    local existing = call.units[key]

    call.units[key] = {
        src = src,
        state = state,
        at = GetGameTimer(),
        name = (unit and unit.name) or (existing and existing.name),
        callsign = (unit and unit.callsign) or (existing and existing.callsign),
        job = (unit and unit.job) or (existing and existing.job),
    }

    return call
end

---Counts the calls `src` is actively committed to: attached, not yet cleared,
---and on a call that is still live. This is what `Config.dispatch.maxActiveCalls`
---is measured against.
---
---`clear` does not count. It is the last state in the walk and means the unit
---has finished -- a unit that has cleared its last call must be able to take
---the next one without waiting for the retention sweep to drop the old record.
---Closed and expired calls do not count either, for the same reason.
---@param src integer
---@param exceptId integer|nil A call to ignore -- pass the call being advanced so re-advancing your own call is never blocked by itself.
---@return integer count
function Dispatch.store.countAttached(src, exceptId)
    local key = tostring(src)
    local now = GetGameTimer()
    local count = 0

    for id, call in pairs(byId) do
        if id ~= exceptId then
            local unit = call.units[key]
            if unit and unit.state ~= 'clear' and Dispatch.calls.isLive(call, now) then
                count = count + 1
            end
        end
    end

    return count
end

---Counts every currently live call, across services. Player-originated ingress
---uses this for its global amplification ceiling; trusted server calls are not
---evicted or refused by the store itself.
---@return integer count
function Dispatch.store.countLive()
    local now = GetGameTimer()
    local count = 0

    for _, call in pairs(byId) do
        if Dispatch.calls.isLive(call, now) then count = count + 1 end
    end

    return count
end

---Detaches a source from every call it is attached to. Used on drop and on
---going off duty -- a unit that has left cannot still be en route.
---@param src integer
---@return integer[] affectedCallIds
function Dispatch.store.detachAll(src)
    local key = tostring(src)
    local affected = {}
    for id, call in pairs(byId) do
        if call.units[key] then
            call.units[key] = nil
            affected[#affected + 1] = id
        end
    end
    return affected
end

---Retention sweep across every service. Driven by a QB.timers interval so it
---dies with the resource.
function Dispatch.store.sweep()
    local now = GetGameTimer()
    for service in pairs(byService) do prune(service, now) end
end

---Test seam: wipes every call. Never called in gameplay.
function Dispatch.store._reset()
    byService, orderByService, byId, nextId = {}, {}, {}, 0
end
