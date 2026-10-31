-- Receiving a newly pushed dispatch call must visibly acknowledge it even with
-- the tablet/feed hidden. Hydrating an existing backlog intentionally bypasses
-- this client event, and duplicate pushes of the same call stay quiet.
local h = dofile('test/harness.lua')
local mocks = dofile('test/mocks.lua'); mocks.install()
dofile('config.lua')

local notices, refreshes, sounds = {}, 0, 0
Kora.notify = { send = function(payload) notices[#notices + 1] = payload end }
Kora.sound = { playFrontend = function() sounds = sounds + 1 end }

dofile('client/state.lua')
Dispatch.ui = { render = function() end, setTablet = function() end }
Dispatch.theme = { refresh = function() end }
Dispatch.blip = {
    refreshCalls = function() refreshes = refreshes + 1 end,
    clear = function() end,
    clearCalls = function() end,
    onCallChanged = function() end,
}
dofile('client/sync.lua')

Dispatch.state.setService('leo', { src = 1 }, { sound = { name = 'tone', set = 'set' } })

local function call(id)
    return {
        id = id, code = '10-90', title = 'Bank Robbery', message = 'Silent alarm', priority = 1,
        createdAt = 0, expiresAt = 60000, coords = { x = 1, y = 2, z = 3 }, units = {},
    }
end

h.test('a new call shows a dispatch toast and refreshes map markers', function()
    TriggerEvent('qbdispatch:client:call', call(1), 0)

    h.assertEqual(#notices, 1, 'one visible notification is sent')
    h.assertEqual(notices[1].title, 'Dispatch 10-90', 'the radio code identifies the call')
    h.assertEqual(notices[1].message, 'Bank Robbery', 'the call title is shown')
    h.assertEqual(notices[1].type, 'error', 'critical calls use the urgent notification style')
    h.assertEqual(refreshes, 1, 'the native map marker is refreshed')
    h.assertEqual(sounds, 1, 'the existing alert tone still plays')
end)

h.test('hidden feed still acknowledges new calls, duplicate pushes do not', function()
    Dispatch.state.setHidden(true)
    TriggerEvent('qbdispatch:client:call', call(2), 0)
    TriggerEvent('qbdispatch:client:call', call(2), 0)

    h.assertEqual(#notices, 2, 'a hidden feed does not suppress the new-call toast')
    h.assertEqual(refreshes, 3, 'both pushes keep the marker state current')
    h.assertEqual(sounds, 1, 'a hidden feed and duplicate call stay silent')
end)

h.report('call_alerts')
