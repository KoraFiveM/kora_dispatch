-- The NUI bridge.
--
-- IMPORTANT: every NUI native below is called RAW rather than through QB.nui.*.
-- This resource owns its own frame (`ui_page` in fxmanifest.lua), and each
-- `QB.<module>.<fn>` access is a cross-resource export call whose body runs in
-- QBLIB's Lua VM -- SendNUIMessage would post into qblib's frame, and
-- RegisterNUICallback would publish the callback at https://qblib/<name> while
-- this resource's page fetches https://qbdispatch/<name>: a permanent 404. The
-- same rationale is documented at the head of qbhud/client/hud.lua.
--
-- QB.cache / QB.theme / QB.timers / QB.blips / QB.keybind stay on the proxy --
-- they are pure Lua and touch no NUI native.

Dispatch = Dispatch or {}
Dispatch.ui = {}

local ready = false
local pending = {}

---@param action string
---@param data any
function Dispatch.ui.send(action, data)
    -- SendNUIMessage is postMessage-like, not a mailbox: anything sent before
    -- the page mounts is lost permanently. Messages are queued until the app
    -- reports in, which matters most on resource restart -- the hydrate reply
    -- routinely beats the browser to it.
    if not ready then
        pending[#pending + 1] = { action = action, data = data }
        return
    end
    SendNUIMessage({ action = action, data = data })
end

---Pushes the whole current view. Cheap enough to send wholesale (a few dozen
---calls at most) and far easier to reason about than diffing.
function Dispatch.ui.render()
    local S = Dispatch.state.data

    Dispatch.ui.send('qbdispatch:state', {
        active = S.service ~= nil,
        service = S.service,
        config = S.config,
        hidden = S.hidden,
        tabletOpen = S.tabletOpen,
        selected = S.selected,
        me = S.unit,
        calls = Dispatch.state.all(),
        units = S.units,
        keybinds = Config.keybinds,
        -- The SERVER's clock, not this client's. Call timestamps are stamped
        -- server-side and the two GetGameTimer()s are unrelated -- the NUI's
        -- countdowns and marker fade are only meaningful against the clock the
        -- timestamps came from.
        now = Dispatch.state.now(),
    })
end

---Opens or closes the tablet, taking and releasing NUI focus with it.
---@param open boolean
function Dispatch.ui.setTablet(open)
    -- Closing ALWAYS releases focus, even when this resource already believes
    -- the tablet is shut. Going off duty clears the local state first, so an
    -- early return here would leave a player who was mid-tablet with their mouse
    -- locked to a frame that is no longer rendering anything -- and no in-game
    -- way out of it.
    if not open then
        SetNuiFocus(false, false)
        if not Dispatch.state.data.tabletOpen then return end
    elseif open == Dispatch.state.data.tabletOpen then
        return
    elseif not Dispatch.state.isActive() then
        return
    end

    Dispatch.state.setTabletOpen(open)
    if open then SetNuiFocus(true, true) end
    Dispatch.ui.render()

    -- The server only runs the unit heartbeat while somebody is looking, so the
    -- open/close signal is what gates that work entirely. It answers by running
    -- a real broadcast, which arrives as an ordinary qbdispatch:client:units
    -- push -- so there is nothing to unpack from the reply here.
    CreateThread(function()
        QB.callback.trigger('qbdispatch:setViewing', open)
    end)
end

-- Answered first and unconditionally, so a failure inside the initial render
-- can't leave the browser's fetch hanging forever.
RegisterNUICallback('qbdispatch:ready', function(_, cb)
    cb({})
    ready = true

    for _, message in ipairs(pending) do
        SendNUIMessage({ action = message.action, data = message.data })
    end
    pending = {}

    Dispatch.ui.render()
end)

RegisterNUICallback('qbdispatch:close', function(_, cb)
    cb({})
    Dispatch.ui.setTablet(false)
end)

RegisterNUICallback('qbdispatch:select', function(data, cb)
    cb({})
    Dispatch.state.select(data and data.id)
    Dispatch.ui.render()
end)

RegisterNUICallback('qbdispatch:respond', function(data, cb)
    if not data or not data.id then return cb({ ok = false }) end

    CreateThread(function()
        local state, err = QB.callback.trigger('qbdispatch:respond', data.id, data.state)
        cb({ ok = state ~= false, state = state or nil, error = err })
    end)
end)

RegisterNUICallback('qbdispatch:setWaypoint', function(data, cb)
    cb({})
    local call = data and data.id and Dispatch.state.get(data.id)
    if call then Dispatch.blip.route(call) end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    -- Leaving NUI focus set would lock the player's mouse into a frame that no
    -- longer exists, with no way out but a reconnect.
    SetNuiFocus(false, false)
end)
