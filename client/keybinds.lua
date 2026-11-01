-- Keyboard control of the feed.
--
-- The design goal is that a player never has to open anything to work a call:
-- select with Page Up/Down, press Home to accept, press it again as you arrive,
-- again to clear. The tablet is for when you want the map, not a step in the
-- normal flow.
--
-- Every bind goes through Kora.keybind.add, so all of them appear in FiveM's own
-- key-binding settings and every player can rebind them.

Dispatch = Dispatch or {}

---Feed keys must not fire while the tablet has focus -- the browser owns input
---then, and a keypress the game also acts on would move the selection behind the
---UI. The tablet toggle itself is the deliberate exception.
---@return boolean
local function feedActive()
    return Dispatch.state.isActive() and not Dispatch.state.data.tabletOpen
end

Kora.keybind.add({
    name = 'qbdispatch_previous',
    description = 'Dispatch: previous call',
    defaultKey = Config.keybinds.previous,
    onPressed = function()
        if not feedActive() then return end
        Dispatch.state.moveSelection(-1)
        Dispatch.ui.render()
    end,
})

Kora.keybind.add({
    name = 'qbdispatch_next',
    description = 'Dispatch: next call (scrolls into history)',
    defaultKey = Config.keybinds.next,
    onPressed = function()
        if not feedActive() then return end
        Dispatch.state.moveSelection(1)
        Dispatch.ui.render()
    end,
})

Kora.keybind.add({
    name = 'qbdispatch_respond',
    description = 'Dispatch: accept / en route / on scene / clear',
    defaultKey = Config.keybinds.respond,
    onPressed = function()
        if not feedActive() then return end

        local call = Dispatch.state.selected()
        -- With nothing selected, respond to the newest live call. Pressing
        -- accept the instant a call comes in is the single most common action,
        -- and requiring a select first would make it two keys every time.
        if not call then
            call = Dispatch.state.live(1)[1]
            if not call then return end
            Dispatch.state.select(call.id)
            Dispatch.ui.render()
        end

        local wasAttached = Dispatch.state.myStateOn(call) ~= nil

        CreateThread(function()
            -- Two return values: the new state, and a reason when the server
            -- refused. A nil `state` is a timed-out callback, NOT a refusal, so
            -- it must stay silent -- inventing a reason for a dropped round trip
            -- would tell the player something the server never said.
            local state, reason = Kora.callback.trigger('qbdispatch:respond', call.id)

            if state == false then
                if reason then Kora.notify.send({ message = reason, type = 'error' }) end
                return
            end

            if state == nil then return end

            -- Accepting routes you there; clearing drops the route. Both are the
            -- action the player just took, so neither needs a second keypress.
            if not wasAttached and state == 'en_route' then
                Dispatch.blip.route(call)
            elseif state == 'clear' then
                Dispatch.blip.clear()
            end
        end)
    end,
})

Kora.keybind.add({
    name = 'qbdispatch_toggle',
    description = 'Dispatch: hide/show the dispatch UI',
    defaultKey = Config.keybinds.toggle,
    onPressed = function()
        if not Dispatch.state.isActive() then return end

        -- With the tablet open, this key means "get the dispatch UI off my
        -- screen" -- so it closes the tablet (which is what holds NUI focus)
        -- rather than silently hiding the feed behind it and leaving the player
        -- still stuck in a focused overlay.
        if Dispatch.state.data.tabletOpen then
            Dispatch.ui.setTablet(false)
            return
        end

        Dispatch.state.setHidden(not Dispatch.state.data.hidden)
        Dispatch.ui.render()
    end,
})

---Says why the tablet refused to open, but ONLY to someone who plausibly meant
---to open it: a player employed in a dispatch service who is currently off duty.
---
---The tablet key defaults to F9, which plenty of other resources also bind, so
---an unconditional notification would fire at civilians who pressed it for
---something else entirely. Silence is right for them and wrong for the off-duty
---officer, for whom a dead key looks exactly like a broken resource.
local function warnIfOffDuty()
    local job = exports.kora_core:getPlayerData({ 'job' })
    local jobType = job and job.type
    if not jobType or jobType == 'none' or jobType == 'civ' then return end
    if not Dispatch.access.allowed(job.name, jobType) then return end
    if job.onduty then return end

    Kora.notify.send({
        message = 'You are off duty -- dispatch is closed. Go on duty to open the tablet.',
        type = 'error',
    })
end

Kora.keybind.add({
    name = 'qbdispatch_tablet',
    description = 'Dispatch: open tablet',
    defaultKey = Config.keybinds.tablet,
    onPressed = function()
        if not Dispatch.state.isActive() then return warnIfOffDuty() end
        Dispatch.ui.setTablet(not Dispatch.state.data.tabletOpen)
    end,
})

-- Prints the player's live world position alongside its projected map pixel, so
-- a server owner swapping in their own basemap can recalibrate Config.map by
-- standing on two landmarks. Not a gameplay command; it reads nothing and
-- changes nothing.
RegisterCommand('dispatchcoords', function()
    local coords = Kora.cache.coords()
    if not coords then return end

    local calibration = Config.map.calibration
    local a, b = calibration.a, calibration.b
    local scaleX = (b.image.x - a.image.x) / (b.world.x - a.world.x)
    local scaleY = (b.image.y - a.image.y) / (b.world.y - a.world.y)

    print(('[qbdispatch] world (%.2f, %.2f, %.2f)  ->  map pixel (%.1f, %.1f)'):format(
        coords.x, coords.y, coords.z,
        a.image.x + (coords.x - a.world.x) * scaleX,
        a.image.y + (coords.y - a.world.y) * scaleY))
end, false)
