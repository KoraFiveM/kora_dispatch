-- Client callbacks must retain the same department scope as live call delivery.
local h = dofile('test/harness.lua')
local net = dofile('test/mocks.lua').install()
dofile('config.lua'); Config.debug = false
dofile('shared/calls.lua')
dofile('server/store.lua')
dofile('server/recipients.lua')
dofile('server/api.lua')
local callbacks, options = {}, {}
Kora.callback.register = function(name, fn, config) callbacks[name], options[name] = fn, config end
dofile(arg[1] or 'server/callbacks.lua')
net.setPlayer(1, 'police', true)
net.setPlayer(2, 'sheriff', true)
net.setPlayer(3, 'ambulance', true)
net.setPlayer(4, 'police', false)
local police = Dispatch.api.createCall({ jobs = { 'police' }, title = 'Police only' })
local sheriff = Dispatch.api.createCall({ jobs = { 'sheriff' }, title = 'Sheriff only' })
local leo = Dispatch.api.createCall({ jobTypes = { 'leo' }, title = 'All LEO' })
local ems = Dispatch.api.createCall({ jobTypes = { 'ems' }, title = 'EMS only' })
local function ids(calls, expected)
    h.assertEqual(#calls, #expected, 'call count')
    for index, id in ipairs(expected) do h.assertEqual(calls[index].id, id, 'call order and identity') end
end

h.test('hydrate follows department delivery within a shared service', function()
    ids(callbacks['qbdispatch:hydrate'](1).calls, { leo, police })
    ids(callbacks['qbdispatch:hydrate'](2).calls, { leo, sheriff })
    ids(callbacks['qbdispatch:hydrate'](3).calls, { ems })
end)

h.test('history cannot forge service or department and accepts existing optional filters', function()
    for _, filter in ipairs({ {}, { job = 'police' }, { service = 'ems', job = 'ambulance' }, { job = false } }) do
        ids(callbacks['qbdispatch:getCalls'](2, filter), { leo, sheriff })
        h.assertEqual(filter.service, 'leo', 'service forced from the current unit')
        h.assertEqual(filter.job, 'sheriff', 'department forced from the current unit')
    end
    ids(callbacks['qbdispatch:getCalls'](2, false), { leo, sheriff })
    ids(callbacks['qbdispatch:getCalls'](2, 'police'), { leo, sheriff })
end)

h.test('closed and expired history remains readable only to invited departments', function()
    Dispatch.api.closeCall(sheriff, 'resolved')
    ids(callbacks['qbdispatch:getCalls'](2, { activeOnly = true }), { leo })
    ids(callbacks['qbdispatch:getCalls'](2), { leo, sheriff })
    net.advance(Config.priorities[Config.defaultPriority].ttl + 1)
    ids(callbacks['qbdispatch:getCalls'](2, { activeOnly = true }), {})
    ids(callbacks['qbdispatch:getCalls'](2), { leo, sheriff })
end)

h.test('off-duty and missing players keep existing nil or empty callback responses', function()
    h.assertEqual(callbacks['qbdispatch:hydrate'](4), nil, 'off-duty hydrate')
    h.assertEqual(callbacks['qbdispatch:hydrate'](99), nil, 'missing player hydrate')
    ids(callbacks['qbdispatch:getCalls'](4), {})
    ids(callbacks['qbdispatch:getCalls'](99), {})
end)

h.test('a job change uses the current department on the next request', function()
    net.setPlayer(2, 'police', true)
    ids(callbacks['qbdispatch:hydrate'](2).calls, { leo, police })
    net.setPlayer(2, 'ambulance', true)
    ids(callbacks['qbdispatch:getCalls'](2, { service = 'leo', job = 'police' }), { ems })
end)

h.test('trusted server history export retains broad and explicit job filters', function()
    ids(net.registeredExports.getCalls({ service = 'leo' }), { leo, sheriff, police })
    ids(net.registeredExports.getCalls({ service = 'leo', job = 'police' }), { leo, police })
    h.assertEqual(#net.registeredExports.getCalls(), 4, 'server resources can still read all services')
end)

h.test('callback names and throttles retain their public contract', function()
    h.assertEqual(options['qbdispatch:hydrate'].rateLimit.max, 5, 'hydrate limit')
    h.assertEqual(options['qbdispatch:getCalls'].rateLimit.max, 10, 'history limit')
    h.assertEqual(options['qbdispatch:respond'].rateLimit.max, 20, 'response limit')
    h.assertEqual(options['qbdispatch:setViewing'].rateLimit.max, 30, 'viewing limit')
end)

h.test('civilians are refused every data callback even when on duty', function()
    net.setPlayer(5, 'unemployed', true)
    h.assertEqual(callbacks['qbdispatch:hydrate'](5), nil, 'civilian hydrate')
    ids(callbacks['qbdispatch:getCalls'](5), {})
    Dispatch.units = { setViewer = function() end, tick = function() end }
    h.assertEqual(callbacks['qbdispatch:setViewing'](5, true), false, 'civilian viewing')
    h.assertEqual(callbacks['qbdispatch:respond'](5, leo), false, 'civilian respond')
    h.assertEqual(Dispatch.api.setUnitState(5, leo), false, 'civilian api response')
end)

h.test('Config.access narrows types, adds job names and can waive on-duty', function()
    net.setPlayer(1, 'police', true)
    net.setPlayer(4, 'police', false)
    Config.access = { jobTypes = { 'ems' } }
    h.assertEqual(callbacks['qbdispatch:hydrate'](1), nil, 'leo outside narrowed types')
    Config.access = { jobTypes = { 'ems' }, jobs = { 'police' } }
    h.assertTrue(callbacks['qbdispatch:hydrate'](1) ~= nil, 'job name allowed')
    Config.access = { requireOnDuty = false }
    h.assertTrue(callbacks['qbdispatch:hydrate'](4) ~= nil, 'off-duty allowed job may read')
    h.assertEqual(callbacks['qbdispatch:respond'](4, leo), false, 'off-duty still cannot respond')
    net.setPlayer(5, 'unemployed', false)
    h.assertEqual(callbacks['qbdispatch:hydrate'](5), nil, 'civilian still refused')
    Config.access = { jobs = {}, requireOnDuty = true }
end)

h.report('callbacks')
