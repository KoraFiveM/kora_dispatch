-- The client-side exports: presentation only.
--
-- Everything that creates or mutates a call is a SERVER export (server/api.lua)
-- -- a client must not be able to invent an incident or expire someone else's.
-- What genuinely belongs here is the part that is per-player by nature: which
-- colour this player's dispatch is, because two players on the same server see
-- different accents at the same moment.

Dispatch = Dispatch or {}

---Sets this player's dispatch accent colour.
---
---A job resource calls this from its own client code on load:
---    exports.qbdispatch:setTheme('#3B82F6')
---@param hex string `#RRGGBB`, or nil to restore the service default.
---@return boolean ok, string|nil error
exports('setTheme', function(hex)
    return Dispatch.theme.set(hex)
end)

---Overrides presentation options for this player.
---@param options { position: string|nil, maxVisible: integer|nil, hidden: boolean|nil }
---@return boolean
exports('setUiOptions', function(options)
    if type(options) ~= 'table' then return false end

    local S = Dispatch.state.data
    S.config = S.config or {}
    S.config.feed = S.config.feed or {}

    if type(options.position) == 'string' then S.config.feed.position = options.position end
    if tonumber(options.maxVisible) then S.config.feed.maxVisible = math.floor(options.maxVisible) end
    if options.hidden ~= nil then Dispatch.state.setHidden(options.hidden) end

    Dispatch.ui.render()
    return true
end)

---Opens or closes the tablet programmatically -- for a job resource binding it
---to an in-world computer or an item rather than the key.
---@param open boolean
exports('setTablet', function(open)
    Dispatch.ui.setTablet(open and true or false)
end)

---This player's service ('leo', 'ems', ...), or nil when off duty. Lets a job
---resource skip work when its user isn't actually on a dispatch service.
---@return string|nil
exports('getService', function()
    return Dispatch.state.data.service
end)

---The call this player has a route to, or nil.
---@return integer|nil
exports('getRoutedCall', function()
    return Dispatch.blip.callId()
end)
