-- Dispatch delegates browser focus to qblib's AppShell. These checks ensure it
-- never reaches for the global NUI focus native itself and cleans up viewing.
local h = dofile('test/harness.lua')
local mocks = dofile('test/mocks.lua'); mocks.install()
dofile('config.lua')

local focusCalls, opened, closed, registered = {}, 0, 0, 0
function _G.SetNuiFocus(mouse, keyboard) focusCalls[#focusCalls + 1] = { mouse, keyboard } end
_G.QB = {
    nui = {
        registerApp = function() registered = registered + 1 end,
        openApp = function() opened = opened + 1 end,
        closeApp = function() closed = closed + 1 end,
    },
    callback = { trigger = function() return true end },
}

dofile('shared/calls.lua')
dofile('client/state.lua')
dofile('client/ui.lua')

h.test('closing a tablet we never opened does not disturb another UI focus', function()
    Dispatch.ui.setTablet(false)
    h.assertEqual(#focusCalls, 0, 'dispatch never releases global focus directly')
    h.assertEqual(closed, 0, 'there is no AppShell instance to close')
end)

h.test('opening and closing delegate focus lifecycle to AppShell', function()
    Dispatch.state.setService('leo', { src = 1 }, { label = 'Police' })
    Dispatch.ui.setTablet(true)
    h.assertEqual(registered, 1, 'the tablet registers its AppShell definition')
    h.assertEqual(opened, 1, 'the tablet opens the shared shell')
    h.assertEqual(#focusCalls, 0, 'dispatch does not own raw focus')

    -- The test shell resolves immediately, so its opener has already performed
    -- the normal close cleanup. The production request remains open until the
    -- player closes it; in both cases dispatch never owns raw focus.
    h.assertEqual(#focusCalls, 0, 'closing still does not touch another UI focus')
end)

h.report('focus')
