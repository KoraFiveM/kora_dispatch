-- The client's view of dispatch: which service it belongs to, the call cache,
-- and the selection cursor the keybinds move. Every other client file reads from
-- here rather than keeping its own copy.

Dispatch = Dispatch or {}
Dispatch.state = {}

-- Server clock minus client clock.
--
-- GetGameTimer() is NOT a shared clock: on the server it counts server uptime,
-- on a client it counts that client's own session. Every timestamp on a call
-- (createdAt/expiresAt) is stamped with the SERVER's, so comparing one against a
-- local GetGameTimer() is meaningless -- depending on which process started
-- first, every call would read as either permanently live or already expired.
--
-- The server sends its own clock with each push; the offset learned from that is
-- what makes Dispatch.state.now() comparable with a call's timestamps.
local clockOffset = 0

local S = {
    service = nil,      -- our job type, nil when off duty
    unit = nil,         -- our own roster record
    config = nil,       -- service label/accent/priorities/feed/map, from the server
    calls = {},         -- id -> wire call
    order = {},         -- call ids, newest first
    selected = nil,     -- currently highlighted call id
    hidden = false,     -- feed toggled off by the player
    tabletOpen = false,
    units = {},         -- colleague snapshots from the heartbeat
}

Dispatch.state.data = S

---Records the server clock reported alongside a push.
---@param serverNow integer|nil
function Dispatch.state.syncClock(serverNow)
    if type(serverNow) ~= 'number' then return end
    clockOffset = serverNow - GetGameTimer()
end

---The current time in the SERVER's clock -- the only one a call's timestamps
---can be compared against.
---@return integer
function Dispatch.state.now()
    return GetGameTimer() + clockOffset
end

---@return boolean
function Dispatch.state.isActive()
    return S.service ~= nil
end

---Rebuilds the ordered id list, newest first, and trims the cache.
---
---The trim matters over a long shift: the server prunes its own history, but a
---client only learns about a pruned call by re-hydrating, so without this the
---local cache would grow for every call ever received in the session -- and the
---tablet renders all of them into the list. Mirrors the server rule: only dead
---calls are ever dropped, oldest first, never a live one however long the
---backlog.
local function reorder()
    local order = {}
    for id in pairs(S.calls) do order[#order + 1] = id end
    table.sort(order, function(a, b)
        local ca, cb = S.calls[a], S.calls[b]
        if ca.createdAt == cb.createdAt then return a > b end
        return ca.createdAt > cb.createdAt
    end)

    local limit = Config.history.max
    if #order > limit then
        local now = Dispatch.state.now()
        for index = #order, 1, -1 do
            if #order <= limit then break end
            local id = order[index]
            local call = S.calls[id]
            if call.closedAt or now >= call.expiresAt then
                S.calls[id] = nil
                if S.selected == id then S.selected = nil end
                table.remove(order, index)
            end
        end
    end

    S.order = order
end

---@param call table
function Dispatch.state.upsert(call)
    if type(call) ~= 'table' or not call.id then return end
    local isNew = S.calls[call.id] == nil
    S.calls[call.id] = call
    -- Reordered on every upsert, not only on insert: an update is also the
    -- moment the trim above gets a chance to notice calls that have since died.
    reorder()
    return isNew
end

---@param calls table[]
function Dispatch.state.replaceAll(calls)
    S.calls = {}
    for _, call in ipairs(calls or {}) do S.calls[call.id] = call end
    reorder()

    -- A selection that no longer exists would leave the respond keybind acting
    -- on nothing with no visible reason why.
    if S.selected and not S.calls[S.selected] then S.selected = nil end
end

---@param id integer
---@return table|nil
function Dispatch.state.get(id)
    return S.calls[id]
end

---@return table|nil
function Dispatch.state.selected()
    return S.selected and S.calls[S.selected] or nil
end

---Our own state on a call ('en_route' | 'on_scene' | 'clear'), or nil.
---@param call table
---@return string|nil
function Dispatch.state.myStateOn(call)
    if not call or not S.unit then return nil end
    for _, unit in ipairs(call.units or {}) do
        if unit.src == S.unit.src then return unit.state end
    end
    return nil
end

---Moves the selection. `delta` of 1 goes towards older calls (and on into
---history), -1 towards newer.
---
---With nothing selected, the first press selects the newest call rather than
---jumping to an arbitrary position -- the common case is "something just came
---in, deal with it".
---@param delta integer
---@return table|nil call
function Dispatch.state.moveSelection(delta)
    if #S.order == 0 then return nil end

    local index
    if S.selected then
        for i, id in ipairs(S.order) do
            if id == S.selected then index = i break end
        end
    end
    if not index then
        S.selected = S.order[1]
        return S.calls[S.selected]
    end

    -- Clamped, not wrapped. Wrapping from the oldest call back to the newest
    -- makes it impossible to tell you have reached the end of the log.
    local target = math.max(1, math.min(#S.order, index + delta))
    S.selected = S.order[target]
    return S.calls[S.selected]
end

---@param id integer|nil
function Dispatch.state.select(id)
    S.selected = (id and S.calls[id]) and id or nil
end

---Live calls only, newest first, capped for the feed.
---@param limit integer|nil
---@return table[]
function Dispatch.state.live(limit)
    local now = Dispatch.state.now()
    local out = {}
    for _, id in ipairs(S.order) do
        local call = S.calls[id]
        if not call.closedAt and now < call.expiresAt then
            out[#out + 1] = call
            if limit and #out >= limit then break end
        end
    end
    return out
end

---@return table[] every known call, newest first
function Dispatch.state.all()
    local out = {}
    for _, id in ipairs(S.order) do out[#out + 1] = S.calls[id] end
    return out
end

---@param service string|nil
---@param unit table|nil
---@param config table|nil
function Dispatch.state.setService(service, unit, config)
    S.service = service
    S.unit = unit
    S.config = config
    if not service then
        S.calls, S.order, S.selected, S.units = {}, {}, nil, {}
        S.tabletOpen = false
    end
end

---@param units table[]
function Dispatch.state.setUnits(units)
    S.units = type(units) == 'table' and units or {}
end

---@param hidden boolean
function Dispatch.state.setHidden(hidden)
    S.hidden = hidden and true or false
end

---@param open boolean
function Dispatch.state.setTabletOpen(open)
    S.tabletOpen = open and true or false
end
