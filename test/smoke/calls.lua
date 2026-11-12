-- shared/calls.lua -- payload normalisation, the expiry/fade model, and the unit
-- state machine. All pure; no store, no network.
local h = dofile('test/harness.lua')
local mocks = dofile('test/mocks.lua'); mocks.install()
dofile('config.lua')
dofile('shared/calls.lua')

local OPTS = { priorities = Config.priorities, defaultPriority = Config.defaultPriority }

h.test('a minimal payload normalises', function()
    local call, err = Dispatch.calls.normalise({ jobTypes = { 'leo' }, title = 'Robbery' }, OPTS)
    h.assertTrue(call ~= nil, 'should normalise: ' .. tostring(err))
    h.assertEqual(call.title, 'Robbery', 'title carried through')
    h.assertEqual(call.priority, Config.defaultPriority, 'priority falls back to the default')
    h.assertEqual(call.ttl, Config.priorities[Config.defaultPriority].ttl, 'ttl comes from the priority')
    h.assertEqual(#call.jobTypes, 1, 'the job type is kept')
end)

h.test('legacy field aliases are accepted', function()
    -- A ps-dispatch/qb-phone era script should work by changing the export name
    -- and nothing else.
    local call = Dispatch.calls.normalise({
        job = 'police', description = 'Silent alarm', dispatchCode = '10-90',
    }, OPTS)

    h.assertEqual(call.message, 'Silent alarm', 'description is an alias for message')
    h.assertEqual(call.code, '10-90', 'dispatchCode is an alias for code')
    h.assertEqual(call.jobs[1], 'police', 'job is an alias for jobs')
    h.assertEqual(call.title, 'Silent alarm', 'a call with no title falls back to its message')
end)

h.test('a string or an array is accepted for jobs and jobTypes', function()
    h.assertEqual(#Dispatch.calls.normalise({ jobs = 'police', title = 'x' }, OPTS).jobs, 1, 'a bare string works')
    local many = Dispatch.calls.normalise({ jobs = { 'police', 'sheriff', 'police' }, title = 'x' }, OPTS)
    h.assertEqual(#many.jobs, 2, 'duplicates are collapsed')
end)

h.test('a payload with no target is refused', function()
    local call, err = Dispatch.calls.normalise({ title = 'Nobody hears this' }, OPTS)
    h.assertFalse(call, 'a call with no job or job type must be refused')
    h.assertTrue(err:find('at least one', 1, true) ~= nil, 'and say so')
end)

h.test('a payload with no title and no message is refused', function()
    local call = Dispatch.calls.normalise({ jobTypes = { 'leo' } }, OPTS)
    h.assertFalse(call, 'an alert with nothing to display is not an alert')
end)

h.test('malformed fields are refused rather than coerced', function()
    h.assertFalse(Dispatch.calls.normalise({ jobs = { 1, 2 }, title = 'x' }, OPTS), 'numeric job names')
    h.assertFalse(Dispatch.calls.normalise({ jobs = 'police', title = 42 }, OPTS), 'numeric title')
    h.assertFalse(Dispatch.calls.normalise({ jobs = 'police', title = 'x', duration = -5 }, OPTS), 'negative duration')
    h.assertFalse(Dispatch.calls.normalise('not a table', OPTS), 'a non-table payload')
end)

h.test('an out-of-range priority falls back instead of erroring', function()
    -- A robbery script passing priority 0 or 9 should still raise its alert.
    h.assertEqual(Dispatch.calls.normalise({ jobs = 'police', title = 'x', priority = 99 }, OPTS).priority,
        Config.defaultPriority, 'an unknown priority falls back')
    h.assertEqual(Dispatch.calls.normalise({ jobs = 'police', title = 'x', priority = 1 }, OPTS).priority,
        1, 'a valid priority is honoured')
end)

h.test('an explicit duration overrides the priority ttl', function()
    local call = Dispatch.calls.normalise({ jobs = 'police', title = 'x', priority = 3, duration = 999000 }, OPTS)
    h.assertEqual(call.ttl, 999000, 'the explicit duration wins')
end)

h.test('coords are coerced to a plain table', function()
    local call = Dispatch.calls.normalise({ jobs = 'police', title = 'x', coords = { x = 1, y = 2, z = 3 } }, OPTS)
    h.assertEqual(call.coords.x, 1.0, 'x')
    h.assertEqual(call.coords.z, 3.0, 'z')

    local noZ = Dispatch.calls.toCoords({ x = 1, y = 2 })
    h.assertEqual(noZ.z, 0.0, 'a missing z defaults to 0 rather than nil')
    h.assertEqual(Dispatch.calls.toCoords({ y = 2 }), nil, 'an incomplete point is nil, not a partial table')
    h.assertEqual(Dispatch.calls.toCoords('nope'), nil, 'a non-table is nil')
end)

local function callAt(created, ttl)
    return { createdAt = created, expiresAt = created + ttl }
end

h.test('a call is live until its expiry and never after being closed', function()
    local call = callAt(0, 1000)
    h.assertTrue(Dispatch.calls.isLive(call, 0), 'live at creation')
    h.assertTrue(Dispatch.calls.isLive(call, 999), 'live one tick before expiry')
    h.assertFalse(Dispatch.calls.isLive(call, 1000), 'not live at expiry')

    local closed = callAt(0, 1000); closed.closedAt = 10
    h.assertFalse(Dispatch.calls.isLive(closed, 0), 'a closed call is never live, even before its expiry')
end)

h.test('severity decides how long a call survives', function()
    -- The whole point of the priority ttls: a carjacking is stale in two
    -- minutes, a bank robbery still matters ten minutes later.
    local carjacking = callAt(0, Config.priorities[3].ttl)
    local robbery = callAt(0, Config.priorities[1].ttl)
    local atFiveMinutes = 5 * 60 * 1000

    h.assertFalse(Dispatch.calls.isLive(carjacking, atFiveMinutes), 'the routine call has gone')
    h.assertTrue(Dispatch.calls.isLive(robbery, atFiveMinutes), 'the critical one has not')
end)

h.test('opacity holds full then eases out', function()
    local call = callAt(0, 1000)
    local hold = 0.6 -- full opacity for the first 60% of life

    h.assertEqual(Dispatch.calls.opacity(call, 0, hold), 1.0, 'full at creation')
    h.assertEqual(Dispatch.calls.opacity(call, 600, hold), 1.0, 'still full at the end of the hold')
    h.assertTrue(Dispatch.calls.opacity(call, 800, hold) < 1.0, 'fading after the hold')
    h.assertTrue(Dispatch.calls.opacity(call, 800, hold) > 0.0, 'but not gone yet')
    h.assertEqual(Dispatch.calls.opacity(call, 1000, hold), 0.0, 'gone at expiry')
    h.assertEqual(Dispatch.calls.opacity(call, 99999, hold), 0.0, 'and stays gone past expiry, never negative')
end)

h.test('remainingFraction is clamped to 0..1', function()
    local call = callAt(100, 1000)
    h.assertEqual(Dispatch.calls.remainingFraction(call, 50), 1.0, 'clamped above at 1')
    h.assertEqual(Dispatch.calls.remainingFraction(call, 5000), 0.0, 'clamped below at 0')
    h.assertEqual(Dispatch.calls.remainingFraction({ createdAt = 0, expiresAt = 0 }, 0), 0.0,
        'a zero-length call does not divide by zero')
end)

h.test('respond walks unattached -> en route -> on scene -> clear', function()
    h.assertEqual(Dispatch.calls.nextState(nil), 'en_route', 'the first press attaches you')
    h.assertEqual(Dispatch.calls.nextState('en_route'), 'on_scene', 'the second marks arrival')
    h.assertEqual(Dispatch.calls.nextState('on_scene'), 'clear', 'the third clears')
    h.assertEqual(Dispatch.calls.nextState('clear'), nil, 'a cleared unit detaches rather than cycling round')
end)

h.test('only the real states are valid', function()
    h.assertTrue(Dispatch.calls.isValidState('on_scene'), 'a real state')
    h.assertFalse(Dispatch.calls.isValidState('busy'), 'an invented state')
    h.assertFalse(Dispatch.calls.isValidState(nil), 'nil is not a state')
end)

h.test('isCallable accepts a cross-resource callable table', function()
    h.assertTrue(Dispatch.calls.isCallable(function() end), 'a plain function')
    h.assertTrue(Dispatch.calls.isCallable(setmetatable({}, { __call = function() end })),
        'a __call table, which is what a function looks like after crossing an exports boundary')
    h.assertFalse(Dispatch.calls.isCallable({}), 'a plain table')
end)

h.report('calls')
