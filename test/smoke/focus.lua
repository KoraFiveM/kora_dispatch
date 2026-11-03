-- Dispatch delegates browser focus to kora_lib's AppShell. These checks ensure it
-- never reaches for the global NUI focus native itself and cleans up viewing.
local h = dofile('test/harness.lua')
local mocks = dofile('test/mocks.lua'); local mock = mocks.install()
local resource = arg[1] or '.'
dofile(resource .. '/config.lua')

local focusCalls, opened, closed, definitions, feeds, updates = {}, 0, 0, {}, {}, {}
function _G.SetNuiFocus(mouse, keyboard) focusCalls[#focusCalls + 1] = { mouse, keyboard } end
_G.Kora = {
    nui = {
        registerApp = function(definition) definitions[#definitions + 1] = definition end,
        updateApp = function(id, update) updates[#updates + 1] = { id = id, update = update }; return true end,
        openApp = function() opened = opened + 1 end,
        closeApp = function() closed = closed + 1 end,
        setDispatchFeed = function(payload) feeds[#feeds + 1] = payload; return true end,
    },
    theme = { tokens = function(hex)
        hex = hex or '#95FF00'
        return { primary = hex, ['brand-soft'] = 'soft:' .. hex, ['brand-border'] = 'border:' .. hex, background = 'unscoped' }
    end },
    callback = { trigger = function() return true end },
}

dofile(resource .. '/shared/calls.lua')
dofile(resource .. '/client/state.lua')
dofile(resource .. '/client/theme.lua')
dofile(resource .. '/client/ui.lua')

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
    h.assertEqual(map.type, 'map', 'the first live-operations block is the kora_lib map')
    h.assertTrue(map.tiles.url:find('cfx%-nui%-kora_dispatch/web/build/map/mainmap'), 'tiles remain owned by kora_dispatch')
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

h.test('a units heartbeat patches only the map and units views, and skips unchanged units (F#445)', function()
    -- The tablet is still registered open from the previous test.
    Dispatch.state.setTabletOpen(false)
    Dispatch.ui.setTablet(true)
    -- The mock shell resolves at once, so reopen the state and do the full render
    -- an open tablet would have had.
    Dispatch.state.setTabletOpen(true)
    Dispatch.state.setUnits({ { src = 9, callsign = '2-ADAM-9', name = 'Officer Diaz',
        coords = { x = 220.0, y = -805.0, z = 30.0 }, heading = 92.0 } })
    Dispatch.ui.render()
    local registered, before = #definitions, definitions[#definitions].navigation
    local unit = { src = 9, callsign = '2-ADAM-9', name = 'Officer Diaz',
        coords = { x = 220.0, y = -805.0, z = 30.0 }, heading = 92.0 }

    Dispatch.state.setUnits({ unit })
    Dispatch.ui.renderUnits()
    h.assertEqual(#updates, 0, 'an unchanged units snapshot sends nothing')

    Dispatch.state.setUnits({ { src = 9, callsign = '2-ADAM-9', name = 'Officer Diaz',
        coords = { x = 260.0, y = -805.0, z = 30.0 }, heading = 92.0 } })
    Dispatch.ui.renderUnits()
    h.assertEqual(#definitions, registered, 'the heartbeat does not re-register the whole app')
    h.assertEqual(#updates, 1, 'a moved unit sends one partial update')
    h.assertEqual(updates[1].id, 'qbdispatch:tablet')
    local views = {}
    for _, view in ipairs(updates[1].update.navigation) do views[view.id] = view end
    local beforeViews = {}
    for _, view in ipairs(before) do beforeViews[view.id] = view end
    h.assertTrue(views.queue == beforeViews.queue, 'call lists are reused, not rebuilt')
    h.assertTrue(views.history == beforeViews.history, 'history is reused, not rebuilt')
    local unitMarker
    for _, marker in ipairs(views.map.content.blocks[1].markers) do
        if marker.id == 'unit:9' then unitMarker = marker end
    end
    h.assertEqual(unitMarker.x, 260.0, 'the map block carries the new unit position')
    h.assertTrue(views.map.content.blocks[2] == beforeViews.map.content.blocks[2], 'the map call list is reused')

    Dispatch.state.setUnits({ { src = 9, callsign = '2-ADAM-9', name = 'Officer Diaz',
        coords = { x = 260.2, y = -805.1, z = 31.0 }, heading = 91.0 } })
    Dispatch.ui.renderUnits()
    h.assertEqual(#updates, 1, 'sub-metre jitter does not resend the tablet')
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

-- Keep the original immediate AppShell checks above; await only these lifecycle
-- cases so state can be checked while a tablet or response callback is pending.
local keys, notices, viewing, sounds, routes = {}, {}, {}, 0, 0
local appThread, responseThread, pauseResponse
function _G.CreateThread(fn)
    local thread = coroutine.create(fn)
    local ok, err = coroutine.resume(thread)
    h.assertTrue(ok, err)
end
local function resume(thread)
    local ok, err = coroutine.resume(thread)
    h.assertTrue(ok, err)
end
Kora.nui.openApp = function()
    opened = opened + 1; appThread = coroutine.running(); coroutine.yield('app')
end
Kora.nui.closeApp = function()
    closed = closed + 1
    if appThread then local thread = appThread; appThread = nil; resume(thread) end
end
Kora.callback.trigger = function(name, value)
    if name == 'qbdispatch:setViewing' then viewing[#viewing + 1] = value end
    if name == 'qbdispatch:respond' and pauseResponse then
        responseThread = coroutine.running(); coroutine.yield('respond'); return nil
    end
    return true
end
Kora.keybind = { add = function(definition) keys[definition.name] = definition end }
Kora.notify = { send = function(payload) notices[#notices + 1] = payload end }
Kora.sound = { playFrontend = function() sounds = sounds + 1 end }
Dispatch.blip = { refreshCalls = function() end, onCallChanged = function() end,
    clear = function() end, clearCalls = function() end,
    route = function() routes = routes + 1 end, callId = function() end }
dofile(resource .. '/client/sync.lua')
dofile(resource .. '/client/keybinds.lua')
dofile(resource .. '/client/exports.lua')
local function feed() return feeds[#feeds] end
local function call(id, created)
    return { id = id, title = 'Incident ' .. id, code = '10-' .. id, priority = 2,
        message = 'Call details', data = { street = 'Alta Street' }, createdAt = created,
        expiresAt = 10000, units = {}, coords = { x = 1, y = 2, z = 3 } }
end

h.test('call pushes publish the complete configured feed and derived service theme', function()
    Dispatch.state.replaceAll({}); Dispatch.state.select(nil)
    Dispatch.state.setService('leo', { src = 1 }, {
        accent = '#3B82F6', feed = { maxVisible = 1, position = 'top-left' }, priorities = Config.priorities,
    })
    Dispatch.theme.set(nil)
    TriggerEvent('qbdispatch:client:call', call(101, 100), 500)
    TriggerEvent('qbdispatch:client:call', call(102, 200), 500)
    h.assertEqual(#feed().calls, 2, 'the browser receives calls beyond the visible cap')
    h.assertEqual(feed().calls[1].id, 102); h.assertEqual(feed().calls[1].data.street, 'Alta Street')
    h.assertEqual(feed().now, 500); h.assertEqual(feed().me.src, 1)
    h.assertEqual(feed().config.feed.maxVisible, 1); h.assertEqual(feed().config.feed.position, 'top-left')
    h.assertEqual(feed().config.priorities, Config.priorities); h.assertEqual(feed().keybinds, Config.keybinds)
    h.assertEqual(feed().theme.primary, '#3B82F6'); h.assertEqual(feed().theme['brand-soft'], 'soft:#3B82F6')
    h.assertEqual(feed().theme['brand-border'], 'border:#3B82F6'); h.assertEqual(feed().theme.background, nil)
    h.assertEqual(#notices, 2); h.assertEqual(sounds, 2)
end)

h.test('selection can browse live calls and history and publishes server response updates', function()
    local history = call(99, 1); history.closedAt = 2
    TriggerEvent('qbdispatch:client:callUpdated', history, 500)
    keys.qbdispatch_previous.onPressed(); h.assertEqual(feed().selected, 102)
    keys.qbdispatch_next.onPressed(); h.assertEqual(feed().selected, 101)
    keys.qbdispatch_next.onPressed(); h.assertEqual(feed().selected, 99)
    h.assertEqual(feed().calls[3].closedAt, 2)
    local updated = call(102, 200); updated.units = { { src = 1, state = 'en_route' } }
    TriggerEvent('qbdispatch:client:callUpdated', updated, 500)
    h.assertEqual(feed().calls[1].units[1].state, 'en_route')
end)

h.test('mute, presentation options and theme exports immediately update the closed-tablet feed', function()
    keys.qbdispatch_toggle.onPressed(); h.assertEqual(feed().hidden, true)
    TriggerEvent('qbdispatch:client:call', call(103, 300), 500)
    h.assertEqual(sounds, 2, 'mute still suppresses the incoming tone'); h.assertEqual(#notices, 3)
    keys.qbdispatch_toggle.onPressed(); h.assertEqual(feed().hidden, false)
    h.assertEqual(mock.registeredExports.setUiOptions({ maxVisible = 0, position = 'top-center', hidden = true }), true)
    h.assertEqual(feed().config.feed.maxVisible, 0); h.assertEqual(feed().config.feed.position, 'top-center')
    h.assertEqual(feed().hidden, true)
    h.assertEqual(mock.registeredExports.setTheme('#EF4444'), true); h.assertEqual(feed().theme.primary, '#EF4444')
    local before = #feeds
    local ok, reason = mock.registeredExports.setTheme(false)
    h.assertEqual(ok, false); h.assertEqual(type(reason), 'string'); h.assertEqual(#feeds, before)
    h.assertEqual(mock.registeredExports.setUiOptions(false), false)
    mock.registeredExports.setUiOptions({ hidden = false })
end)

h.test('tablet opening hides the feed and explicit or awaited close restores it without raw focus', function()
    mock.registeredExports.setTablet(true)
    h.assertEqual(feed(), false); h.assertEqual(viewing[#viewing], true)
    h.assertEqual(Dispatch.state.data.tabletOpen, true)
    local before = closed
    mock.registeredExports.setTablet(false)
    h.assertEqual(closed, before + 1); h.assertEqual(type(feed()), 'table'); h.assertEqual(viewing[#viewing], false)
    mock.registeredExports.setTablet(true); h.assertEqual(feed(), false)
    local thread = appThread; appThread = nil; resume(thread)
    h.assertEqual(type(feed()), 'table'); h.assertEqual(Dispatch.state.data.tabletOpen, false)
    h.assertEqual(viewing[#viewing], false); h.assertEqual(#focusCalls, 0)
end)

h.test('respond fallback publishes its selected call before an awaited callback can complete', function()
    Dispatch.state.select(nil); Dispatch.ui.render(); pauseResponse = true
    keys.qbdispatch_respond.onPressed()
    h.assertEqual(coroutine.status(responseThread), 'suspended')
    h.assertEqual(feed().selected, 103, 'selection is visible during the server round trip')
    resume(responseThread); pauseResponse = false
    h.assertEqual(routes, 0, 'a callback timeout remains silent and cannot route')
end)

h.test('kora_lib restart replays the feed while inactive service and player unload clear it', function()
    local before = #feeds
    TriggerEvent('onClientResourceStart', 'unrelated'); h.assertEqual(#feeds, before)
    TriggerEvent('onClientResourceStart', 'kora_lib'); h.assertEqual(#feeds, before + 1)
    h.assertEqual(feed().selected, 103)
    Dispatch.state.setService(nil); Dispatch.ui.render(); h.assertEqual(feed(), false)
    Dispatch.state.setService('leo', { src = 1 }, { feed = Config.feed }); Dispatch.ui.render()
    TriggerEvent('QBCore:Client:OnPlayerUnload'); h.assertEqual(feed(), false)
    h.assertEqual(Dispatch.state.isActive(), false)
end)

h.report('focus')
