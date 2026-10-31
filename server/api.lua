-- The public server API. Every export this resource publishes is defined here so
-- the whole contract a job resource writes against is one file.
--
-- Exports are server-side by design: a call has to be authoritative (a client
-- must not be able to invent one, or expire someone else's), and the recipient
-- roster only exists on the server. The only client exports are the two
-- presentation ones in client/exports.lua.

Dispatch = Dispatch or {}
Dispatch.api = {}

---Wire form of a call: the subset a client is allowed to see, with the units map
---flattened into an array the UI can render directly.
---@param call table
---@return table
function Dispatch.api.toWire(call)
    local units = {}
    for _, unit in pairs(call.units) do units[#units + 1] = unit end
    table.sort(units, function(a, b) return a.at < b.at end)

    return {
        id = call.id,
        service = call.service,
        code = call.code,
        title = call.title,
        message = call.message,
        priority = call.priority,
        coords = call.coords,
        icon = call.icon,
        createdAt = call.createdAt,
        expiresAt = call.expiresAt,
        closedAt = call.closedAt,
        closeReason = call.closeReason,
        origin = call.origin,
        data = call.data,
        -- Carried so a single call can override its service's alert tone (a
        -- silent alarm should not sound like a routine call). `onAccept` is
        -- deliberately NOT carried: it is a server event name, and a client has
        -- no business knowing it.
        sound = call.sound,
        units = units,
    }
end

---Pushes a call to every currently on-duty member of its service.
---
---One TriggerClientEvent per recipient rather than a `-1` broadcast with a
---client-side filter: a broadcast would hand every connected player the
---coordinates and description of every crime in progress, which is a
---straightforward cheat feed.
---@param call table
---@param event string
---@return integer recipientCount
local function push(call, event)
    local wire = Dispatch.api.toWire(call)
    -- The server clock rides along with every push. A client's own
    -- GetGameTimer() counts its session, the server's counts server uptime, and
    -- a call's timestamps are in the latter -- so the client needs a fresh
    -- reading to keep its offset honest, including after a reconnect where it
    -- never saw a hydrate.
    local now = GetGameTimer()
    local count = 0
    for _, src in ipairs(Dispatch.recipients.sources(call.service, call.jobs)) do
        TriggerClientEvent(event, src, wire, now)
        count = count + 1
    end
    return count
end

Dispatch.api.push = push

---Raises a new dispatch call.
---
---@param payload table See docs/index.md for the full field list.
---@return integer|false callId
---@return integer|string recipientCount when a call was created, or the error
function Dispatch.api.createCall(payload)
    local origin = GetInvokingResource() or GetCurrentResourceName()
    if Config.trustedCallers and Config.trustedCallers[origin] ~= true then
        return false, ('resource %q is not allowed to create free-form dispatch calls'):format(origin)
    end

    local normalised, err = Dispatch.calls.normalise(payload, {
        priorities = Config.priorities,
        defaultPriority = Config.defaultPriority,
    })
    if not normalised then return false, err end

    local service, jobs, resolveErr = Dispatch.recipients.resolve(normalised.jobs, normalised.jobTypes)
    if not service then return false, resolveErr end

    local call = Dispatch.store.insert(normalised, service, jobs, origin)
    local count = push(call, 'qbdispatch:client:call')

    if Config.debug then
        print(('[qbdispatch] #%d %s/%s "%s" -> %d recipient(s) from %s')
            :format(call.id, service, call.code or 'no-code', call.title, count, origin))
    end

    return call.id, count
end

---Revises an open call in place; every recipient is re-pushed with the new
---content. Use it for "the suspect vehicle is now a red Sultan", not to close.
---@param id integer
---@param patch table
---@return boolean ok, string|nil error
function Dispatch.api.updateCall(id, patch)
    local call, err = Dispatch.store.update(id, patch)
    if not call then return false, err end

    push(call, 'qbdispatch:client:callUpdated')
    return true
end

---Closes a call. It leaves the live feed immediately and stays in history.
---@param id integer
---@param reason string|nil
---@return boolean ok, string|nil error
function Dispatch.api.closeCall(id, reason)
    local call, err = Dispatch.store.close(id, reason)
    if not call then return false, err end

    push(call, 'qbdispatch:client:callUpdated')
    return true
end

---@param id integer
---@return table|nil
function Dispatch.api.getCall(id)
    local call = Dispatch.store.get(id)
    return call and Dispatch.api.toWire(call) or nil
end

---@param filter { service: string|nil, job: string|nil, activeOnly: boolean|nil }|nil
---@return table[]
function Dispatch.api.getCalls(filter)
    filter = filter or {}

    local services = filter.service and { filter.service } or Dispatch.store.services()
    local out = {}
    for _, service in ipairs(services) do
        for _, call in ipairs(Dispatch.store.list(service, filter)) do
            out[#out + 1] = Dispatch.api.toWire(call)
        end
    end
    return out
end

---Attaches a unit to a call at a given state, or advances them to the next state
---when `state` is omitted. Passing `false` detaches them.
---@param src integer
---@param id integer
---@param state string|false|nil
---@return string|false state The unit's new state, or false on failure.
---@return string|nil error
function Dispatch.api.setUnitState(src, id, state)
    local call = Dispatch.store.get(id)
    if not call then return false, 'no such call' end
    -- Detaching is cleanup and remains valid after closure/expiry. Every other
    -- transition is a response to a live incident and must fail closed here,
    -- regardless of what an older client happens to render.
    if state ~= false and not Dispatch.calls.isLive(call, GetGameTimer()) then
        return false, 'call is no longer active'
    end

    local unit = Dispatch.recipients.unitOf(src)
    if not unit then return false, 'not on duty' end
    if unit.jobType ~= call.service then return false, 'wrong service for this call' end

    -- Service alone is not enough. A call raised against `jobs = {'police'}`
    -- never reached the sheriff's department, so a deputy must not be able to
    -- attach to it either -- otherwise the unit list shows responders who were
    -- never told about the incident.
    local invited = false
    for _, jobName in ipairs(call.jobs) do
        if jobName == unit.job then invited = true break end
    end
    if not invited then return false, 'this call was not sent to your department' end

    local existing = call.units[tostring(src)]

    local target
    if state == false then
        target = nil
    elseif state == nil then
        target = Dispatch.calls.nextState(existing and existing.state or nil)
    else
        target = state
    end

    -- Concurrency cap. Only the ACCEPT is capped -- `not existing` and a target
    -- inside the state walk. Advancing (on scene, clear) and detaching must
    -- always be allowed, or a unit that hit the cap could never clear the call
    -- holding it there.
    --
    -- Enforced here rather than in store.setUnitState because the store is the
    -- low-level write and is also what detachAll and the retention sweep drive;
    -- a policy check belongs on the authoritative entry point, not under it.
    local limit = Config.dispatch and Config.dispatch.maxActiveCalls
    if target and not existing and limit and limit > 0 then
        if Dispatch.store.countAttached(src, id) >= limit then
            return false, limit == 1
                and 'you are already en route to a call'
                or ('you are already en route to %d calls'):format(limit)
        end
    end

    local updated, err = Dispatch.store.setUnitState(id, src, target, unit)
    if not updated then return false, err end

    -- The first transition into the first state is the "accept", and the only
    -- moment an onAccept hook should fire. Later advances (on scene, clear) are
    -- progress reports, not fresh acceptances -- firing the hook again would
    -- have a house-call queue hand the same job out three times.
    if call.onAccept and not existing and target == Dispatch.calls.STATES[1] then
        TriggerEvent(call.onAccept, src, call.id, call.data)
    end

    push(updated, 'qbdispatch:client:callUpdated')

    return target or false
end

---The on-duty roster for a service, straight from kora_core's maintained index.
---@param filter { service: string|nil, job: string|nil }|nil
---@return table[]
function Dispatch.api.getOnDutyUnits(filter)
    filter = filter or {}
    return exports.kora_core:getOnDutyRoster({ job = filter.job, jobType = filter.service })
end

-- --- exports ---------------------------------------------------------------

exports('createCall', Dispatch.api.createCall)
exports('updateCall', Dispatch.api.updateCall)
exports('closeCall', Dispatch.api.closeCall)
exports('getCall', Dispatch.api.getCall)
exports('getCalls', Dispatch.api.getCalls)
exports('setUnitState', Dispatch.api.setUnitState)
exports('getOnDutyUnits', Dispatch.api.getOnDutyUnits)

-- --- lifecycle -------------------------------------------------------------

-- A unit that dropped or went off duty cannot still be en route. Both paths
-- detach them and re-push the affected calls so everyone else's unit list stops
-- showing a responder who is not coming.
local function detach(src)
    for _, id in ipairs(Dispatch.store.detachAll(src)) do
        local call = Dispatch.store.get(id)
        if call then push(call, 'qbdispatch:client:callUpdated') end
    end
end

AddEventHandler('qbcore:server:playerDropped', function(src) detach(src) end)

AddEventHandler('QBCore:Server:SetDuty', function(src, onDuty)
    if not onDuty then detach(src) end
end)

CreateThread(function()
    Kora.timers.setInterval(Dispatch.store.sweep, Config.history.sweepInterval)
end)
