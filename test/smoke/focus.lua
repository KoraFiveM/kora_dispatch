-- NUI focus ownership.
--
-- SetNuiFocus is GLOBAL, not per-resource. Releasing focus this resource never
-- took steals the mouse from whatever UI actually has it -- and because
-- hydrate() closes the tablet on player load and on every job/duty change, that
-- lands squarely on qbmultichar's character selector during login. The player
-- then cannot pick a character, never logs in, and every logged-in-gated UI on
-- the server (the HUD included) stays hidden.
--
-- This suite exists so that never happens twice.
local h = dofile('test/harness.lua')
local mocks = dofile('test/mocks.lua'); mocks.install()
dofile('config.lua')

-- --- client realm natives ---------------------------------------------------
local focusCalls = {}
function _G.SetNuiFocus(mouse, keyboard) focusCalls[#focusCalls + 1] = { mouse, keyboard } end
function _G.SendNUIMessage(_) end
function _G.RegisterNUICallback(name, cb) _G.__nuiCallbacks[name] = cb end
_G.__nuiCallbacks = {}

_G.QB = setmetatable({}, { __index = function(t, k)
    local m = setmetatable({}, { __index = function() return function() return nil end end })
    rawset(t, k, m); return m
end })

dofile('shared/calls.lua')
dofile('client/state.lua')
dofile('client/ui.lua')

local function focusEvents() return #focusCalls end
local function lastFocus() return focusCalls[#focusCalls] end

h.test('closing the tablet we never opened touches nobody else focus', function()
    -- The login-path case: hydrate() -> not on duty -> setTablet(false), while
    -- qbmultichar owns the mouse.
    focusCalls = {}
    Dispatch.ui.setTablet(false)

    h.assertEqual(focusEvents(), 0,
        'a resource that never took focus must not release it -- that is another UI mouse')
end)

h.test('repeated closes stay silent', function()
    focusCalls = {}
    for _ = 1, 5 do Dispatch.ui.setTablet(false) end

    h.assertEqual(focusEvents(), 0, 'still nobody else business')
end)

h.test('opening takes focus, closing gives back exactly what we took', function()
    Dispatch.state.setService('leo', { src = 1 }, { label = 'Police' })
    focusCalls = {}

    Dispatch.ui.setTablet(true)
    h.assertEqual(focusEvents(), 1, 'opening takes focus once')
    h.assertEqual(lastFocus()[1], true, 'mouse')
    h.assertEqual(lastFocus()[2], true, 'keyboard')

    Dispatch.ui.setTablet(true)
    h.assertEqual(focusEvents(), 1, 'opening again is a no-op, not a second grab')

    Dispatch.ui.setTablet(false)
    h.assertEqual(focusEvents(), 2, 'closing releases')
    h.assertEqual(lastFocus()[1], false, 'mouse released')

    Dispatch.ui.setTablet(false)
    h.assertEqual(focusEvents(), 2, 'and does not release twice')
end)

h.test('going off duty with the tablet open still releases the mouse', function()
    Dispatch.state.setService('leo', { src = 1 }, { label = 'Police' })
    Dispatch.ui.setTablet(true)
    focusCalls = {}

    -- setService(nil) clears the state the tablet reads, so the close has to
    -- happen first -- otherwise a player who went off duty mid-tablet is left
    -- with their mouse locked to a frame that renders nothing, and no way out.
    Dispatch.ui.setTablet(false)
    Dispatch.state.setService(nil)

    h.assertEqual(focusEvents(), 1, 'focus released exactly once')
    h.assertEqual(lastFocus()[1], false, 'and it was a release')
end)

h.test('resource stop releases only focus we hold', function()
    Dispatch.state.setService('leo', { src = 1 }, { label = 'Police' })
    Dispatch.ui.setTablet(false)
    focusCalls = {}

    TriggerEvent('onResourceStop', 'qbdispatch')
    h.assertEqual(focusEvents(), 0, 'stopping without focus disturbs nothing')

    Dispatch.ui.setTablet(true)
    focusCalls = {}
    TriggerEvent('onResourceStop', 'qbdispatch')

    h.assertEqual(focusEvents(), 1, 'stopping WITH focus must hand the mouse back')
    h.assertEqual(lastFocus()[1], false, 'released')
end)

h.test('another resource stopping is not our business', function()
    focusCalls = {}
    TriggerEvent('onResourceStop', 'some_other_resource')
    h.assertEqual(focusEvents(), 0, 'we only clean up after ourselves')
end)

h.report('focus')
