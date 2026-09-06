-- Legacy inbound. Anything already written against qb-policejob or
-- qb-ambulancejob raises a real dispatch call here without being touched.
--
-- Loaded LAST so every function it forwards to already exists.

Dispatch = Dispatch or {}

if not Config.compat.legacyInbound and not Config.compat.coreAlerts then return end

if Config.compat.legacyInbound then
    -- Compatibility keeps the old event names, not their trust model. The
    -- client payload is ignored and each event selects one fixed, throttled
    -- incident whose coordinates are derived from the reporter's ped.
    local compatibilityAlerts = {
        ['qbdispatch:compat:police'] = {
            jobTypes = { 'leo' }, code = '10-13', title = 'Officer Alert',
            message = 'An officer requested assistance.', priority = 1, icon = 'siren',
            requiredJobType = 'leo',
        },
        ['qbdispatch:compat:ambulance'] = {
            jobTypes = { 'ems' }, code = '10-52', title = 'Medical Emergency',
            message = 'A medical emergency was reported.', priority = 1, icon = 'heart-pulse',
        },
        ['qbdispatch:compat:doctor'] = {
            jobTypes = { 'ems' }, code = '10-51', title = 'Doctor Requested',
            message = 'A doctor is needed at the hospital.', priority = 3, icon = 'stethoscope',
        },
    }

    local owner = GetCurrentResourceName()
    for key, definition in pairs(compatibilityAlerts) do
        local ok, err = Dispatch.ingress.register(key, definition, owner)
        if not ok then print(('^3[qbdispatch]^7 could not register compatibility alert %s: %s'):format(key, err)) end
    end

    RegisterNetEvent('police:server:policeAlert', function()
        local src = source
        Dispatch.ingress.create(src, 'qbdispatch:compat:police')
    end)

    RegisterNetEvent('hospital:server:ambulanceAlert', function()
        local src = source
        Dispatch.ingress.create(src, 'qbdispatch:compat:ambulance')
    end)

    RegisterNetEvent('hospital:server:SendDoctorAlert', function()
        Dispatch.ingress.create(source, 'qbdispatch:compat:doctor')
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
