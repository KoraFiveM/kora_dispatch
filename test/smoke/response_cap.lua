-- Config.dispatch.maxActiveCalls: how many live calls one unit may be committed
-- to at once. The rule is deliberately asymmetric -- the ACCEPT is capped, every
-- other transition is not -- because a unit that hit the cap must still be able
-- to advance and clear the call holding it there. A cap that blocked `clear`
-- would deadlock the unit permanently on its first call.
local h = dofile('test/harness.lua')
local mocks = dofile('test/mocks.lua'); local net = mocks.install()
dofile('config.lua')
dofile('shared/calls.lua')
dofile('server/store.lua')
dofile('server/recipients.lua')
dofile('server/api.lua')

net.setPlayer(1, 'police', true, { name = 'Jane Doe', callsign = '1-ADAM-12' })
net.setPlayer(2, 'sheriff', true, { name = 'Sam Reed', callsign = 'S-01' })

local function call(title)
    return Dispatch.api.createCall({ jobTypes = { 'leo' }, title = title })
end

local function reset(cap)
    Dispatch.store._reset()
    Config.dispatch.maxActiveCalls = cap
end

h.test('a unit at the cap cannot accept a second call', function()
    reset(1)
    local a, b = call('A'), call('B')

    h.assertEqual(Dispatch.api.setUnitState(1, a), 'en_route', 'the first call is accepted')

    local state, err = Dispatch.api.setUnitState(1, b)
    h.assertFalse(state, 'the second accept is refused')
    h.assertEqual(err, 'you are already en route to a call', 'and says why, in words a player can act on')
    h.assertEqual(#Dispatch.api.getCall(b).units, 0, 'the refused call records no unit at all')
end)

h.test('the cap never blocks advancing or clearing the call already held', function()
    reset(1)
    local id = call('A')

    h.assertEqual(Dispatch.api.setUnitState(1, id), 'en_route', 'accept')
    h.assertEqual(Dispatch.api.setUnitState(1, id), 'on_scene', 'on scene, while at the cap')
    h.assertEqual(Dispatch.api.setUnitState(1, id), 'clear', 'and clear, while at the cap')
end)

h.test('clearing a call frees the unit to accept the next one', function()
    reset(1)
    local a, b = call('A'), call('B')

    Dispatch.api.setUnitState(1, a) -- en route
    Dispatch.api.setUnitState(1, a) -- on scene
    Dispatch.api.setUnitState(1, a) -- clear

    h.assertEqual(Dispatch.api.setUnitState(1, b), 'en_route',
        'a cleared call must not keep counting against the cap')
end)

h.test('detaching frees the unit too', function()
    reset(1)
    local a, b = call('A'), call('B')

    Dispatch.api.setUnitState(1, a)
    h.assertFalse(Dispatch.api.setUnitState(1, a, false), 'detach reports no state')
    h.assertEqual(Dispatch.api.setUnitState(1, b), 'en_route', 'and releases the cap')
end)

h.test('a closed call stops counting against the cap', function()
    reset(1)
    local a, b = call('A'), call('B')

    Dispatch.api.setUnitState(1, a)
    Dispatch.api.closeCall(a)

    h.assertEqual(Dispatch.api.setUnitState(1, b), 'en_route',
        'a unit is not held hostage by a call dispatch has already closed')
end)

h.test('the cap is per player, not per call', function()
    reset(1)
    local id = call('A')

    h.assertEqual(Dispatch.api.setUnitState(1, id), 'en_route', 'the officer')
    h.assertEqual(Dispatch.api.setUnitState(2, id), 'en_route',
        'a second unit on the SAME call is fine -- the cap counts calls per unit')
end)

h.test('a higher cap allows exactly that many', function()
    reset(2)
    local a, b, c = call('A'), call('B'), call('C')

    h.assertEqual(Dispatch.api.setUnitState(1, a), 'en_route', 'first')
    h.assertEqual(Dispatch.api.setUnitState(1, b), 'en_route', 'second')

    local state, err = Dispatch.api.setUnitState(1, c)
    h.assertFalse(state, 'third refused at a cap of 2')
    h.assertEqual(err, 'you are already en route to 2 calls', 'the reason counts correctly')
end)

h.test('a cap of 0 disables the check', function()
    reset(0)
    local a, b, c = call('A'), call('B'), call('C')

    h.assertEqual(Dispatch.api.setUnitState(1, a), 'en_route', 'first')
    h.assertEqual(Dispatch.api.setUnitState(1, b), 'en_route', 'second')
    h.assertEqual(Dispatch.api.setUnitState(1, c), 'en_route', 'third -- uncapped')
end)

h.test('countAttached ignores the call being advanced', function()
    reset(1)
    local id = call('A')
    Dispatch.api.setUnitState(1, id)

    h.assertEqual(Dispatch.store.countAttached(1), 1, 'counted normally')
    h.assertEqual(Dispatch.store.countAttached(1, id), 0,
        'excluded when asked to ignore it -- this is what lets a held call advance')
end)

h.report('response_cap')
