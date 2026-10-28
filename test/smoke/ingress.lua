-- Player-originated ingress: fixed registered incidents, resource ownership,
-- server-observed coordinates, cooldowns and the global live-call ceiling.
local h = dofile('test/harness.lua')
local mocks = dofile('test/mocks.lua'); local net = mocks.install()
dofile('config.lua')
dofile('shared/calls.lua')
dofile('server/store.lua')
dofile('server/recipients.lua')
dofile('server/api.lua')
dofile('server/ingress.lua')

net.setPlayer(1, 'unemployed', true)
net.setPlayer(2, 'police', true)
net.setInvokingResource('kora_police')

local definition = {
    jobTypes = { 'leo' }, code = '10-31', title = 'Shots Fired',
    message = 'Gunfire was reported nearby.', priority = 1, icon = 'crosshair',
    cooldown = 20000,
}

local ok, err = Dispatch.ingress.register('qbpolice:test-gunfire', definition)
assert(ok, err)

local function reset()
    Dispatch.store._reset()
    Dispatch.ingress._resetCooldowns()
end

h.test('a registered player alert uses fixed presentation and server coordinates', function()
    reset()
    local id = Dispatch.ingress.create(1, 'qbpolice:test-gunfire')
    h.assertTrue(id ~= false, 'the registered incident should be created')

    local call = Dispatch.api.getCall(id)
    h.assertEqual(call.title, 'Shots Fired', 'title comes from registration')
    h.assertEqual(call.coords.x, 100.0, 'position comes from the reporter ped')
    h.assertEqual(call.data.incident, 'qbpolice:test-gunfire', 'wire data identifies the allowlisted type')
    h.assertEqual(call.data.reporter, 1, 'wire data identifies the reporter')
end)

h.test('cooldowns are per player and alert type', function()
    reset()
    h.assertTrue(Dispatch.ingress.create(1, 'qbpolice:test-gunfire') ~= false, 'first request')

    local id, reason, remaining = Dispatch.ingress.create(1, 'qbpolice:test-gunfire')
    h.assertFalse(id, 'a repeated request is refused')
    h.assertEqual(reason, 'player alert is cooling down', 'with a stable reason')
    h.assertEqual(remaining, 20000, 'and an actionable remaining duration')

    h.assertTrue(Dispatch.ingress.create(2, 'qbpolice:test-gunfire') ~= false,
        "one player's cooldown does not mute another")
    net.advance(20001)
    h.assertTrue(Dispatch.ingress.create(1, 'qbpolice:test-gunfire') ~= false,
        'the original reporter can raise a genuinely new incident later')
end)

h.test('an unregistered or foreign-owned incident cannot be raised', function()
    reset()
    h.assertFalse(Dispatch.ingress.create(1, 'qbpolice:not-real'), 'unknown keys fail closed')

    net.setInvokingResource('kora_ambulance')
    local id, reason = Dispatch.ingress.create(1, 'qbpolice:test-gunfire')
    h.assertFalse(id, 'another resource cannot borrow a registered incident')
    h.assertTrue(reason:find('does not own', 1, true) ~= nil, 'ownership denial is explicit')
    net.setInvokingResource('kora_police')
end)

h.test('an untrusted resource cannot consume registry capacity', function()
    net.setInvokingResource('untrusted-resource')
    local registered, reason = net.registeredExports.registerPlayerAlert('untrusted:test', definition, 'kora_police')
    h.assertFalse(registered, 'registration is denied')
    h.assertTrue(reason:find('not allowed', 1, true) ~= nil,
        'a forged third owner argument is not forwarded by the export')
    net.setInvokingResource('kora_police')
end)

h.test('a job-type entitlement is checked centrally when configured', function()
    local entitled = {}
    for field, value in pairs(definition) do entitled[field] = value end
    entitled.requiredJobType = 'leo'
    local registered, reason = Dispatch.ingress.register('qbpolice:officer-only', entitled)
    h.assertTrue(registered, reason)

    h.assertFalse(Dispatch.ingress.create(1, 'qbpolice:officer-only'),
        'a civilian cannot raise an officer-only alert')
    h.assertTrue(Dispatch.ingress.create(2, 'qbpolice:officer-only') ~= false,
        'an on-duty LEO can raise it')
end)

h.test('the global live-call ceiling bounds public fanout state', function()
    reset()
    local previous = Config.ingress.maxLiveCalls
    Config.ingress.maxLiveCalls = 1

    h.assertTrue(Dispatch.ingress.create(1, 'qbpolice:test-gunfire') ~= false, 'first live call')
    local id, reason = Dispatch.ingress.create(2, 'qbpolice:test-gunfire')
    h.assertFalse(id, 'the next public call is refused at capacity')
    h.assertEqual(reason, 'player alert capacity reached', 'with a stable reason')

    Config.ingress.maxLiveCalls = previous
end)

h.test('free-form createCall is restricted to trusted resources', function()
    reset()
    net.setInvokingResource('untrusted-resource')
    local id, reason = Dispatch.api.createCall({ jobTypes = { 'leo' }, title = 'Forged' })
    h.assertFalse(id, 'an untrusted resource is denied')
    h.assertTrue(reason:find('not allowed', 1, true) ~= nil, 'and told why')
    net.setInvokingResource('kora_police')
end)

h.test('resource stop removes its registered incident types', function()
    net.setInvokingResource('temporary-alert-resource')
    Config.trustedCallers['temporary-alert-resource'] = true
    local registered = Dispatch.ingress.register('temporary:test', definition)
    h.assertTrue(registered, 'temporary resource registered')

    TriggerEvent('onResourceStop', 'temporary-alert-resource')
    local id = Dispatch.ingress.create(1, 'temporary:test')
    h.assertFalse(id, 'the stale type is gone after its owner stops')
    Config.trustedCallers['temporary-alert-resource'] = nil
    net.setInvokingResource('kora_police')
end)

h.report('ingress')
