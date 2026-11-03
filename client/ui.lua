-- Dispatch uses kora_lib's shared AppShell for its tablet. The dispatch resource
-- remains responsible for call state, response rules, routes and unit data;
-- kora_lib provides the common application frame, navigation and focus handling.

Dispatch = Dispatch or {}
Dispatch.ui = {}

-- Navigation from the last full tablet render and a fingerprint of the units it
-- drew, so a units heartbeat can patch just the map/units views (F#445).
local lastNavigation, lastUnitsKey

local function round(value, step)
    value = tonumber(value) or 0
    return math.floor(value / step + 0.5)
end

---Fingerprint of everything the tablet draws for units: identity, labels and a
---position rounded to 1 m and heading to 5 degrees.
local function unitsKey(units)
    local parts = {}
    for i, unit in ipairs(units or {}) do
        local coords = unit.coords
        parts[i] = ('%s;%s;%s;%s;%s;%d;%d;%d'):format(tostring(unit.src), unit.callsign or '', unit.name or '',
            unit.gradeLabel or '', unit.plate or '', coords and round(coords.x, 1) or 0,
            coords and round(coords.y, 1) or 0, round(unit.heading, 5))
    end
    return table.concat(parts, '|')
end

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
            metadata = {
                { label = 'Location', value = call.location or 'Unknown' },
                { label = 'Units', value = #(call.units or {}) },
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
                label = callTitle(call), description = call.location or call.message,
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
                label = unit.callsign or unit.name or ('Unit ' .. unit.src),
                description = unit.gradeLabel or unit.plate, icon = 'car',
                tone = unit.src == (S.unit and S.unit.src) and 'success' or 'neutral',
                heading = unit.heading,
            }
        end
    end
    return {
        type = 'map', id = 'live-map', title = 'Live dispatch map',
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
        empty = 'No active calls or unit positions to display.',
    }
end

local function selectedContent(S)
    local call = Dispatch.state.selected()
    if not call then
        return { title = 'Call details', blocks = { { type = 'empty', title = 'No call selected', description = 'Choose a call from the queue to see its details.', icon = 'radio' } } }
    end
    local mine = Dispatch.state.myStateOn(call)
    local nextState = mine == 'en_route' and 'on_scene' or mine == 'on_scene' and 'clear' or 'en_route'
    local nextLabel = mine == 'en_route' and 'Mark on scene' or mine == 'on_scene' and 'Clear call' or 'Accept call'
    local actions = {}
    if Dispatch.calls.isLive(call, Dispatch.state.now()) then
        actions[#actions + 1] = {
            id = 'dispatch:respond:' .. nextState, label = nextLabel, icon = 'radio', variant = 'primary',
        }
    end
    actions[#actions + 1] = { id = 'dispatch:route', label = 'Set route', icon = 'navigation', variant = 'secondary' }
    return {
        title = callTitle(call), description = callDescription(call),
        actions = actions,
        blocks = { { type = 'stats', items = {
            { label = 'Priority', value = call.priority or '—', icon = 'alert-triangle', tone = 'warning' },
            { label = 'Units assigned', value = #(call.units or {}), icon = 'users' },
            { label = 'Your response', value = mine and mine:gsub('_', ' ') or 'Not assigned', icon = 'radio', tone = mine and 'primary' or 'neutral' },
        } }, { type = 'details', title = 'Call information', columns = 2, items = {
            { label = 'Location', value = call.location or 'Unknown', icon = 'map-pin' },
            { label = 'Origin', value = call.origin or 'Dispatch', icon = 'radio' },
            { label = 'Created', value = call.createdAt or '—', icon = 'clock' },
            { label = 'Expires', value = call.expiresAt or '—', icon = 'clock', tone = 'warning' },
        } }, { type = 'timeline', title = 'Assigned units', empty = 'No units assigned.', items = (function()
            local items = {}
            for _, unit in ipairs(call.units or {}) do items[#items + 1] = {
                id = tostring(unit.src), title = unit.callsign or unit.name or ('Unit ' .. unit.src),
                description = (unit.state or 'assigned'):gsub('_', ' '), timestamp = tostring(unit.at or ''),
                icon = 'radio', tone = unit.state == 'on_scene' and 'success' or 'primary',
            } end
            return items
        end)() } },
    }
end

local function unitsView(S)
    local units = {}
    for _, unit in ipairs(S.units) do units[#units + 1] = {
        id = tostring(unit.src), label = (unit.callsign and unit.callsign .. ' · ' or '') .. (unit.name or ('Unit ' .. unit.src)),
        description = unit.gradeLabel or 'On duty', icon = 'users', tone = unit.src == (S.unit and S.unit.src) and 'primary' or 'neutral',
    } end
    return { id = 'units', label = 'Units', icon = 'users', badge = #S.units,
        content = { title = 'On-duty units', blocks = { { type = 'list', id = 'units', searchable = true,
            layout = 'cards', pageSize = 9, items = units, empty = 'No unit updates yet.' } } } }
end

local function appDefinition()
    local S = Dispatch.state.data
    local active = Dispatch.state.live()
    return {
        id = 'qbdispatch:tablet', title = (S.config and S.config.label) or 'Dispatch',
        description = S.unit and ((S.unit.callsign and S.unit.callsign .. ' · ' or '') .. (S.unit.name or ('Unit ' .. S.unit.src))) or 'Dispatch tablet',
        icon = 'radio', accent = Dispatch.theme.get(), width = 1220, height = 800,
        navigation = {
            { id = 'map', label = 'Live map', icon = 'map', badge = #active,
                content = { title = 'Live operations', description = 'Pan, zoom, and select a live call marker.',
                    blocks = { mapBlock(S, active), { type = 'list', id = 'map-calls', title = 'Active calls',
                        searchable = true, pageSize = 6, layout = 'cards', items = callItems(active, S.selected),
                        empty = 'No active calls. Everything is clear.' } } } },
            { id = 'queue', label = 'Active calls', icon = 'radio', badge = #active,
                content = { title = 'Active calls', description = 'Search or select a call to inspect it, respond or set a route.',
                    blocks = { { type = 'list', id = 'active-calls', searchable = true, pageSize = 8,
                        layout = 'cards', items = callItems(active, S.selected), empty = 'No active calls. Everything is clear.' } } } },
            { id = 'history', label = 'History', icon = 'history', badge = #S.order,
                content = { title = 'Call history', blocks = { { type = 'list', id = 'call-history', searchable = true,
                    pageSize = 10, items = callItems(Dispatch.state.all(), S.selected), empty = 'No calls in this shift.' } } } },
            { id = 'detail', label = 'Selected call', icon = 'map-pin', content = selectedContent(S) },
            unitsView(S),
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
            local state, err = Kora.callback.trigger('qbdispatch:respond', call.id, response)
            if state == false then error(err or 'Could not update the call.') end
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
    if S.tabletOpen then
        local definition = appDefinition()
        lastNavigation, lastUnitsKey = definition.navigation, unitsKey(S.units)
        Kora.nui.registerApp(definition)
    else
        lastNavigation, lastUnitsKey = nil, nil
    end
end

---Units heartbeat path (every few seconds while the tablet is open). Rebuilds only
---the map block and the units view, reuses the call lists from the last full
---render, and sends nothing when no unit moved or changed (F#445).
function Dispatch.ui.renderUnits()
    local S = Dispatch.state.data
    if not S.tabletOpen then return end
    if not lastNavigation then return Dispatch.ui.render() end
    local key = unitsKey(S.units)
    if key == lastUnitsKey then return end
    lastUnitsKey = key

    local navigation = {}
    for index, view in ipairs(lastNavigation) do
        if view.id == 'map' then
            local blocks = {}
            for i, block in ipairs(view.content.blocks) do
                blocks[i] = block.type == 'map' and mapBlock(S, Dispatch.state.live()) or block
            end
            local content = {}
            for k, v in pairs(view.content) do content[k] = v end
            content.blocks = blocks
            local copy = {}
            for k, v in pairs(view) do copy[k] = v end
            copy.content = content
            navigation[index] = copy
        elseif view.id == 'units' then
            navigation[index] = unitsView(S)
        else
            navigation[index] = view
        end
    end
    lastNavigation = navigation
    Kora.nui.updateApp('qbdispatch:tablet', { navigation = navigation })
end

local function setViewing(open)
    CreateThread(function() Kora.callback.trigger('qbdispatch:setViewing', open) end)
end

---@param open boolean
function Dispatch.ui.setTablet(open)
    if not open then
        if not Dispatch.state.data.tabletOpen then return end
        Dispatch.state.setTabletOpen(false)
        Kora.nui.closeApp('qbdispatch:tablet')
        setViewing(false)
        Dispatch.ui.render()
        return
    end
    if Dispatch.state.data.tabletOpen or not Dispatch.state.isActive() then return end
    Dispatch.state.setTabletOpen(true)
    Dispatch.ui.render()
    setViewing(true)
    CreateThread(function()
        Kora.nui.openApp('qbdispatch:tablet')
        if Dispatch.state.data.tabletOpen then
            Dispatch.state.setTabletOpen(false)
            setViewing(false)
            Dispatch.ui.render()
        end
    end)
end
