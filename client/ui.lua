-- Dispatch uses kora_lib's shared AppShell for its tablet. The dispatch resource
-- remains responsible for call state, response rules, routes and unit data;
-- kora_lib provides the common application frame, navigation and focus handling.

Dispatch = Dispatch or {}
Dispatch.ui = {}

local function callTitle(call)
    return (call.code and (call.code .. ' · ') or '') .. (call.title or Kora.lang('UI.call'))
end

-- A call carries no top-level `location` field -- the street name, when a
-- reporter's client supplied one, rides in `data.street` (see e.g.
-- kora_ambulance's /911e). Reading `call.location` here always read nil.
local function callLocation(call)
    return call.data and call.data.street
end

local function callDescription(call)
    return table.concat({ call.message or Kora.lang('UI.no_details'), callLocation(call) or Kora.lang('UI.location_unavailable') }, '\n')
end

local function callItems(calls, selected)
    local out = {}
    for _, call in ipairs(calls) do
        out[#out + 1] = {
            id = tostring(call.id), label = callTitle(call), description = callDescription(call),
            icon = call.id == selected and 'radio' or 'map-pin', badge = call.priority,
            tone = call.id == selected and 'primary' or 'neutral', action = 'dispatch:select',
            metadata = {
                { label = Kora.lang('UI.location'), value = callLocation(call) or Kora.lang('UI.unknown') },
                { label = Kora.lang('UI.units'), value = #(call.units or {}) },
            },
        }
    end
    return out
end

local function markerTone(priority)
    priority = tonumber(priority) or 3
    if priority <= 1 then return 'destructive' end
    if priority == 2 then return 'warning' end
    return 'primary'
end

local function mapBlock(S, calls)
    local map = (S.config and S.config.map) or Config.map
    local fadeHoldFraction = math.max(0, math.min(1, tonumber(map.fadeHoldFraction) or 0.6))
    local markers = {}
    for _, call in ipairs(calls) do
        if call.coords then
            local lifespan = math.max(0, (tonumber(call.expiresAt) or 0) - (tonumber(call.createdAt) or 0))
            markers[#markers + 1] = {
                id = tostring(call.id), x = call.coords.x, y = call.coords.y,
                label = callTitle(call), description = callLocation(call) or call.message,
                icon = call.icon or 'map-pin', tone = markerTone(call.priority),
                action = 'dispatch:select', expiresAt = call.expiresAt,
                fadeDuration = lifespan * (1 - fadeHoldFraction),
            }
        end
    end
    for _, unit in ipairs(S.units or {}) do
        if unit.coords then
            markers[#markers + 1] = {
                id = 'unit:' .. tostring(unit.src), x = unit.coords.x, y = unit.coords.y,
                label = unit.callsign or unit.name or Kora.lang('UI.unit', unit.src),
                description = unit.gradeLabel or unit.plate, icon = 'car',
                tone = unit.src == (S.unit and S.unit.src) and 'success' or 'neutral',
                heading = unit.heading,
            }
        end
    end
    return {
        type = 'map', id = 'live-map', title = Kora.lang('UI.map'),
        tiles = {
            url = ('https://cfx-nui-kora_dispatch/web/build/%s/{z}/{x}/{y}.%s')
                :format(map.tilePath, map.tileExtension or 'jpg'),
            tileSize = map.tileSize, grid = map.grid, calibration = map.calibration,
        },
        minZoom = map.minZoom, maxZoom = map.maxZoom, initialZoom = 0.5,
        captureWheel = map.captureWheel ~= false,
        markers = markers, selectedId = S.selected and tostring(S.selected) or nil,
        recenter = S.unit and S.unit.coords or nil, follow = true,
        now = Dispatch.state.now(),
        empty = Kora.lang('UI.no_calls_map'),
    }
end

local function selectedContent(S)
    local call = Dispatch.state.selected()
    if not call then
        return { title = Kora.lang('UI.call_details'), blocks = { { type = 'empty', title = Kora.lang('UI.no_call_selected'), description = Kora.lang('UI.choose_call'), icon = 'radio' } } }
    end
    local mine = Dispatch.state.myStateOn(call)
    local nextState = mine == 'en_route' and 'on_scene' or mine == 'on_scene' and 'clear' or 'en_route'
    local nextLabel = mine == 'en_route' and Kora.lang('UI.mark_on_scene') or mine == 'on_scene' and Kora.lang('UI.clear_call') or Kora.lang('UI.accept_call')
    local actions = {}
    if Dispatch.calls.isLive(call, Dispatch.state.now()) then
        actions[#actions + 1] = {
            id = 'dispatch:respond:' .. nextState, label = nextLabel, icon = 'radio', variant = 'primary',
        }
    end
    actions[#actions + 1] = { id = 'dispatch:route', label = Kora.lang('UI.set_route'), icon = 'navigation', variant = 'secondary' }
    return {
        title = callTitle(call), description = callDescription(call),
        actions = actions,
        blocks = { { type = 'stats', items = {
            { label = Kora.lang('UI.priority'), value = call.priority or '-', icon = 'alert-triangle', tone = 'warning' },
            { label = Kora.lang('UI.units_assigned'), value = #(call.units or {}), icon = 'users' },
            { label = Kora.lang('UI.your_response'), value = mine and Kora.lang('State.' .. mine) or Kora.lang('UI.not_assigned'), icon = 'radio', tone = mine and 'primary' or 'neutral' },
        } }, { type = 'details', title = Kora.lang('UI.call_information'), columns = 2, items = {
            { label = Kora.lang('UI.location'), value = callLocation(call) or Kora.lang('UI.unknown'), icon = 'map-pin' },
            { label = Kora.lang('UI.origin'), value = call.origin or Kora.lang('UI.dispatch'), icon = 'radio' },
            { label = Kora.lang('UI.created'), value = call.createdAt or '-', icon = 'clock' },
            { label = Kora.lang('UI.expires'), value = call.expiresAt or '-', icon = 'clock', tone = 'warning' },
        } }, { type = 'timeline', title = Kora.lang('UI.assigned_units'), empty = Kora.lang('UI.no_units_assigned'), items = (function()
            local items = {}
            for _, unit in ipairs(call.units or {}) do items[#items + 1] = {
                id = tostring(unit.src), title = unit.callsign or unit.name or Kora.lang('UI.unit', unit.src),
                description = Kora.lang('State.' .. (unit.state or 'assigned')), timestamp = tostring(unit.at or ''),
                icon = 'radio', tone = unit.state == 'on_scene' and 'success' or 'primary',
            } end
            return items
        end)() } },
    }
end

local function appDefinition()
    local S = Dispatch.state.data
    local active = Dispatch.state.live()
    return {
        id = 'kora_dispatch:tablet', title = (S.config and S.config.label) or Kora.lang('UI.dispatch'),
        description = S.unit and ((S.unit.callsign and S.unit.callsign .. ' · ' or '') .. (S.unit.name or ('Unit ' .. S.unit.src))) or Kora.lang('UI.tablet'),
        icon = 'radio', accent = Dispatch.theme.get(), width = 1220, height = 800,
        navigation = {
            { id = 'map', label = Kora.lang('UI.live_map'), icon = 'map', badge = #active,
                content = { title = Kora.lang('UI.live_operations'), description = Kora.lang('UI.map_help'),
                    blocks = { mapBlock(S, active), { type = 'list', id = 'map-calls', title = Kora.lang('UI.active_calls'),
                        searchable = true, pageSize = 6, layout = 'cards', items = callItems(active, S.selected),
                        empty = Kora.lang('UI.no_active_calls') } } } },
            { id = 'queue', label = Kora.lang('UI.active_calls'), icon = 'radio', badge = #active,
                content = { title = Kora.lang('UI.active_calls'), description = Kora.lang('UI.active_calls_help'),
                    blocks = { { type = 'list', id = 'active-calls', searchable = true, pageSize = 8,
                        layout = 'cards', items = callItems(active, S.selected), empty = Kora.lang('UI.no_active_calls') } } } },
            { id = 'history', label = Kora.lang('UI.history'), icon = 'history', badge = #S.order,
                content = { title = Kora.lang('UI.call_history'), blocks = { { type = 'list', id = 'call-history', searchable = true,
                    pageSize = 10, items = callItems(Dispatch.state.all(), S.selected), empty = Kora.lang('UI.no_calls_this_shift') } } } },
            { id = 'detail', label = Kora.lang('UI.selected_call'), icon = 'map-pin', content = selectedContent(S) },
            { id = 'units', label = Kora.lang('UI.units_tab'), icon = 'users', badge = #S.units,
                content = { title = Kora.lang('UI.on_duty_units'), blocks = { { type = 'list', id = 'units', searchable = true,
                    layout = 'cards', pageSize = 9, items = (function()
                    local units = {}
                    for _, unit in ipairs(S.units) do units[#units + 1] = {
                        id = tostring(unit.src), label = (unit.callsign and unit.callsign .. ' · ' or '') .. (unit.name or Kora.lang('UI.unit', unit.src)),
                        description = unit.gradeLabel or Kora.lang('UI.on_duty'), icon = 'users', tone = unit.src == (S.unit and S.unit.src) and 'primary' or 'neutral',
                    } end
                    return units
                end)(), empty = Kora.lang('UI.no_unit_updates') } } } },
        },
        footer = Kora.lang('UI.footer'),
        onAction = function(actionId, context)
            if actionId == 'dispatch:select' then
                local id = tonumber(context and context.itemId)
                Dispatch.state.select(id)
                return { update = { navigation = appDefinition().navigation } }
            end
            local call = Dispatch.state.selected()
            if not call then error(Kora.lang('UI.select_call_first')) end
            if actionId == 'dispatch:route' then
                Dispatch.blip.route(call)
                return {}
            end
            local response = actionId:match('^dispatch:respond:(.+)$')
            if not response then error(Kora.lang('UI.unknown_action')) end
            local state, err = Kora.callback.trigger('kora_dispatch:respond', call.id, response)
            if state == false then error(err or Kora.lang('UI.update_failed')) end
            return { update = { navigation = appDefinition().navigation } }
        end,
    }
end

function Dispatch.ui.render()
    local S = Dispatch.state.data
    if not Dispatch.state.isActive() or S.tabletOpen then
        Kora.nui.setDispatchFeed(false)
    else
        Kora.nui.setDispatchFeed({
            now = Dispatch.state.now(), calls = Dispatch.state.all(),
            selected = S.selected, hidden = S.hidden, me = S.unit,
            config = {
                feed = (S.config and S.config.feed) or Config.feed,
                priorities = (S.config and S.config.priorities) or Config.priorities,
            },
            keybinds = Config.keybinds, theme = Dispatch.theme.tokens(),
        })
    end
    if S.tabletOpen then Kora.nui.registerApp(appDefinition()) end
end

local function setViewing(open)
    CreateThread(function() Kora.callback.trigger('kora_dispatch:setViewing', open) end)
end

---@param open boolean
function Dispatch.ui.setTablet(open)
    if not open then
        if not Dispatch.state.data.tabletOpen then return end
        Dispatch.state.setTabletOpen(false)
        Kora.nui.closeApp('kora_dispatch:tablet')
        setViewing(false)
        Dispatch.ui.render()
        return
    end
    if Dispatch.state.data.tabletOpen or not Dispatch.state.isActive() then return end
    Dispatch.state.setTabletOpen(true)
    Dispatch.ui.render()
    setViewing(true)
    CreateThread(function()
        Kora.nui.openApp('kora_dispatch:tablet')
        if Dispatch.state.data.tabletOpen then
            Dispatch.state.setTabletOpen(false)
            setViewing(false)
            Dispatch.ui.render()
        end
    end)
end
