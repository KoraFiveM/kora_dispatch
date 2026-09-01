-- Legacy inbound. Anything already written against qb-policejob or
-- qb-ambulancejob raises a real dispatch call here without being touched.
--
-- Loaded LAST so every function it forwards to already exists.

Dispatch = Dispatch or {}

if not Config.compat.legacyInbound and not Config.compat.coreAlerts then return end

---Legacy alerts carry coords and text in an argument order that is NOT stable
---across the ecosystem, so sniff rather than assume:
---
---  * real qb-policejob fires `police:client:policeAlert(coords, text)`
---  * qbcore's own compat table fires it as `(message, coords)`
---
---Both shapes are live on this server at once (a vendored legacy resource and
---the modern core), and getting it wrong silently swaps a call's title with its
---coordinates. A table/vector first argument is coords; a string is the message.
---@param a any
---@param b any
---@return string|nil message, table|nil coords
local function sniff(a, b)
    if type(a) == 'string' then return a, Dispatch.calls.toCoords(b) end
    local coords = Dispatch.calls.toCoords(a)
    if coords then return type(b) == 'string' and b or nil, coords end
    return nil, nil
end

---@param src integer
---@return table|nil
local function coordsOfSource(src)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return nil end
    local coords = GetEntityCoords(ped)
    return { x = coords.x, y = coords.y, z = coords.z }
end

if Config.compat.legacyInbound then
    -- qb-policejob's server-side alert. The caller's own position is used when
    -- the event carries none, which is how the real resource behaves.
    RegisterNetEvent('police:server:policeAlert', function(a, b)
        local src = source
        local message, coords = sniff(a, b)
        Dispatch.api.createCall({
            jobTypes = { 'leo' },
            code = '10-13',
            title = 'Officer Alert',
            message = message or 'An officer requested assistance.',
            coords = coords or coordsOfSource(src),
            priority = 1,
            icon = 'siren',
            data = { legacy = 'police:server:policeAlert', requester = src },
        })
    end)

    RegisterNetEvent('hospital:server:ambulanceAlert', function(a, b)
        local src = source
        local message, coords = sniff(a, b)
        Dispatch.api.createCall({
            jobTypes = { 'ems' },
            code = '10-52',
            title = 'Medical Emergency',
            message = message or 'A medical emergency was reported.',
            coords = coords or coordsOfSource(src),
            priority = 1,
            icon = 'heart-pulse',
            data = { legacy = 'hospital:server:ambulanceAlert', requester = src },
        })
    end)

    RegisterNetEvent('hospital:server:SendDoctorAlert', function()
        Dispatch.api.createCall({
            jobTypes = { 'ems' },
            code = '10-51',
            title = 'Doctor Requested',
            message = 'A doctor is needed at the hospital.',
            priority = 3,
            icon = 'stethoscope',
            data = { legacy = 'hospital:server:SendDoctorAlert' },
        })
    end)
end

if Config.compat.coreAlerts then
    -- qbcore's own Core.dispatch.alert is a raw fan-out with no UI of its own
    -- (its module header says so explicitly). Mirroring it here means anything
    -- calling exports.qbcore:alert directly gets a real dispatch call rather
    -- than a notification that vanishes.
    --
    -- The mirror runs on the SERVER off the same local event qbcore fires, not
    -- by listening to its client push -- otherwise every recipient's client
    -- would ask the server to create the same call, once each.
    AddEventHandler('qbcore:server:dispatchAlert', function(payload)
        if type(payload) ~= 'table' then return end
        Dispatch.api.createCall(payload)
    end)
end
