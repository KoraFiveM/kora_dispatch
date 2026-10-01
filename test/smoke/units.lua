-- The colleague heartbeat: what it reads, who it reaches, and when it runs at
-- all. Every native touched here has to exist on the SERVER -- the mock
-- deliberately omits the client-only ones so a regression fails loudly.
local h = dofile('test/harness.lua')
local mocks = dofile('test/mocks.lua'); local net = mocks.install()
dofile('config.lua')
dofile('shared/calls.lua')
dofile('server/store.lua')
dofile('server/recipients.lua')
dofile('server/api.lua')
dofile(arg[1] or 'server/units.lua')

net.setPlayer(1, 'police', true, { name = 'Jane Doe', callsign = '1-ADAM-12' })
net.setPlayer(2, 'sheriff', true, { name = 'Sam Reed', callsign = 'S-01' })
net.setPlayer(3, 'ambulance', true, { name = 'Mia Chen', callsign = 'MED-3' })

local function unitPushes()
    return net.eventsNamed('qbdispatch:client:units')
end

h.test('with nobody viewing, the heartbeat does no work at all', function()
    net.clearEvents()
    Dispatch.units.tick()

    h.assertEqual(#unitPushes(), 0, 'an idle server must pay nothing for this feature')
    h.assertEqual(Dispatch.units.viewerCount(), 0, 'and hold no viewers')
end)

h.test('a viewer receives their own service roster, including themselves', function()
    net.clearEvents()
    Dispatch.units.setViewer(1, 'leo')
    Dispatch.units.tick()

    local pushes = unitPushes()
    h.assertEqual(#pushes, 1, 'exactly one push, to the one viewer')
    h.assertEqual(pushes[1].target, 1, 'addressed to the viewer')

    local units = pushes[1].args[1]
    h.assertEqual(#units, 2, 'both on-duty LEO units')

    -- The viewer is included on purpose: the map draws them as "you" and the
    -- call detail measures distance from their position.
    local sawSelf = false
    for _, unit in ipairs(units) do
        if unit.src == 1 then sawSelf = true end
        h.assertTrue(unit.job ~= 'ambulance', 'a LEO viewer never sees EMS positions')
    end
    h.assertTrue(sawSelf, 'the viewer is in their own list')
end)

h.test('a snapshot carries what the map needs and reads only SERVER natives', function()
    net.clearEvents()
    Dispatch.units.setViewer(1, 'leo')
    Dispatch.units.tick()

    local unit = unitPushes()[1].args[1][1]
    h.assertTrue(unit.coords ~= nil, 'position')
    h.assertTrue(unit.heading ~= nil, 'heading')
    h.assertEqual(unit.callsign ~= nil, true, 'callsign for the map label')
    h.assertEqual(unit.vehicle, 'foot', 'a unit not in a vehicle is on foot')
end)

h.test('a unit in a vehicle reports its type, plate and speed', function()
    net.setVehicle(1, 500, 'heli')
    net.clearEvents()
    Dispatch.units.setViewer(1, 'leo')
    Dispatch.units.tick()

    local units = unitPushes()[1].args[1]
    local self
    for _, unit in ipairs(units) do if unit.src == 1 then self = unit end end

    -- The icon key is grouped from GetVehicleType, a server native.
    -- GetVehicleClass is client-only and is not defined in the mock at all.
    h.assertEqual(self.vehicle, 'heli', 'the air unit is drawn as a helicopter')
    h.assertEqual(self.plate, 'TEST123', 'the plate rides along for the tooltip')
    h.assertTrue(self.speed > 0, 'and a speed readout')

    net.setVehicle(1, nil, nil)
end)

h.test('each service is broadcast only to its own viewers', function()
    net.clearEvents()
    Dispatch.units.setViewer(1, 'leo')
    Dispatch.units.setViewer(3, 'ems')
    Dispatch.units.tick()

    local byTarget = {}
    for _, push in ipairs(unitPushes()) do byTarget[push.target] = push.args[1] end

    h.assertEqual(#byTarget[1], 2, 'the officer sees the two LEO units')
    h.assertEqual(#byTarget[3], 1, 'the paramedic sees only EMS')
    h.assertEqual(byTarget[3][1].job, 'ambulance', 'and never a police position')
end)

h.test('closing the tablet stops the work for that viewer', function()
    Dispatch.units.setViewer(1, 'leo')
    Dispatch.units.setViewer(1, nil)
    Dispatch.units.setViewer(3, nil) -- still viewing from the previous test

    net.clearEvents()
    Dispatch.units.tick()

    h.assertEqual(#unitPushes(), 0, 'no viewers left, no broadcast')
end)

h.test('maxDistance limits a viewer to nearby colleagues but never hides them from themselves', function()
    net.setCoords(1, { x = 100.0, y = 200.0, z = 30.0 })
    net.setCoords(2, { x = 500.0, y = 200.0, z = 30.0 })
    Config.units.maxDistance = 100
    net.clearEvents()
    Dispatch.units.setViewer(1, 'leo')
    Dispatch.units.tick()

    local units = unitPushes()[1].args[1]
    h.assertEqual(#units, 1, 'a colleague outside the configured radius is filtered out')
    local sawSelf = false
    for _, unit in ipairs(units) do if unit.src == 1 then sawSelf = true end end
    h.assertTrue(sawSelf, 'the viewer is never filtered out of their own list')

    Config.units.maxDistance = 0
    net.setCoords(1, nil)
    net.setCoords(2, nil)
    Dispatch.units.setViewer(1, nil)
end)

local function resetViewers()
    for src, job in ipairs({ 'police', 'sheriff', 'ambulance' }) do
        Dispatch.units.setViewer(src, nil)
        net.setPlayer(src, job, true)
    end
    net.clearEvents()
end

h.test('the heartbeat removes off-duty or missing viewers without relying on client close', function()
    resetViewers()
    Dispatch.units.setViewer(1, 'leo'); Dispatch.units.setViewer(2, 'leo'); Dispatch.units.setViewer(3, 'ems')
    net.setPlayer(1, 'police', false); net.removePlayer(3)
    Dispatch.units.tick()
    h.assertEqual(#unitPushes(), 1, 'only the still-authorised viewer receives positions')
    h.assertEqual(unitPushes()[1].target, 2, 'the on-duty colleague keeps their map')
    h.assertEqual(Dispatch.units.viewerCount(), 1, 'stale subscriptions are removed')
    net.setPlayer(1, 'police', true)
    net.clearEvents(); Dispatch.units.tick()
    h.assertEqual(#unitPushes(), 1, 'returning on duty does not revive a retired subscription')
    Dispatch.units.setViewer(1, 'leo')
    net.clearEvents(); Dispatch.units.tick()
    h.assertEqual(#unitPushes(), 2, 'opening the map again restores normal delivery')
end)

h.test('a service change removes the old viewer and requires viewing their current service', function()
    resetViewers()
    Dispatch.units.setViewer(1, 'leo'); Dispatch.units.setViewer(2, 'leo')
    net.setPlayer(1, 'ambulance', true)
    Dispatch.units.tick()
    h.assertEqual(#unitPushes(), 1, 'the former officer no longer receives LEO positions')
    h.assertEqual(unitPushes()[1].target, 2, 'other officers remain subscribed')
    h.assertEqual(Dispatch.units.viewerCount(), 1, 'the obsolete service subscription is removed')
    Dispatch.units.setViewer(1, 'ems')
    net.clearEvents(); Dispatch.units.tick()
    local own
    for _, push in ipairs(unitPushes()) do if push.target == 1 then own = push.args[1] end end
    h.assertEqual(#own, 2, 'viewing the current service delivers its roster')
    for _, unit in ipairs(own) do h.assertEqual(unit.job, 'ambulance', 'current service only') end
end)

h.test('an on-duty department change within the same service retains the service map', function()
    resetViewers()
    Dispatch.units.setViewer(1, 'leo')
    net.setPlayer(1, 'sheriff', true)
    Dispatch.units.tick()
    h.assertEqual(#unitPushes(), 1, 'an authorised LEO viewer keeps receiving the shared map')
    h.assertEqual(#unitPushes()[1].args[1], 2, 'both current LEO units remain visible')
    h.assertEqual(Dispatch.units.viewerCount(), 1, 'same-service viewing stays registered')
end)

h.report('units')
