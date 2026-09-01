-- Legacy inbound: the events a resource written against qb-policejob or
-- qb-ambulancejob already fires, turned into real dispatch calls.
local h = dofile('test/harness.lua')
local mocks = dofile('test/mocks.lua'); local net = mocks.install()
dofile('config.lua')

-- Legacy inbound ships OFF (a job resource usually owns those event names, and
-- qbcore re-fires police:server:policeAlert itself -- see the Config comment).
-- Enabled here because this suite is what proves the code path works when a
-- server does turn it on.
Config.compat.legacyInbound = true

dofile('shared/calls.lua')
dofile('server/store.lua')
dofile('server/recipients.lua')
dofile('server/api.lua')
dofile('server/compat.lua')

net.setPlayer(1, 'police', true, { name = 'Jane Doe' })
net.setPlayer(2, 'ambulance', true, { name = 'Mia Chen' })

local function newest(service)
    return Dispatch.api.getCalls({ service = service })[1]
end

h.test('the legacy police alert becomes a leo call', function()
    Dispatch.store._reset()
    _G.source = 1
    TriggerEvent('police:server:policeAlert', 'Shots fired at the bank')

    local call = newest('leo')
    h.assertTrue(call ~= nil, 'a call should have been raised')
    h.assertEqual(call.message, 'Shots fired at the bank', 'the legacy text becomes the message')
    h.assertEqual(call.service, 'leo', 'routed to law enforcement')
    h.assertEqual(call.priority, 1, 'an officer alert is critical')
end)

h.test('the legacy ambulance alert becomes an ems call', function()
    Dispatch.store._reset()
    _G.source = 2
    TriggerEvent('hospital:server:ambulanceAlert', 'Civilian down')

    local call = newest('ems')
    h.assertTrue(call ~= nil, 'a call should have been raised')
    h.assertEqual(call.service, 'ems', 'routed to EMS, never to police')
    h.assertEqual(#Dispatch.api.getCalls({ service = 'leo' }), 0, 'and only to EMS')
end)

h.test('both legacy argument orders are handled', function()
    -- Real qb-policejob fires (coords, text); qbcore's own compat table fires
    -- (message, coords). Both are live on this server at once, and getting it
    -- wrong silently swaps a call's description with its coordinates.
    Dispatch.store._reset()
    _G.source = 1

    TriggerEvent('police:server:policeAlert', 'message first', { x = 1, y = 2, z = 3 })
    local a = newest('leo')
    h.assertEqual(a.message, 'message first', 'string-first form: the string is the message')
    h.assertEqual(a.coords.x, 1.0, 'and the table is the coordinates')

    Dispatch.store._reset()
    TriggerEvent('police:server:policeAlert', { x = 7, y = 8, z = 9 }, 'coords first')
    local b = newest('leo')
    h.assertEqual(b.message, 'coords first', 'coords-first form: the string is still the message')
    h.assertEqual(b.coords.x, 7.0, 'and the table is still the coordinates')
end)

h.test('a legacy alert with no coordinates falls back to the caller position', function()
    Dispatch.store._reset()
    _G.source = 1
    TriggerEvent('police:server:policeAlert', 'no coords given')

    local call = newest('leo')
    h.assertTrue(call.coords ~= nil, 'the reporter position is used, matching the real resource')
    h.assertEqual(call.coords.x, 100.0, 'read server-side from their ped')
end)

h.test('qbcore alerts are mirrored exactly once', function()
    -- Core.dispatch.alert fires this once per alert. Mirroring off its CLIENT
    -- push instead would record the same incident once per recipient.
    Dispatch.store._reset()
    TriggerEvent('qbcore:server:dispatchAlert', {
        jobs = { 'police' }, title = 'Core alert', message = 'via exports.qbcore:alert',
    }, 1)

    h.assertEqual(#Dispatch.api.getCalls({ service = 'leo' }), 1, 'exactly one call recorded')
    h.assertEqual(newest('leo').title, 'Core alert', 'with the core payload intact')
end)

h.test('a malformed legacy payload is ignored, not fatal', function()
    Dispatch.store._reset()
    -- A robbery script mid-heist must not die because its alert was malformed.
    TriggerEvent('qbcore:server:dispatchAlert', 'not a table')
    TriggerEvent('qbcore:server:dispatchAlert', { jobs = {} })

    h.assertEqual(#Dispatch.api.getCalls({ service = 'leo' }), 0, 'nothing recorded, nothing thrown')
end)

h.report('compat')
