-- Exactly one game blip exists at a time for the route to the call you
-- personally accepted. A separate, small capped set of non-routing markers
-- makes live incidents visible on GTA's normal map.
--
-- The cap is deliberate: GTA's blip pool is shared with every resource. The
-- tablet retains the complete queue and map; the native map gets only the most
-- urgent few calls.

Dispatch = Dispatch or {}
Dispatch.blip = {}

local active
local activeCallId
local callBlips = {}

local function alertColor(call)
    if call.priority == 1 then return 1 end
    if call.priority == 2 then return 47 end
    return 5
end

local function alertName(call)
    return ('%s%s'):format(
        call.code or '',
        call.title and ((call.code and ' - ' or '') .. call.title) or ''
    )
end

local function alertLabel(call)
    local name = alertName(call)
    return name ~= '' and Kora.lang('Blip.title', name) or Kora.lang('Blip.dispatch')
end

local function callLocation(call)
    return call.data and call.data.street
end

local function callInfo(call)
    local priority = Config.priorities[call.priority] or Config.priorities[Config.defaultPriority]
    return {
        title = alertLabel(call),
        rows = {
            { kind = 'name', label = Kora.lang('Blip.priority'), value = priority.label },
            { kind = 'name', label = Kora.lang('Blip.location'), value = callLocation(call) or Kora.lang('UI.location_unavailable') },
            { kind = 'wrappedText', value = call.message or Kora.lang('UI.no_details') },
        },
    }
end

local function removeCallBlip(id)
    local blip = callBlips[id]
    if blip then Kora.blips.remove(blip) end
    callBlips[id] = nil
end

---Synchronises the bounded native-map markers to live calls. Markers are
---informational only; none receives a GPS route.
function Dispatch.blip.refreshCalls()
    local map = Config.map or {}
    local limit = tonumber(map.maxCallBlips) or 0
    if not map.showCallBlips or limit < 1 then
        for id in pairs(callBlips) do removeCallBlip(id) end
        return
    end

    local live = Dispatch.state.live()
    table.sort(live, function(a, b)
        if a.priority == b.priority then return a.createdAt > b.createdAt end
        return a.priority < b.priority
    end)

    local desired, desiredIds = {}, {}
    for _, call in ipairs(live) do
        if #desiredIds >= limit then break end
        if call.coords then
            desired[call.id] = call
            desiredIds[#desiredIds + 1] = call.id
        end
    end

    for id in pairs(callBlips) do
        if not desired[id] then removeCallBlip(id) end
    end

    for _, id in ipairs(desiredIds) do
        local call = desired[id]
        if not callBlips[id] then
            local name = alertName(call)
            local blip = Kora.blips.create(call.coords, {
                sprite = map.callBlipSprite or 161,
                color = alertColor(call),
                scale = map.callBlipScale or 0.85,
                name = name ~= '' and name or nil,
                shortRange = false,
                category = Kora.lang('Blip.dispatch'),
                info = callInfo(call),
            })
            if blip then callBlips[id] = blip end
        else
            Kora.blips.setInfo(callBlips[id], callInfo(call))
        end
    end
end

function Dispatch.blip.clearCalls()
    for id in pairs(callBlips) do removeCallBlip(id) end
end

---Clears the current route blip, if any.
function Dispatch.blip.clear()
    if active then
        Kora.blips.remove(active)
        active = nil
        activeCallId = nil
    end
end

---Routes to a call, replacing any existing route.
---@param call table|nil
---@return boolean
function Dispatch.blip.route(call)
    Dispatch.blip.clear()

    if not call or not call.coords then return false end

    local blip = Kora.blips.create(call.coords, {
        sprite = 161,
        color = call.priority == 1 and 1 or (call.priority == 2 and 47 or 4),
        scale = 0.9,
        shortRange = false,
        category = Kora.lang('Blip.dispatch'),
        name = ('%s%s'):format(call.code and (call.code .. ' - ') or '', call.title or Kora.lang('Blip.dispatch')),
        route = true,
        info = callInfo(call),
    })

    if not blip then return false end

    active = blip
    activeCallId = call.id
    return true
end

---@return integer|nil
function Dispatch.blip.callId()
    return activeCallId
end

---Drops the route when the call it points at is no longer worth driving to.
---@param call table
function Dispatch.blip.onCallChanged(call)
    Dispatch.blip.refreshCalls()
    if activeCallId ~= call.id then return end

    if call.closedAt then return Dispatch.blip.clear() end

    -- Cleared units are done with the call; keeping their route would send them
    -- to the last incident forever.
    if Dispatch.state.myStateOn(call) == 'clear' then Dispatch.blip.clear() end
end

-- Expiry is clock-based, so an otherwise quiet call has no server update to
-- remove its marker. A low-frequency local sweep keeps the normal map honest
-- without polling the server or touching the tablet.
Kora.timers.setInterval(function()
    if Dispatch.state.isActive() then Dispatch.blip.refreshCalls() end
end, 5000)
