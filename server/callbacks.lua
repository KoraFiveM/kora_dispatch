-- The client-facing surface. Everything here is authenticated against the
-- caller's own on-duty job -- a client may ask for its own service's calls and
-- change its own unit state, and nothing else.

Dispatch = Dispatch or {}

---The service a source is entitled to see, or nil when they are not on duty.
---@param src integer
---@return string|nil service, table|nil unit
local function serviceOf(src)
    local unit = Dispatch.recipients.unitOf(src)
    if not unit or not unit.onDuty then return nil end
    return unit.jobType, unit
end

-- Initial hydrate: everything the client needs to render, in one round trip, so
-- a player coming on duty (or reconnecting mid-shift) sees the existing call
-- backlog instead of an empty feed until the next incident.
Kora.callback.register('qbdispatch:hydrate', function(src)
    local service, unit = serviceOf(src)
    if not service then return nil end

    local serviceConfig = Config.services[service] or Config.defaultService

    -- Config.priorities is authored as a DENSE array ([1], [2], [3]), which
    -- json.encode emits as a JSON array -- so the browser would read index 0 as
    -- priority 1 and every label, colour and lifetime would be off by one.
    -- Re-keyed to strings here so the wire shape is unambiguously an object and
    -- `priorities[String(p)]` means exactly what it says on both sides.
    local priorities = {}
    for level, definition in pairs(Config.priorities) do
        priorities[tostring(level)] = definition
    end

    return {
        service = service,
        unit = unit,
        -- The server clock, so the client can convert its own GetGameTimer()
        -- into the one every call timestamp is stamped with.
        now = GetGameTimer(),
        config = {
            label = serviceConfig.label,
            accent = serviceConfig.accent,
            -- The service's own alert tone. Without this the client could only
            -- ever fall back to the default, so a per-service sound was
            -- documented but unreachable.
            sound = serviceConfig.sound,
            priorities = priorities,
            feed = Config.feed,
            map = Config.map,
        },
        calls = Dispatch.api.getCalls({ service = service, job = unit.job }),
    }
end, { rateLimit = { max = 5, window = 5000 } })

-- Attach/advance/detach. `state` is optional: omitted, it advances one step,
-- which is what the single respond keybind sends.
Kora.callback.register('qbdispatch:respond', function(src, callId, state)
    local service = serviceOf(src)
    if not service then return false, 'not on duty' end

    return Dispatch.api.setUnitState(src, callId, state)
end, { rateLimit = { max = 20, window = 5000 } })

-- Tablet open/close. This is what gates the unit heartbeat, so it is the one
-- callback a client is expected to send often; the rate limit is sized for a
-- player toggling the view rather than for a script hammering it.
Kora.callback.register('qbdispatch:setViewing', function(src, viewing)
    local service = serviceOf(src)
    if not service then
        Dispatch.units.setViewer(src, nil)
        return false
    end

    Dispatch.units.setViewer(src, viewing and service or nil)

    -- Populate the map immediately rather than leaving it blank until the next
    -- heartbeat. This runs the real broadcast rather than returning a roster:
    -- roster records carry no coordinates, and handing those to the client as if
    -- they were position snapshots put `undefined` through the map projection
    -- and took the whole React tree down -- feed included -- on every open.
    if viewing then Dispatch.units.tick() end

    return true
end, { rateLimit = { max = 30, window = 10000 } })

-- Full call list for the history view, including expired and closed calls.
Kora.callback.register('qbdispatch:getCalls', function(src, filter)
    local service, unit = serviceOf(src)
    if not service then return {} end

    filter = type(filter) == 'table' and filter or {}
    -- Bind both filters to the current unit; sharing a service does not grant
    -- access to calls addressed only to another department.
    filter.service = service
    filter.job = unit.job

    return Dispatch.api.getCalls(filter)
end, { rateLimit = { max = 10, window = 5000 } })
