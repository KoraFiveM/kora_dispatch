-- Pure, realm-agnostic call helpers. Everything here is deliberately free of
-- natives and of Core/QB lookups so the whole normalisation and expiry model can
-- be unit-tested under plain Lua -- the shape of a call is the contract every
-- job resource writes against, so it is the part most worth testing.

Dispatch = Dispatch or {}
Dispatch.calls = {}

---Cross-resource callables arrive as a table with a `__call` metamethod, not a
---function. Every registration API in this stack needs this; a bare
---`type(x) == 'function'` guard rejects every caller that came through exports.
---@param value any
---@return boolean
function Dispatch.calls.isCallable(value)
    if type(value) == 'function' then return true end
    local meta = getmetatable(value)
    return type(meta) == 'table' and Dispatch.calls.isCallable(meta.__call)
end

---Coerces anything vector3-ish into a plain `{x, y, z}` table, or nil.
---Plain tables only: a CfxLua vector3 does not survive json.encode intact, and
---this value is going to the NUI and across the network.
---@param value any
---@return table|nil
function Dispatch.calls.toCoords(value)
    if type(value) ~= 'table' and type(value) ~= 'vector3' and type(value) ~= 'vector4' then return nil end
    local x, y, z = value.x, value.y, value.z
    if type(x) ~= 'number' or type(y) ~= 'number' then return nil end
    return { x = x + 0.0, y = y + 0.0, z = (tonumber(z) or 0.0) + 0.0 }
end

---@param priority any
---@param priorities table
---@param default integer
---@return integer
function Dispatch.calls.resolvePriority(priority, priorities, default)
    local p = math.floor(tonumber(priority) or 0)
    if priorities[p] then return p end
    return default
end

---Normalises a caller-supplied payload into the canonical call shape.
---
---Accepts the field aliases a ps-dispatch/qb-phone-era script already uses
---(`description`, `job`, `dispatchCode`) so an existing robbery script can be
---pointed at this API by changing the export name and nothing else.
---
---Returns `nil, reason` rather than raising: createCall is called from gameplay
---code paths where a malformed alert should be logged and skipped, not crash
---the robbery script mid-heist.
---@param payload table
---@param options { priorities: table, defaultPriority: integer }
---@return table|nil call, string|nil error
function Dispatch.calls.normalise(payload, options)
    if type(payload) ~= 'table' then return nil, 'payload must be a table' end

    -- `jobs` and `jobTypes` may each be a string or an array of strings.
    local function list(value, alias)
        local raw = value ~= nil and value or alias
        if raw == nil then return {} end
        if type(raw) == 'string' then return { raw } end
        if type(raw) ~= 'table' then return nil end

        local out, seen = {}, {}
        for _, entry in ipairs(raw) do
            if type(entry) ~= 'string' or entry == '' then return nil end
            if not seen[entry] then
                seen[entry] = true
                out[#out + 1] = entry
            end
        end
        return out
    end

    local jobs = list(payload.jobs, payload.job)
    if not jobs then return nil, 'jobs must be a string or an array of strings' end

    local jobTypes = list(payload.jobTypes, payload.jobType)
    if not jobTypes then return nil, 'jobTypes must be a string or an array of strings' end

    if #jobs == 0 and #jobTypes == 0 then
        return nil, 'a call must target at least one job or job type'
    end

    local title = payload.title
    if title ~= nil and type(title) ~= 'string' then return nil, 'title must be a string' end

    local message = payload.message or payload.description
    if message ~= nil and type(message) ~= 'string' then return nil, 'message must be a string' end

    if title == nil and message == nil then
        return nil, 'a call needs a title or a message'
    end

    local code = payload.code or payload.dispatchCode
    if code ~= nil and type(code) ~= 'string' then return nil, 'code must be a string' end

    local priority = Dispatch.calls.resolvePriority(payload.priority, options.priorities, options.defaultPriority)

    local duration = tonumber(payload.duration)
    if duration ~= nil and duration <= 0 then return nil, 'duration must be positive' end

    return {
        code = code,
        title = title or message,
        message = message,
        priority = priority,
        jobs = jobs,
        jobTypes = jobTypes,
        coords = Dispatch.calls.toCoords(payload.coords),
        icon = type(payload.icon) == 'string' and payload.icon or nil,
        sound = payload.sound,
        onAccept = type(payload.onAccept) == 'string' and payload.onAccept or nil,
        ttl = duration or options.priorities[priority].ttl,
        data = type(payload.data) == 'table' and payload.data or nil,
    }
end

---Whether a call is still live at `now`. A closed call is never live, whatever
---its expiry says.
---@param call table
---@param now integer
---@return boolean
function Dispatch.calls.isLive(call, now)
    if call.closedAt then return false end
    return now < call.expiresAt
end

---Remaining fraction of a call's life, 1.0 at creation down to 0.0 at expiry.
---@param call table
---@param now integer
---@return number
function Dispatch.calls.remainingFraction(call, now)
    local span = call.expiresAt - call.createdAt
    if span <= 0 then return 0.0 end
    local left = (call.expiresAt - now) / span
    if left < 0 then return 0.0 end
    if left > 1 then return 1.0 end
    return left
end

---Marker opacity for a call: full for the first `holdFraction` of its life, then
---a linear ease out.
---
---Fading from the very first second reads as a broken UI rather than as "this
---call is going stale", which is why the hold exists at all.
---@param call table
---@param now integer
---@param holdFraction number
---@return number opacity 0..1
function Dispatch.calls.opacity(call, now, holdFraction)
    local left = Dispatch.calls.remainingFraction(call, now)
    local hold = 1.0 - (holdFraction or 0.6)
    if hold <= 0 then return left > 0 and 1.0 or 0.0 end
    if left >= hold then return 1.0 end
    return left / hold
end

-- The unit state machine. `respond` walks these in order, so a single keypress
-- takes an officer from unaware to cleared without a menu.
Dispatch.calls.STATES = { 'en_route', 'on_scene', 'clear' }

---Next state after `state`, or the first state when not yet attached. Returns
---nil once cleared -- a cleared unit detaches rather than cycling round.
---@param state string|nil
---@return string|nil
function Dispatch.calls.nextState(state)
    if state == nil then return Dispatch.calls.STATES[1] end
    for index, candidate in ipairs(Dispatch.calls.STATES) do
        if candidate == state then return Dispatch.calls.STATES[index + 1] end
    end
    return nil
end

---@param state any
---@return boolean
function Dispatch.calls.isValidState(state)
    for _, candidate in ipairs(Dispatch.calls.STATES) do
        if candidate == state then return true end
    end
    return false
end
