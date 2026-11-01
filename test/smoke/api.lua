-- The server API end to end: recipient resolution, the single-service rule, the
-- store's retention, and the unit state machine over the wire.
local h = dofile('test/harness.lua')
local mocks = dofile('test/mocks.lua'); local net = mocks.install()
dofile('config.lua')
dofile('shared/calls.lua')
dofile('server/store.lua')
dofile('server/recipients.lua')
dofile('server/api.lua')

-- Two LEO (one of each LEO job), one EMS, one off-duty cop, one civilian.
net.setPlayer(1, 'police', true, { name = 'Jane Doe', callsign = '1-ADAM-12' })
net.setPlayer(2, 'sheriff', true, { name = 'Sam Reed', callsign = 'S-01' })
net.setPlayer(3, 'ambulance', true, { name = 'Mia Chen', callsign = 'MED-3' })
net.setPlayer(4, 'police', false, { name = 'Off Duty' })
net.setPlayer(5, 'unemployed', true, { name = 'A Civilian' })

local function targets(name)
    local out = {}
    for _, e in ipairs(net.eventsNamed(name)) do out[#out + 1] = e.target end
    table.sort(out)
    return out
end

local function equalList(actual, expected, message)
    h.assertEqual(#actual, #expected, message .. ' (count)')
    for i = 1, #expected do h.assertEqual(actual[i], expected[i], message .. (' [%d]'):format(i)) end
end

h.test('a job type reaches every job carrying it', function()
    net.clearEvents()
    local id, count = Dispatch.api.createCall({ jobTypes = { 'leo' }, title = 'Robbery', priority = 1 })

    h.assertTrue(id ~= false, 'the call should be created: ' .. tostring(count))
    h.assertEqual(count, 2, 'both the on-duty officer and the on-duty deputy')
    equalList(targets('qbdispatch:client:call'), { 1, 2 }, 'police and sheriff, not the off-duty cop')
end)

h.test('a specific job reaches only that job', function()
    net.clearEvents()
    local _, count = Dispatch.api.createCall({ jobs = { 'police' }, title = 'Police only' })

    h.assertEqual(count, 1, 'only the on-duty police officer')
    equalList(targets('qbdispatch:client:call'), { 1 }, 'the deputy is a different job')
end)

h.test('off-duty and unrelated players never receive a call', function()
    net.clearEvents()
    Dispatch.api.createCall({ jobTypes = { 'leo' }, title = 'Nobody else' })

    for _, target in ipairs(targets('qbdispatch:client:call')) do
        h.assertTrue(target ~= 4, 'the off-duty officer must not be alerted')
        h.assertTrue(target ~= 5, 'the civilian must never see call content')
    end
end)

h.test('a call targeting two services is refused, not silently split', function()
    -- The user-facing rule: there is no 'emergency' service. A scene needing
    -- police and paramedics is two calls, so that each service can word it their
    -- own way and clear it independently.
    local id, err = Dispatch.api.createCall({ jobTypes = { 'leo', 'ems' }, title = 'Both' })

    h.assertFalse(id, 'a mixed-service call must be refused')
    h.assertTrue(err:find('exactly one service', 1, true) ~= nil, 'and explain the rule: ' .. tostring(err))
    h.assertTrue(err:find('one call per service', 1, true) ~= nil, 'and say what to do instead')
end)

h.test('mixing a job and a job type from the same service is fine', function()
    local id, count = Dispatch.api.createCall({ jobs = { 'police' }, jobTypes = { 'leo' }, title = 'Same service' })
    h.assertTrue(id ~= false, 'police is leo, so this is one service: ' .. tostring(count))
end)

h.test('an unknown job or an unreachable job type is refused', function()
    local id, err = Dispatch.api.createCall({ jobs = { 'wizard' }, title = 'x' })
    h.assertFalse(id, 'an unregistered job must be refused')
    h.assertTrue(err:find('wizard', 1, true) ~= nil, 'and name it')

    -- The classic typo: passing a job name where a type belongs. Accepting it as
    -- an empty call would be a silent failure the caller never notices.
    local id2, err2 = Dispatch.api.createCall({ jobTypes = { 'police' }, title = 'x' })
    h.assertFalse(id2, 'a job name passed as a type must be refused')
    h.assertTrue(err2:find('no registered job', 1, true) ~= nil, 'and explain why: ' .. tostring(err2))
end)

h.test('a call with nobody on duty still records, and reports zero recipients', function()
    net.clearEvents()
    local id, count = Dispatch.api.createCall({ jobTypes = { 'recovery' }, title = 'Tow needed' })

    h.assertTrue(id ~= false, 'the call is still logged for whoever comes on duty next')
    h.assertEqual(count, 0, 'and the caller can tell nobody heard it')
end)

h.test('the wire form exposes what a UI needs and nothing internal', function()
    local id = Dispatch.api.createCall({
        jobTypes = { 'leo' }, code = '10-90', title = 'Bank Robbery',
        message = 'Silent alarm', priority = 1, coords = { x = 1, y = 2, z = 3 },
        data = { plate = 'ABC123' },
    })
    local wire = Dispatch.api.getCall(id)

    h.assertEqual(wire.code, '10-90', 'code')
    h.assertEqual(wire.priority, 1, 'priority')
    h.assertEqual(wire.service, 'leo', 'resolved service')
    h.assertEqual(wire.data.plate, 'ABC123', 'freeform data passes through untouched')
    h.assertEqual(type(wire.units), 'table', 'units is an array for the UI')
    h.assertEqual(wire.jobs, nil, 'the resolved job list is server bookkeeping, not UI data')
    h.assertEqual(wire.onAccept, nil, 'the accept hook is an event name a client must not see')
end)

-- Config.dispatch.maxActiveCalls caps how many live calls one unit may be
-- committed to (shipped default: 1), so attachments LEAK between tests in this
-- file -- a unit left en route in one test is at the cap in the next and cannot
-- accept anything. These two helpers keep each scenario's starting state
-- explicit instead of depending on the order the tests happen to run in.
local function releaseAll()
    for src = 1, 5 do Dispatch.store.detachAll(src) end
end

---Runs `fn` with the cap temporarily set to `cap` (0 disables it), restoring the
---real configured value afterwards even if `fn` raises.
local function withCap(cap, fn)
    local previous = Config.dispatch.maxActiveCalls
    Config.dispatch.maxActiveCalls = cap
    local ok, err = pcall(fn)
    Config.dispatch.maxActiveCalls = previous
    if not ok then error(err, 0) end
end

h.test('respond advances a unit through the state machine', function()
    releaseAll()
    local id = Dispatch.api.createCall({ jobTypes = { 'leo' }, title = 'State test' })

    h.assertEqual(Dispatch.api.setUnitState(1, id), 'en_route', 'first press attaches')
    h.assertEqual(Dispatch.api.setUnitState(1, id), 'on_scene', 'second marks arrival')
    h.assertEqual(Dispatch.api.setUnitState(1, id), 'clear', 'third clears')

    local wire = Dispatch.api.getCall(id)
    h.assertEqual(#wire.units, 1, 'one unit attached')
    h.assertEqual(wire.units[1].state, 'clear', 'at the final state')
    h.assertEqual(wire.units[1].callsign, '1-ADAM-12', 'the roster callsign is cached on the call')
end)

h.test('a unit from another service cannot attach', function()
    local id = Dispatch.api.createCall({ jobTypes = { 'leo' }, title = 'Police business' })
    local state, err = Dispatch.api.setUnitState(3, id) -- the paramedic

    h.assertFalse(state, 'wrong service must be refused')
    h.assertEqual(err, 'wrong service for this call', 'and say why')
end)

h.test('an off-duty player cannot attach', function()
    local id = Dispatch.api.createCall({ jobTypes = { 'leo' }, title = 'x' })
    local state, err = Dispatch.api.setUnitState(4, id)

    h.assertFalse(state, 'off duty must be refused')
    h.assertEqual(err, 'not on duty', 'and say why')
end)

h.test('onAccept fires once, on the first attach only', function()
    -- A house-call queue hands out the job on accept. Firing again as the unit
    -- reports on scene would hand the same job to them a second time.
    local fired = 0
    AddEventHandler('qbdispatch:test:accepted', function() fired = fired + 1 end)

    local id = Dispatch.api.createCall({
        jobTypes = { 'ems' }, title = 'House call', onAccept = 'qbdispatch:test:accepted',
    })

    Dispatch.api.setUnitState(3, id)
    h.assertEqual(fired, 1, 'the accept hook fires on attach')

    Dispatch.api.setUnitState(3, id) -- on scene
    Dispatch.api.setUnitState(3, id) -- clear
    h.assertEqual(fired, 1, 'later progress reports are not fresh acceptances')
end)

h.test('going off duty detaches a unit from every call', function()
    releaseAll()
    local a = Dispatch.api.createCall({ jobTypes = { 'leo' }, title = 'A' })
    local b = Dispatch.api.createCall({ jobTypes = { 'leo' }, title = 'B' })

    -- Cap lifted deliberately: being attached to two calls at once is the exact
    -- state this test needs to prove detachAll clears, and the shipped cap of 1
    -- would otherwise refuse the second attach and make the assertion vacuous.
    withCap(0, function()
        Dispatch.api.setUnitState(1, a)
        Dispatch.api.setUnitState(1, b)
    end)

    h.assertEqual(#Dispatch.api.getCall(a).units, 1, 'attached to A')
    h.assertEqual(#Dispatch.api.getCall(b).units, 1, 'and to B')

    TriggerEvent('QBCore:Server:SetDuty', 1, false)

    h.assertEqual(#Dispatch.api.getCall(a).units, 0, 'a unit that went off duty is not still en route')
    h.assertEqual(#Dispatch.api.getCall(b).units, 0, 'on every call, not just one')

    net.setPlayer(1, 'police', true, { name = 'Jane Doe', callsign = '1-ADAM-12' })
end)

h.test('update revises an open call and re-pushes it', function()
    local id = Dispatch.api.createCall({ jobTypes = { 'leo' }, title = 'Pursuit', priority = 2 })
    net.clearEvents()

    h.assertTrue(Dispatch.api.updateCall(id, { message = 'Now a red Sultan' }), 'the update should apply')
    h.assertEqual(Dispatch.api.getCall(id).message, 'Now a red Sultan', 'the new detail is stored')
    h.assertTrue(#net.eventsNamed('qbdispatch:client:callUpdated') > 0, 'and pushed to recipients')
end)

h.test('update cannot move a call between services', function()
    local id = Dispatch.api.createCall({ jobTypes = { 'leo' }, title = 'x' })
    Dispatch.api.updateCall(id, { service = 'ems', jobs = { 'ambulance' }, id = 999 })

    local wire = Dispatch.api.getCall(id)
    h.assertEqual(wire.service, 'leo', 'service is identity, not a patchable field')
    h.assertEqual(wire.id, id, 'nor is the id')
end)

h.test('escalating priority extends the call to its new severity', function()
    local id = Dispatch.api.createCall({ jobTypes = { 'leo' }, title = 'x', priority = 3 })
    local before = Dispatch.api.getCall(id).expiresAt

    Dispatch.api.updateCall(id, { priority = 1 })
    local after = Dispatch.api.getCall(id)

    h.assertEqual(after.priority, 1, 'priority raised')
    h.assertTrue(after.expiresAt > before, 'a critical call now lives as long as a critical call should')
    h.assertEqual(after.expiresAt, after.createdAt + Config.priorities[1].ttl,
        'the deadline is rebased on creation, so elapsed time stays honest')
end)

h.test('closing removes a call from the live list but keeps it in history', function()
    Dispatch.store._reset()
    local id = Dispatch.api.createCall({ jobTypes = { 'leo' }, title = 'Resolved' })

    h.assertTrue(Dispatch.api.closeCall(id, 'suspect in custody'), 'close should succeed')
    h.assertEqual(#Dispatch.api.getCalls({ service = 'leo', activeOnly = true }), 0,
        'no live leo calls remain')
    h.assertEqual(Dispatch.api.getCall(id).closeReason, 'suspect in custody', 'the reason is retained')
    h.assertTrue(#Dispatch.api.getCalls({ service = 'leo' }) > 0, 'history still has it')
end)

h.test('a closed call cannot be updated or closed again', function()
    local id = Dispatch.api.createCall({ jobTypes = { 'leo' }, title = 'x' })
    Dispatch.api.closeCall(id)

    local ok, err = Dispatch.api.updateCall(id, { message = 'too late' })
    h.assertFalse(ok, 'a closed call is immutable')
    h.assertEqual(err, 'call is closed', 'and says so')
end)

h.test('closed and expired history calls cannot accept new responses', function()
    releaseAll()
    local closed = Dispatch.api.createCall({ jobTypes = { 'leo' }, title = 'Closed incident' })
    Dispatch.api.closeCall(closed)
    local closedState, closedErr = Dispatch.api.setUnitState(1, closed)
    h.assertFalse(closedState, 'a closed history entry cannot attach a unit')
    h.assertEqual(closedErr, 'call is no longer active', 'closed responses explain that the incident ended')
    local directState, directErr = Dispatch.store.setUnitState(closed, 1, 'en_route', { name = 'Jane Doe' })
    h.assertFalse(directState, 'the store also refuses a non-live attachment')
    h.assertEqual(directErr, 'call is no longer active', 'low-level writes enforce the same invariant')

    local expired = Dispatch.api.createCall({ jobTypes = { 'leo' }, title = 'Expired incident', duration = 1 })
    net.advance(2)
    local expiredState, expiredErr = Dispatch.api.setUnitState(1, expired)
    h.assertFalse(expiredState, 'an expired history entry cannot attach a unit')
    h.assertEqual(expiredErr, 'call is no longer active', 'expired responses explain that the incident ended')

    -- Cleanup remains available so duty changes and retention never strand an
    -- old unit record solely because the incident ended.
    h.assertFalse(Dispatch.api.setUnitState(1, closed, false), 'detaching from a closed call remains valid cleanup')
end)

h.test('a sibling job in the same service cannot attach to a narrower call', function()
    releaseAll()
    -- A call raised against jobs={'police'} never reached the sheriff's
    -- department, so a deputy must not appear on its unit list either --
    -- otherwise it shows responders who were never told about the incident.
    local id = Dispatch.api.createCall({ jobs = { 'police' }, title = 'Police only' })

    h.assertEqual(Dispatch.api.setUnitState(1, id), 'en_route', 'the invited officer can attach')

    local state, err = Dispatch.api.setUnitState(2, id) -- the deputy: same service, different job
    h.assertFalse(state, 'the uninvited department must be refused')
    h.assertEqual(err, 'this call was not sent to your department', 'and told why')
end)

h.test('a service-wide call admits every job in that service', function()
    releaseAll()
    local id = Dispatch.api.createCall({ jobTypes = { 'leo' }, title = 'All units' })

    h.assertEqual(Dispatch.api.setUnitState(1, id), 'en_route', 'the officer')
    h.assertEqual(Dispatch.api.setUnitState(2, id), 'en_route', 'and the deputy')
end)

h.test('a bad patch is reported, not raised out of the export', function()
    -- createCall/updateCall are called from gameplay code paths. A malformed
    -- patch must not crash the robbery script that sent it.
    local id = Dispatch.api.createCall({ jobTypes = { 'leo' }, title = 'x' })

    local ok, err = Dispatch.api.updateCall(id, { duration = 'soon' })
    h.assertFalse(ok, 'a non-numeric duration is refused')
    h.assertEqual(err, 'duration must be a positive number', 'with a reason')

    local ok2, err2 = Dispatch.api.updateCall(id, { priority = 99 })
    h.assertFalse(ok2, 'an unknown priority is refused')
    h.assertEqual(err2, 'unknown priority', 'with a reason')

    h.assertEqual(Dispatch.api.getCall(id).title, 'x', 'and the call is left untouched')
end)

h.test('the wire form carries a per-call sound but never the accept hook', function()
    local id = Dispatch.api.createCall({
        jobTypes = { 'leo' }, title = 'Silent alarm',
        sound = { name = 'Beep_Red', set = 'DLC_HEIST_HACKING_SNAKE_SOUNDS' },
        onAccept = 'some:server:event',
    })
    local wire = Dispatch.api.getCall(id)

    -- A silent alarm should not sound like a routine call.
    h.assertEqual(wire.sound.name, 'Beep_Red', 'the tone override reaches the client')
    -- onAccept is a server event name; a client has no business knowing it.
    h.assertEqual(wire.onAccept, nil, 'the accept hook stays server-side')
end)

h.test('operations on an unknown call fail cleanly', function()
    h.assertEqual(Dispatch.api.getCall(999999), nil, 'get')
    h.assertFalse(Dispatch.api.updateCall(999999, {}), 'update')
    h.assertFalse(Dispatch.api.closeCall(999999), 'close')
    h.assertFalse(Dispatch.api.setUnitState(1, 999999), 'respond')
end)

h.test('a call drops off the live list at its expiry but stays readable', function()
    Dispatch.store._reset()
    local id = Dispatch.api.createCall({ jobTypes = { 'leo' }, title = 'Carjacking', priority = 3 })

    h.assertEqual(#Dispatch.api.getCalls({ service = 'leo', activeOnly = true }), 1, 'live at first')

    net.advance(Config.priorities[3].ttl + 1)

    h.assertEqual(#Dispatch.api.getCalls({ service = 'leo', activeOnly = true }), 0, 'expired off the feed')
    h.assertEqual(Dispatch.api.getCall(id).title, 'Carjacking', 'but still in history')
end)

h.test('retention drops old dead calls but never a live one', function()
    Dispatch.store._reset()

    -- Fill well past the budget with routine calls, then let them all expire.
    for i = 1, Config.history.max + 10 do
        Dispatch.api.createCall({ jobTypes = { 'leo' }, title = 'Routine ' .. i, priority = 3 })
    end
    net.advance(Config.priorities[3].ttl + 1)

    -- One long-lived critical call raised now must survive the sweep whatever
    -- the backlog looks like.
    local critical = Dispatch.api.createCall({ jobTypes = { 'leo' }, title = 'Bank Robbery', priority = 1 })

    Dispatch.store.sweep()

    local all = Dispatch.api.getCalls({ service = 'leo' })
    h.assertTrue(#all <= Config.history.max + 1, 'retention keeps history bounded, got ' .. #all)
    h.assertTrue(Dispatch.api.getCall(critical) ~= nil,
        'a live critical call must never be evicted to make room for routine history')
end)

h.test('history older than its ttl is swept entirely', function()
    Dispatch.store._reset()
    local id = Dispatch.api.createCall({ jobTypes = { 'leo' }, title = 'Ancient', priority = 3 })

    net.advance(Config.priorities[3].ttl + Config.history.ttl + 1)
    Dispatch.store.sweep()

    h.assertEqual(Dispatch.api.getCall(id), nil, 'a call past the history ttl is gone for good')
end)

h.test('services keep separate histories', function()
    Dispatch.store._reset()
    Dispatch.api.createCall({ jobTypes = { 'leo' }, title = 'Police call' })
    Dispatch.api.createCall({ jobTypes = { 'ems' }, title = 'Medical call' })

    local leo = Dispatch.api.getCalls({ service = 'leo' })
    h.assertEqual(#leo, 1, 'one leo call')
    h.assertEqual(leo[1].title, 'Police call', 'and it is the right one')
    h.assertEqual(#Dispatch.api.getCalls({ service = 'ems' }), 1, 'the ems history is its own')
end)

h.test('calls come back newest first', function()
    Dispatch.store._reset()
    Dispatch.api.createCall({ jobTypes = { 'leo' }, title = 'Older' })
    net.advance(1000)
    Dispatch.api.createCall({ jobTypes = { 'leo' }, title = 'Newer' })

    h.assertEqual(Dispatch.api.getCalls({ service = 'leo' })[1].title, 'Newer',
        'a feed reads newest first, so no consumer has to sort')
end)

h.report('api')
