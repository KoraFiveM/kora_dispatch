-- Dispatch uses qblib's shared AppShell for its tablet. The dispatch resource
-- remains responsible for call state, response rules, routes and unit data;
-- qblib provides the common application frame, navigation and focus handling.

Dispatch = Dispatch or {}
Dispatch.ui = {}

local function callTitle(call)
    return (call.code and (call.code .. ' · ') or '') .. (call.title or 'Dispatch call')
end

local function callDescription(call)
    return table.concat({ call.message or 'No details supplied.', call.location or 'Location unavailable' }, '\n')
end

local function callItems(calls, selected)
    local out = {}
    for _, call in ipairs(calls) do
        out[#out + 1] = {
            id = tostring(call.id), label = callTitle(call), description = callDescription(call),
            icon = call.id == selected and 'radio' or 'map-pin', badge = call.priority,
            tone = call.id == selected and 'primary' or 'neutral', action = 'dispatch:select',
        }
    end
    return out
end

local function selectedContent(S)
    local call = Dispatch.state.selected()
    if not call then
        return { title = 'Call details', blocks = { { type = 'empty', title = 'No call selected', description = 'Choose a call from the queue to see its details.', icon = 'radio' } } }
    end
    local mine = Dispatch.state.myStateOn(call)
    local nextState = mine == 'en_route' and 'on_scene' or mine == 'on_scene' and 'clear' or 'en_route'
    local nextLabel = mine == 'en_route' and 'Mark on scene' or mine == 'on_scene' and 'Clear call' or 'Accept call'
    return {
        title = callTitle(call), description = callDescription(call),
        actions = {
            { id = 'dispatch:respond:' .. nextState, label = nextLabel, icon = 'radio', variant = 'primary' },
            { id = 'dispatch:route', label = 'Set route', icon = 'navigation', variant = 'secondary' },
        },
        blocks = { { type = 'stats', items = {
            { label = 'Priority', value = call.priority or '—', icon = 'alert-triangle', tone = 'warning' },
            { label = 'Units assigned', value = #(call.units or {}), icon = 'users' },
            { label = 'Your response', value = mine and mine:gsub('_', ' ') or 'Not assigned', icon = 'radio', tone = mine and 'primary' or 'neutral' },
        } }, { type = 'text', title = 'Call information', text = callDescription(call) } },
    }
end

local function appDefinition()
    local S = Dispatch.state.data
    local active = Dispatch.state.live()
    return {
        id = 'qbdispatch:tablet', title = (S.config and S.config.label) or 'Dispatch',
        description = S.unit and ((S.unit.callsign and S.unit.callsign .. ' · ' or '') .. (S.unit.name or ('Unit ' .. S.unit.src))) or 'Dispatch tablet',
        icon = 'radio', accent = Dispatch.theme.get(), width = 1220, height = 800,
        navigation = {
            { id = 'queue', label = 'Active calls', icon = 'radio', badge = #active,
                content = { title = 'Active calls', description = 'Select a call to inspect it, respond or set a route.',
                    blocks = { { type = 'list', items = callItems(active, S.selected), empty = 'No active calls. Everything is clear.' } } } },
            { id = 'history', label = 'History', icon = 'history', badge = #S.order,
                content = { title = 'Call history', blocks = { { type = 'list', items = callItems(Dispatch.state.all(), S.selected), empty = 'No calls in this shift.' } } } },
            { id = 'detail', label = 'Selected call', icon = 'map-pin', content = selectedContent(S) },
            { id = 'units', label = 'Units', icon = 'users', badge = #S.units,
                content = { title = 'On-duty units', blocks = { { type = 'list', items = (function()
                    local units = {}
                    for _, unit in ipairs(S.units) do units[#units + 1] = {
                        id = tostring(unit.src), label = (unit.callsign and unit.callsign .. ' · ' or '') .. (unit.name or ('Unit ' .. unit.src)),
                        description = unit.gradeLabel or 'On duty', icon = 'users', tone = unit.src == (S.unit and S.unit.src) and 'primary' or 'neutral',
                    } end
                    return units
                end)(), empty = 'No unit updates yet.' } } } },
        },
        footer = 'Routes and call responses are verified by dispatch.',
        onAction = function(actionId, context)
            if actionId == 'dispatch:select' then
                local id = tonumber(context and context.itemId)
                Dispatch.state.select(id)
                return { update = { navigation = appDefinition().navigation } }
            end
            local call = Dispatch.state.selected()
            if not call then error('Select a call first.') end
            if actionId == 'dispatch:route' then
                Dispatch.blip.route(call)
                return {}
            end
            local response = actionId:match('^dispatch:respond:(.+)$')
            if not response then error('Unknown dispatch action.') end
            local state, err = QB.callback.trigger('qbdispatch:respond', call.id, response)
            if state == false then error(err or 'Could not update the call.') end
            return { update = { navigation = appDefinition().navigation } }
        end,
    }
end

function Dispatch.ui.render()
    if Dispatch.state.data.tabletOpen then QB.nui.registerApp(appDefinition()) end
end

local function setViewing(open)
    CreateThread(function() QB.callback.trigger('qbdispatch:setViewing', open) end)
end

---@param open boolean
function Dispatch.ui.setTablet(open)
    if not open then
        if not Dispatch.state.data.tabletOpen then return end
        Dispatch.state.setTabletOpen(false)
        QB.nui.closeApp('qbdispatch:tablet')
        setViewing(false)
        return
    end
    if Dispatch.state.data.tabletOpen or not Dispatch.state.isActive() then return end
    Dispatch.state.setTabletOpen(true)
    QB.nui.registerApp(appDefinition())
    setViewing(true)
    CreateThread(function()
        QB.nui.openApp('qbdispatch:tablet')
        if Dispatch.state.data.tabletOpen then
            Dispatch.state.setTabletOpen(false)
            setViewing(false)
        end
    end)
end
