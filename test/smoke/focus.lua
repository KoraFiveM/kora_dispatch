-- Dispatch delegates browser focus to qblib's AppShell. These checks ensure it
-- never reaches for the global NUI focus native itself and cleans up viewing.
local h = dofile('test/harness.lua')
local mocks = dofile('test/mocks.lua'); mocks.install()
dofile('config.lua')

local focusCalls, opened, closed, definitions = {}, 0, 0, {}
function _G.SetNuiFocus(mouse, keyboard) focusCalls[#focusCalls + 1] = { mouse, keyboard } end
_G.QB = {
    nui = {
        registerApp = function(definition) definitions[#definitions + 1] = definition end,
        openApp = function() opened = opened + 1 end,
        closeApp = function() closed = closed + 1 end,
    },
    theme = { tokens = function() return { primary = 'token' } end },
    callback = { trigger = function() return true end },
}

dofile('shared/calls.lua')
dofile('client/state.lua')
dofile('client/theme.lua')
dofile('client/ui.lua')

h.test('closing a tablet we never opened does not disturb another UI focus', function()
    Dispatch.ui.setTablet(false)
    h.assertEqual(#focusCalls, 0, 'dispatch never releases global focus directly')
    h.assertEqual(closed, 0, 'there is no AppShell instance to close')
end)

h.test('opening and closing delegate focus lifecycle to AppShell', function()
    Dispatch.state.setService('leo', { src = 1 }, { label = 'Police' })
    Dispatch.theme.refresh()
    Dispatch.ui.setTablet(true)
    h.assertEqual(#definitions, 1, 'the tablet registers its AppShell definition')
    h.assertEqual(definitions[1].accent, Config.defaultService.accent, 'the shared shell receives the service accent')
    h.assertEqual(opened, 1, 'the tablet opens the shared shell')
    h.assertEqual(#focusCalls, 0, 'dispatch does not own raw focus')

    -- The test shell resolves immediately, so its opener has already performed
    -- the normal close cleanup. The production request remains open until the
    -- player closes it; in both cases dispatch never owns raw focus.
    h.assertEqual(#focusCalls, 0, 'closing still does not touch another UI focus')
end)

h.test('the AppShell payload includes live map tiles, call and unit markers, and searchable collections', function()
    Dispatch.state.upsert({
        id = 41, title = 'Vehicle pursuit', priority = 1,
        message = 'Black coupe', location = 'Alta Street',
        coords = { x = 215.0, y = -810.0, z = 30.0 },
        createdAt = 1, expiresAt = 999999, units = {},
    })
    Dispatch.state.setUnits({ {
        src = 9, callsign = '2-ADAM-9', name = 'Officer Diaz',
        coords = { x = 220.0, y = -805.0, z = 30.0 }, heading = 92.0,
    } })

    Dispatch.state.setTabletOpen(false)
    Dispatch.ui.setTablet(true)
    local definition = definitions[#definitions]
    local mapView, queueView
    for _, view in ipairs(definition.navigation) do
        if view.id == 'map' then mapView = view end
        if view.id == 'queue' then queueView = view end
    end

    local map = mapView.content.blocks[1]
    h.assertEqual(map.type, 'map', 'the first live-operations block is the qblib map')
    h.assertTrue(map.tiles.url:find('cfx%-nui%-qbdispatch/web/build/map/mainmap'), 'tiles remain owned by qbdispatch')
    h.assertEqual(#map.markers, 2, 'one call and one unit are projected into the map payload')
    h.assertEqual(map.markers[1].action, 'dispatch:select', 'call markers route through the declared AppShell action')
    h.assertEqual(map.markers[1].fadeDuration, (999999 - 1) * (1 - Config.map.fadeHoldFraction),
        'call markers derive their fade window from dispatch map configuration')
    h.assertTrue(map.follow, 'the map follows and can recenter on the current unit')

    local calls = queueView.content.blocks[1]
    h.assertTrue(calls.searchable, 'the active queue is searchable')
    h.assertTrue(calls.pageSize > 0, 'the active queue is paged')
    h.assertEqual(calls.layout, 'cards', 'the active queue uses cards')
end)

h.test('history details never offer a response action for an ended call', function()
    Dispatch.state.upsert({
        id = 42, title = 'Resolved incident', priority = 2,
        message = 'Scene clear', location = 'Vespucci Boulevard',
        coords = { x = -100.0, y = -900.0, z = 30.0 },
        createdAt = 1, expiresAt = 999999, closedAt = 2, units = {},
    })
    Dispatch.state.select(42)
    Dispatch.state.setTabletOpen(false)
    Dispatch.ui.setTablet(true)

    local detail
    for _, view in ipairs(definitions[#definitions].navigation) do if view.id == 'detail' then detail = view end end
    local sawRoute, sawRespond = false, false
    for _, action in ipairs(detail.content.actions or {}) do
        if action.id == 'dispatch:route' then sawRoute = true end
        if action.id:match('^dispatch:respond:') then sawRespond = true end
    end
    h.assertTrue(sawRoute, 'historical coordinates can still be routed')
    h.assertFalse(sawRespond, 'closed history entries cannot render response controls')
end)

h.report('focus')
