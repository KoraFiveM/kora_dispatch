-- Per-service UI colour.
--
-- The accent is applied CLIENT-side, on purpose: two players on the same server
-- see different colours at the same moment because they belong to different
-- services, so this can never be a server setting. A job resource calls
-- exports.kora_dispatch:setTheme('#3B82F6') from its own client code and owns its
-- own brand.

Dispatch = Dispatch or {}
Dispatch.theme = {}

local current
local currentTokens

---@param hex any
---@return boolean
local function isHex(hex)
    return type(hex) == 'string' and hex:match('^#%x%x%x%x%x%x$') ~= nil
end

---The player's /theme colour, or nil to use the kora_theme server default.
---@return string|nil
local function playerColour()
    if GetResourceState('kora_theme') ~= 'started' then return nil end
    local ok, colour = pcall(function() return exports.kora_theme:getPlayerTheme() end)
    return ok and isHex(colour) and colour or nil
end

---Applies an accent colour to the dispatch UI.
---
---kora_lib validates and applies the accent in the shared AppShell's own frame;
---this resource only selects the per-service primary override.
---@param hex string|nil `#RRGGBB`; nil restores the service default.
---@return boolean ok, string|nil error
function Dispatch.theme.set(hex)
    if hex ~= nil and not isHex(hex) then
        return false, ('accent must be a #RRGGBB hex colour, got %s'):format(tostring(hex))
    end

    if hex == nil then
        local S = Dispatch.state.data
        hex = (S.config and S.config.accent) or Config.defaultService.accent
    end

    -- A nil accent here means "follow kora_theme": the AppShell then keeps the
    -- player's /theme colour, and the feed tokens are derived from it below.
    current = hex

    local ok, tokens = pcall(function() return Kora.theme.tokens(hex or playerColour()) end)
    if not ok or type(tokens) ~= 'table' then
        return false, 'failed to derive theme tokens'
    end

    currentTokens = { primary = tokens.primary, ['brand-soft'] = tokens['brand-soft'], ['brand-border'] = tokens['brand-border'] }
    Dispatch.ui.render()
    return true
end

---@return string|nil
function Dispatch.theme.get()
    return current
end

---@return table|nil
function Dispatch.theme.tokens()
    return currentTokens
end

---Re-applies whatever accent is in force. Called after hydrate, so a service
---that never calls setTheme still gets its configured default.
function Dispatch.theme.refresh()
    Dispatch.theme.set(current)
end

-- A /theme change must reach the feed tokens too (the AppShell follows it on
-- its own). Only matters while no explicit accent is pinned.
AddEventHandler('kora_theme:playerThemeChanged', function()
    if current == nil then Dispatch.theme.refresh() end
end)
