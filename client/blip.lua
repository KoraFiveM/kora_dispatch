-- Exactly one game blip exists at a time: the route to the call you personally
-- accepted.
--
-- This is the whole reason the tablet renders its own map. GTA's blip pool is
-- small and shared with every other resource on the server; a busy shift that
-- dropped a blip per call would exhaust it and start silently breaking garages,
-- shops and job markers everywhere else. Calls live on the rendered map, and the
-- one thing that genuinely benefits from the real map -- turn-by-turn routing to
-- where you are actually going -- gets the single blip.

Dispatch = Dispatch or {}
Dispatch.blip = {}

local active
local activeCallId

---Clears the current route blip, if any.
function Dispatch.blip.clear()
    if active then
        QB.blips.remove(active)
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

    local priority = Config.priorities[call.priority] or Config.priorities[Config.defaultPriority]

    local blip = QB.blips.create(call.coords, {
        sprite = 161,
        color = call.priority == 1 and 1 or (call.priority == 2 and 47 or 4),
        scale = 0.9,
        shortRange = false,
        label = ('%s%s'):format(call.code and (call.code .. ' - ') or '', call.title or 'Dispatch'),
        route = true,
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
    if activeCallId ~= call.id then return end

    if call.closedAt then return Dispatch.blip.clear() end

    -- Cleared units are done with the call; keeping their route would send them
    -- to the last incident forever.
    if Dispatch.state.myStateOn(call) == 'clear' then Dispatch.blip.clear() end
end
