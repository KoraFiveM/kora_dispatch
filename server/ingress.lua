-- Safe ingress for incidents first observed by a client. Gameplay resources
-- register fixed alert definitions at startup and public events submit only the
-- registered key. kora_dispatch owns the shared rate limit, live-call ceiling and
-- server-side reporter position lookup, so none of those controls are copied
-- across every job resource.

Dispatch = Dispatch or {}
Dispatch.ingress = {}

local definitions = {}
local registeredCount = 0
local lastRequestAt = {}

local function removeDefinition(key)
    if not definitions[key] then return end
    definitions[key] = nil
    registeredCount = registeredCount - 1

    for _, byType in pairs(lastRequestAt) do byType[key] = nil end
end

local ownership = Kora.resources.serverRegistry(removeDefinition)

---@param value any
---@return table
local function copyList(value)
    local result = {}
    for index, entry in ipairs(value or {}) do result[index] = entry end
    return result
end

---@param definition table
---@return table|nil definition, string|nil error
local function normaliseDefinition(definition)
    if type(definition) ~= 'table' then return nil, 'definition must be a table' end

    local payload, err = Dispatch.calls.normalise(definition, {
        priorities = Config.priorities,
        defaultPriority = Config.defaultPriority,
    })
    if not payload then return nil, err end

    local cooldown = tonumber(definition.cooldown) or Config.ingress.defaultCooldown
    if not Kora.util.isFiniteNumber(cooldown) then return nil, 'cooldown must be a finite number' end
    cooldown = math.floor(cooldown)
    if cooldown < Config.ingress.minimumCooldown then
        return nil, ('cooldown must be at least %dms'):format(Config.ingress.minimumCooldown)
    end

    -- A registered client-originated incident may never carry a server hook.
    -- Otherwise repeatedly raising the public incident would also repeatedly
    -- invoke arbitrary server behavior when a unit accepts it.
    payload.onAccept = nil
    payload.jobs = copyList(payload.jobs)
    payload.jobTypes = copyList(payload.jobTypes)

    -- Definition metadata is static, but copy one level so a caller mutating
    -- its registration table after the export returns cannot rewrite live
    -- policy behind kora_dispatch's back.
    if payload.data then
        local data = {}
        for key, value in pairs(payload.data) do
            if type(key) == 'string' and (type(value) == 'string' or type(value) == 'number'
                or type(value) == 'boolean') then
                data[key] = value
            end
        end
        payload.data = data
    end
    if type(payload.sound) == 'table' then
        payload.sound = { name = payload.sound.name, set = payload.sound.set }
    else
        payload.sound = nil
    end

    if definition.requiredJobType ~= nil and (type(definition.requiredJobType) ~= 'string'
        or definition.requiredJobType == '') then
        return nil, 'requiredJobType must be a non-empty string'
    end

    payload.cooldown = cooldown
    payload.requiredJobType = definition.requiredJobType
    return payload
end

---@param key string
---@param definition table
---@param owner? string
---@return boolean ok, string|nil error
function Dispatch.ingress.register(key, definition, owner)
    if type(key) ~= 'string' or not key:match('^[%w][%w:._%-]*$') or #key > 64 then
        return false, 'alert key must be 1-64 letters, numbers, dots, dashes, underscores or colons'
    end

    owner = owner or GetInvokingResource() or GetCurrentResourceName()
    if type(owner) ~= 'string' or owner == '' then return false, 'alert owner is unavailable' end
    if Config.trustedCallers and Config.trustedCallers[owner] ~= true then
        return false, ('resource %q is not allowed to register player alerts'):format(owner)
    end

    local existing = definitions[key]
    if existing and existing.owner ~= owner then
        return false, ('alert type %q is owned by %s'):format(key, existing.owner)
    end
    if not existing and registeredCount >= Config.ingress.maxRegisteredTypes then
        return false, 'player alert registry is full'
    end

    local normalised, err = normaliseDefinition(definition)
    if not normalised then return false, err end

    normalised.owner = owner
    definitions[key] = normalised
    if not existing then registeredCount = registeredCount + 1 end
    ownership.track(owner, key)
    return true
end

---@param src integer
---@return table|nil coords
local function coordsOfSource(src)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 or not DoesEntityExist(ped) then return nil end
    return Dispatch.calls.toCoords(GetEntityCoords(ped))
end

---@param src integer
---@param key string
---@return integer|false callId
---@return integer|string recipientCountOrError
---@return integer|nil remainingCooldownMs
function Dispatch.ingress.create(src, key)
    src = tonumber(src)
    if not Kora.util.isFiniteNumber(src) or src <= 0 or type(key) ~= 'string' then
        return false, 'invalid player alert request'
    end
    src = math.floor(src)

    local definition = definitions[key]
    if not definition then return false, 'unknown player alert type' end

    local caller = GetInvokingResource() or GetCurrentResourceName()
    if definition.owner ~= caller then
        return false, ('resource %q does not own alert type %q'):format(caller, key)
    end

    if definition.requiredJobType then
        local unit = Dispatch.recipients.unitOf(src)
        if not unit or unit.jobType ~= definition.requiredJobType then
            return false, 'reporter is not an eligible on-duty unit'
        end
    end

    local now = GetGameTimer()
    local byType = lastRequestAt[src]
    local last = byType and byType[key]
    if last then
        local remaining = definition.cooldown - (now - last)
        if remaining > 0 then return false, 'player alert is cooling down', remaining end
    end

    local coords = coordsOfSource(src)
    if not coords then return false, 'reporter entity is unavailable' end

    -- Consume the request window before the bounded live-call scan. A caller at
    -- capacity must not be able to hammer that scan every network packet; this
    -- is a request throttle, not a reward cooldown.
    if not byType then
        byType = {}
        lastRequestAt[src] = byType
    end
    byType[key] = now

    if Dispatch.store.countLive() >= Config.ingress.maxLiveCalls then
        return false, 'player alert capacity reached'
    end

    local data = {}
    for field, value in pairs(definition.data or {}) do data[field] = value end
    data.incident = key
    data.reporter = src

    local payload = {
        code = definition.code,
        title = definition.title,
        message = definition.message,
        priority = definition.priority,
        jobs = copyList(definition.jobs),
        jobTypes = copyList(definition.jobTypes),
        coords = coords,
        icon = definition.icon,
        sound = definition.sound,
        duration = definition.ttl,
        data = data,
    }

    local callId, result = Dispatch.api.createCall(payload)
    if not callId then return false, result end
    return callId, result
end

-- Do not export register() directly: its third argument exists only so this
-- resource can own its internal compatibility types. An external caller must
-- never be able to pass a forged owner name through the export boundary.
exports('registerPlayerAlert', function(key, definition)
    return Dispatch.ingress.register(key, definition)
end)
exports('createPlayerCall', Dispatch.ingress.create)

AddEventHandler('playerDropped', function() lastRequestAt[source] = nil end)
AddEventHandler('qbcore:server:playerDropped', function(src) lastRequestAt[src] = nil end)

-- Test seams: reset only transient cooldowns. Definitions are resource-owned
-- registrations and intentionally survive store resets.
function Dispatch.ingress._resetCooldowns() lastRequestAt = {} end
