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
        ['kora_dispatch:compat:police'] = {
            jobTypes = { 'leo' }, code = '10-13', title = Kora.lang('Compatibility.officer_title'),
            message = Kora.lang('Compatibility.officer_message'), priority = 1, icon = 'siren',
            requiredJobType = 'leo',
        },
        ['kora_dispatch:compat:ambulance'] = {
            jobTypes = { 'ems' }, code = '10-52', title = Kora.lang('Compatibility.medical_title'),
            message = Kora.lang('Compatibility.medical_message'), priority = 1, icon = 'heart-pulse',
        },
        ['kora_dispatch:compat:doctor'] = {
            jobTypes = { 'ems' }, code = '10-51', title = Kora.lang('Compatibility.doctor_title'),
            message = Kora.lang('Compatibility.doctor_message'), priority = 3, icon = 'stethoscope',
        },
    }

    local owner = GetCurrentResourceName()
    for key, definition in pairs(compatibilityAlerts) do
        local ok, err = Dispatch.ingress.register(key, definition, owner)
        if not ok then print(('^3[kora_dispatch]^7 could not register compatibility alert %s: %s'):format(key, err)) end
    end

    RegisterNetEvent('police:server:policeAlert', function()
        Dispatch.ingress.create(source, 'kora_dispatch:compat:police')
    end)

    RegisterNetEvent('hospital:server:ambulanceAlert', function()
        Dispatch.ingress.create(source, 'kora_dispatch:compat:ambulance')
    end)

    RegisterNetEvent('hospital:server:SendDoctorAlert', function()
        Dispatch.ingress.create(source, 'kora_dispatch:compat:doctor')
    end)
end

if Config.compat.coreAlerts then
    -- kora_core's own Core.dispatch.alert is a raw fan-out with no UI of its own
    -- (its module header says so explicitly). Mirroring it here means anything
    -- calling exports.kora_core:alert directly gets a real dispatch call rather
    -- than a notification that vanishes.
    --
    -- The mirror runs on the SERVER off the same local event kora_core fires, not
    -- by listening to its client push -- otherwise every recipient's client
    -- would ask the server to create the same call, once each.
    AddEventHandler('kora_core:server:dispatchAlert', function(payload)
        if type(payload) ~= 'table' then return end
        Dispatch.api.createCall(payload)
    end)
end
