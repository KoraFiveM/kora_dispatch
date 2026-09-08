-- Native call markers are capped, prioritised and removed when a call closes
-- or expires. They must never create an automatic GPS route.
local h = dofile('test/harness.lua')
local mocks = dofile('test/mocks.lua'); local net = mocks.install()
dofile('config.lua')

local created, removed = {}, {}
local infoUpdates = {}
local nextBlip = 100
QB.blips = {
    create = function(coords, options)
        nextBlip = nextBlip + 1
        created[#created + 1] = { id = nextBlip, coords = coords, options = options }
        return nextBlip
    end,
    remove = function(blip)
        removed[#removed + 1] = blip
        return true
    end,
    setInfo = function(blip, info)
        infoUpdates[#infoUpdates + 1] = { blip = blip, info = info }
        return true
    end,
}

dofile('client/state.lua')
dofile('client/blip.lua')

local function call(id, priority, expiresAt)
    return {
        id = id, priority = priority, code = '10-' .. id, title = 'Call ' .. id,
        coords = { x = id, y = id, z = 30 }, createdAt = 0, expiresAt = expiresAt or 60000,
        units = {},
    }
end

h.test('map markers show the most urgent calls and do not set a route', function()
    Dispatch.state.setService('leo', { src = 1 }, {})
    Dispatch.state.upsert(call(1, 3))
    Dispatch.state.upsert(call(2, 1))
    Dispatch.state.upsert(call(3, 2))
    Config.map.maxCallBlips = 2

    Dispatch.blip.refreshCalls()

    h.assertEqual(#created, 2, 'only the configured number of markers is created')
    h.assertEqual(created[1].coords.x, 2, 'critical calls take the first marker slot')
    h.assertEqual(created[2].coords.x, 3, 'then high-priority calls')
    h.assertEqual(created[1].options.route, nil, 'a map marker must not route the officer automatically')
    h.assertEqual(created[1].options.shortRange, false, 'the marker is visible on the full map')
    h.assertEqual(created[1].options.category, 'Dispatch', 'call markers use the canonical Dispatch category')
    h.assertEqual(created[1].options.name, '10-2 - Call 2', 'the alert identity is supplied without a preformatted category')
    h.assertEqual(created[1].options.label, nil, 'qblib composes the display label')
    h.assertEqual(created[1].options.info.rows[1].value, 'Critical', 'the panel describes call priority')
    h.assertEqual(created[1].options.info.rows[3].value, 'No details supplied.', 'the panel handles a missing call message')
end)

h.test('an accepted-call route uses the same canonical category and name contract', function()
    local routed = call(4, 1)
    h.assertTrue(Dispatch.blip.route(routed), 'a valid call creates a route')
    local options = created[#created].options
    h.assertEqual(options.category, 'Dispatch')
    h.assertEqual(options.name, '10-4 - Call 4')
    h.assertEqual(options.label, nil)
    h.assertEqual(options.route, true)
end)

h.test('closed and expired calls lose their native map markers', function()
    local closed = call(2, 1)
    closed.closedAt = 1
    Dispatch.state.upsert(closed)
    Dispatch.blip.onCallChanged(closed)
    h.assertEqual(#removed, 1, 'closing a visible call removes its marker')

    net.advance(60001)
    net.intervals[1].fn()
    h.assertEqual(#removed, 3, 'the expiry sweep removes every remaining marker')
    h.assertEqual(#infoUpdates, 1, 'a surviving marker refreshes its pause-map details')
end)

h.report('call_blips')
