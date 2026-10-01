-- Inbound wiring: service membership, calls, and the colleague heartbeat.
-- Nothing here polls; every update is server-pushed.

Dispatch = Dispatch or {}
local hydrating = false

---Pulls our service, config and the existing call backlog. Called on login, on
---job/duty change, and on resource start -- so coming on duty mid-shift shows
---the calls already in progress rather than an empty feed.
local function hydrate()
    -- The player-loaded, job-update, and duty events often arrive together.
    -- A hydrate is a full replacement, so one in-flight request already has
    -- all the state a later request would fetch.
    if hydrating then return end
    hydrating = true
    local data = QB.callback.trigger('qbdispatch:hydrate')

    if type(data) ~= 'table' or not data.service then
        -- Tablet first: it reads the state that setService(nil) is about to
        -- clear, and releasing NUI focus is the one step that must not be
        -- skipped when a player goes off duty with it open.
        Dispatch.ui.setTablet(false)
        Dispatch.state.setService(nil)
        Dispatch.blip.clear()
        Dispatch.blip.clearCalls()
        Dispatch.ui.render()
        hydrating = false
        return
    end

    Dispatch.state.syncClock(data.now)
    Dispatch.state.setService(data.service, data.unit, data.config)
    Dispatch.state.replaceAll(data.calls)
    Dispatch.blip.refreshCalls()
    Dispatch.theme.refresh()
    Dispatch.ui.render()
    hydrating = false
end

Dispatch.hydrate = function() CreateThread(hydrate) end

RegisterNetEvent('qbdispatch:client:call', function(call, serverNow)
    if not Dispatch.state.isActive() then return end
    Dispatch.state.syncClock(serverNow)

    local isNew = Dispatch.state.upsert(call)
    Dispatch.blip.refreshCalls()
    Dispatch.ui.render()

    if not isNew then return end

    if Config.alerts and Config.alerts.notify then
        QB.notify.send({
            title = call.code and ('Dispatch ' .. call.code) or 'New dispatch call',
            message = call.title or call.message or 'A new call is waiting.',
            type = call.priority == 1 and 'error' or (call.priority == 2 and 'warning' or 'info'),
            duration = Config.alerts.duration,
            icon = call.icon or 'radio',
        })
    end

    -- Hiding the feed is a presentation preference, not an acknowledgement:
    -- the new-call toast and native map marker above still reach the officer.
    if Dispatch.state.data.hidden then return end

    -- A call may carry its own tone; otherwise the service's; otherwise the
    -- fallback. Most specific first, so a silent alarm can sound different from
    -- a routine call without reconfiguring the whole service.
    local serviceConfig = Dispatch.state.data.config
    local sound = call.sound or (serviceConfig and serviceConfig.sound) or Config.defaultService.sound
    if type(sound) == 'table' and sound.name and sound.set then
        QB.sound.playFrontend(sound.name, sound.set)
    end
end)

RegisterNetEvent('qbdispatch:client:callUpdated', function(call, serverNow)
    if not Dispatch.state.isActive() then return end
    Dispatch.state.syncClock(serverNow)
    Dispatch.state.upsert(call)
    Dispatch.blip.onCallChanged(call)
    Dispatch.ui.render()
end)

RegisterNetEvent('qbdispatch:client:units', function(units)
    if not Dispatch.state.isActive() then return end
    Dispatch.state.setUnits(units)
    -- Only the tablet draws colleague markers, so a heartbeat arriving with the
    -- tablet closed is stored and not re-rendered.
    if Dispatch.state.data.tabletOpen then Dispatch.ui.render() end
end)

-- --- lifecycle --------------------------------------------------------------

RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function() Dispatch.hydrate() end)
RegisterNetEvent('QBCore:Client:OnJobUpdate', function() Dispatch.hydrate() end)
RegisterNetEvent('QBCore:Client:SetDuty', function() Dispatch.hydrate() end)

RegisterNetEvent('QBCore:Client:OnPlayerUnload', function()
    Dispatch.ui.setTablet(false)
    Dispatch.state.setService(nil)
    Dispatch.blip.clear()
    Dispatch.blip.clearCalls()
    Dispatch.ui.render()
end)

AddEventHandler('onClientResourceStart', function(resource)
    if resource == 'qblib' then Dispatch.ui.render(); return end
    if resource ~= GetCurrentResourceName() then return end
    -- A resource restart mid-session has no login event to wait for, so hydrate
    -- directly. The short wait lets qbcore's client mirror finish priming first.
    CreateThread(function()
        Wait(1000)
        hydrate()
    end)
end)
