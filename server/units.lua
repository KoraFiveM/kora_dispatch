-- Colleague positions for the tablet map.
--
-- Two decisions worth stating up front, because both are the difference between
-- this being free and this being a per-frame tax on every client:
--
-- 1. Positions are read SERVER-side. Under OneSync the server can read a
--    networked ped's coordinates directly, so no client runs a loop, no client
--    sends its position, and there is no round trip. qbambulance's /911e already
--    relies on the same property.
-- 2. The tick only runs while somebody is actually looking. Clients announce
--    when their tablet opens and closes; a service with no viewers is skipped
--    entirely, and with no viewers at all the interval does nothing but check an
--    empty table. An idle server pays nothing for this feature.

Dispatch = Dispatch or {}
Dispatch.units = {}

-- src -> service they are viewing. One viewer can only look at their own
-- service's map, so this doubles as the per-service subscriber set.
local viewers = {}

-- GetVehicleTYPE, not GetVehicleClass. Class is a CLIENT-ONLY native (it is
-- absent from citizen/scripting/lua/natives_server.lua, which has GetVehicleType
-- instead), so calling it here would throw the moment any unit got into a
-- vehicle -- taking the whole heartbeat down and leaving every tablet with an
-- empty map for reasons nothing would explain.
--
-- Type is the better fit anyway: the UI wants "what shape is this unit" at a
-- glance, not GTA's 22-way commercial/industrial/utility taxonomy.
local ICON_FOR_TYPE = {
    automobile = 'car',
    amphibious_automobile = 'car',
    bike = 'bike',
    bicycle = 'bike',
    quadbike = 'offroad',
    amphibious_quadbike = 'offroad',
    boat = 'boat',
    submarine = 'boat',
    submarinecar = 'boat',
    heli = 'heli',
    plane = 'heli',
    blimp = 'heli',
    trailer = 'truck',
    train = 'truck',
}

---@param vehicle integer
---@return string
local function iconForVehicle(vehicle)
    return ICON_FOR_TYPE[GetVehicleType(vehicle)] or 'car'
end

---A live position snapshot for one on-duty unit, or nil when their ped is gone.
---@param unit table Roster record from qbcore.
---@return table|nil
local function snapshot(unit)
    local ped = GetPlayerPed(unit.src)
    if not ped or ped == 0 then return nil end

    local coords = GetEntityCoords(ped)
    -- A ped that has not finished streaming in sits at the origin. Publishing
    -- that would park every joining colleague on the map at (0,0) in the ocean.
    if coords.x == 0.0 and coords.y == 0.0 then return nil end

    local vehicle = GetVehiclePedIsIn(ped, false)
    local inVehicle = vehicle and vehicle ~= 0 and DoesEntityExist(vehicle)

    return {
        src = unit.src,
        name = unit.name,
        callsign = unit.callsign,
        job = unit.job,
        jobLabel = unit.jobLabel,
        grade = unit.gradeLabel,
        coords = { x = coords.x, y = coords.y, z = coords.z },
        heading = GetEntityHeading(ped),
        vehicle = inVehicle and iconForVehicle(vehicle) or 'foot',
        plate = inVehicle and GetVehicleNumberPlateText(vehicle) or nil,
        speed = inVehicle and math.floor(GetEntitySpeed(vehicle) * 2.236936) or 0, -- m/s -> mph
    }
end

---@param a table
---@param b table
---@return number
local function distanceSquared(a, b)
    local dx, dy, dz = a.x - b.x, a.y - b.y, (a.z or 0.0) - (b.z or 0.0)
    return dx * dx + dy * dy + dz * dz
end

---Builds and sends one service's unit list to its viewers.
---@param service string
---@param watchers integer[]
local function broadcast(service, watchers)
    local units = {}
    local positions = {}
    for _, unit in ipairs(exports.qbcore:getOnDutyRoster({ jobType = service })) do
        local snap = snapshot(unit)
        if snap then
            units[#units + 1] = snap
            positions[snap.src] = snap.coords
        end
    end

    local maxDistance = tonumber(Config.units.maxDistance) or 0
    local rangeSquared = maxDistance > 0 and maxDistance * maxDistance or nil

    -- The viewer is INCLUDED in their own list. They are a unit like any other,
    -- the map needs to draw them (and marks them "you"), and the call detail
    -- computes distance and bearing from their position -- none of which works
    -- if the one unit the UI can't do without is the one filtered out. That also
    -- means a viewer is never range-filtered out of their own list.
    for _, src in ipairs(watchers) do
        if not rangeSquared or not positions[src] then
            TriggerClientEvent('qbdispatch:client:units', src, units)
        else
            local origin = positions[src]
            local visible = {}
            for _, unit in ipairs(units) do
                if unit.src == src or distanceSquared(origin, unit.coords) <= rangeSquared then
                    visible[#visible + 1] = unit
                end
            end
            TriggerClientEvent('qbdispatch:client:units', src, visible)
        end
    end
end

---@param src integer
---@param service string|nil nil stops them viewing.
function Dispatch.units.setViewer(src, service)
    viewers[src] = service
end

---One heartbeat across every service that currently has a viewer.
function Dispatch.units.tick()
    local watchersByService = {}
    for src, service in pairs(viewers) do
        watchersByService[service] = watchersByService[service] or {}
        table.insert(watchersByService[service], src)
    end

    for service, watchers in pairs(watchersByService) do
        broadcast(service, watchers)
    end
end

---@return integer
function Dispatch.units.viewerCount()
    local n = 0
    for _ in pairs(viewers) do n = n + 1 end
    return n
end

AddEventHandler('qbcore:server:playerDropped', function(src) viewers[src] = nil end)
AddEventHandler('playerDropped', function() viewers[source] = nil end)

CreateThread(function()
    QB.timers.setInterval(Dispatch.units.tick, Config.units.heartbeat)
end)
