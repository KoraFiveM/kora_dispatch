-- Mocks for smoke-testing kora_dispatch under plain lua5.4 (no FiveM, no kora_core).
--
-- The clock is DRIVEN, not auto-advancing: expiry, fade and retention are the
-- behaviours most worth testing here, and every one of them is a comparison
-- against GetGameTimer. A clock that ticked on read would make "is this call
-- still live" untestable.

local M = {}

function M.install()
    local clock = 0
    local invokingResource

    local eventHandlers = {}
    local netHandlers = {}
    local clientEvents = {}
    local localEvents = {}
    local commands = {}
    local intervals = {}

    function _G.GetGameTimer() return clock end

    function _G.AddEventHandler(name, cb)
        eventHandlers[name] = eventHandlers[name] or {}
        table.insert(eventHandlers[name], cb)
    end

    function _G.RegisterNetEvent(name, cb)
        if not cb then return end
        netHandlers[name] = netHandlers[name] or {}
        table.insert(netHandlers[name], cb)
    end

    function _G.TriggerEvent(name, ...)
        table.insert(localEvents, { name = name, args = { ... } })
        for _, fn in ipairs(eventHandlers[name] or {}) do fn(...) end
        for _, fn in ipairs(netHandlers[name] or {}) do fn(...) end
    end

    function _G.TriggerClientEvent(name, target, ...)
        table.insert(clientEvents, { name = name, target = target, args = { ... } })
    end

    function _G.RegisterCommand(name, cb) commands[name] = cb end
    function _G.CreateThread(fn) fn() end
    function _G.Wait(_) end
    function _G.GetInvokingResource() return invokingResource end
    function _G.GetCurrentResourceName() return 'kora_dispatch' end
    local positionOfPed = {}
    function _G.GetPlayerPed(src) return 1000 + src end
    function _G.GetEntityCoords(entity) return positionOfPed[entity] or { x = 100.0, y = 200.0, z = 30.0 } end
    function _G.GetEntityHeading(_) return 90.0 end
    function _G.GetEntitySpeed(_) return 10.0 end
    function _G.DoesEntityExist(entity) return entity ~= nil and entity ~= 0 end

    -- src -> vehicle handle. Nothing is in a vehicle unless a test says so.
    local vehicleOf = {}
    function _G.GetVehiclePedIsIn(ped) return vehicleOf[ped] or 0 end
    function _G.GetVehicleType(_) return _G.__vehicleType or 'automobile' end
    function _G.GetVehicleNumberPlateText(_) return 'TEST123' end

    -- GetVehicleClass is deliberately NOT defined: it is a CLIENT-only native,
    -- and defining it here would let a regression back to it pass the tests and
    -- then throw on every heartbeat in game.

    -- --- the kora_core/qblib surfaces kora_dispatch actually calls ---
    --
    -- Registry contents mirror kora_core/shared/jobs.lua, because the single-service
    -- rule is enforced against real job->type relationships and a mock with a
    -- different shape would test nothing.
    local jobs = {
        { name = 'police',     label = 'Law Enforcement', type = 'leo' },
        { name = 'sheriff',    label = 'Sheriff',         type = 'leo' },
        { name = 'ambulance',  label = 'EMS',             type = 'ems' },
        { name = 'tow',        label = 'Recovery',        type = 'recovery' },
        { name = 'unemployed', label = 'Civilian',        type = 'civ' },
    }

    -- src -> { job, onDuty, name, callsign }
    local players = {}

    local qbcore = {}
    function qbcore:getShared(_registry, key)
        for _, record in ipairs(jobs) do if record.name == key then return record end end
        return nil
    end
    function qbcore:allShared() return jobs end
    function qbcore:getJob(src)
        local p = players[src]
        if not p then return nil end
        local record = qbcore:getShared('jobs', p.job)
        return { name = p.job, label = record and record.label, type = record and record.type,
                 onduty = p.onDuty, grade = { name = 'Grade', level = 1 } }
    end
    function qbcore:getPlayersByJob(name, onDutyOnly)
        local out = {}
        for src, p in pairs(players) do
            if p.job == name and (not onDutyOnly or p.onDuty) then out[#out + 1] = src end
        end
        table.sort(out)
        return out
    end
    function qbcore:getPlayersByJobType(jobType, onDutyOnly)
        local out = {}
        for src, p in pairs(players) do
            local record = qbcore:getShared('jobs', p.job)
            if record and record.type == jobType and (not onDutyOnly or p.onDuty) then out[#out + 1] = src end
        end
        table.sort(out)
        return out
    end
    function qbcore:getOnDutyRoster(filter)
        filter = filter or {}
        local onDutyOnly = filter.onDutyOnly
        if onDutyOnly == nil then onDutyOnly = true end

        local out = {}
        for src, p in pairs(players) do
            local record = qbcore:getShared('jobs', p.job)
            local jobType = record and record.type or 'none'
            local ok = (not onDutyOnly or p.onDuty)
                and (not filter.job or filter.job == p.job)
                and (not filter.jobType or filter.jobType == jobType)
            if ok then
                out[#out + 1] = { src = src, citizenid = 'CID' .. src, name = p.name or ('Unit ' .. src),
                                  callsign = p.callsign, job = p.job, jobLabel = record and record.label,
                                  jobType = jobType, grade = 1, gradeLabel = 'Grade', onDuty = p.onDuty }
            end
        end
        table.sort(out, function(a, b) return a.src < b.src end)
        return out
    end

    -- FXServer's `exports` is both callable (exports('name', fn) registers) and
    -- indexable (exports.kora_core:fn(...) calls). Mocked as a callable table so
    -- both forms work, and the registrations are recorded so a test can assert
    -- the public surface.
    --
    -- Colon-call dispatch passes the receiver as `self`, which the `function
    -- qbcore:fn(...)` sugar already declares -- so each method's named
    -- parameters line up with the real export's signature exactly.
    local registered = {}
    _G.exports = setmetatable({ kora_core = qbcore }, {
        __call = function(_, name, fn) registered[name] = fn end,
    })

    _G.QB = {
        util = {
            isFiniteNumber = function(value)
                return type(value) == 'number' and value == value and value ~= math.huge and value ~= -math.huge
            end,
        },
        timers = {
            setInterval = function(fn, ms)
                intervals[#intervals + 1] = { fn = fn, ms = ms }
                return #intervals
            end,
        },
        callback = { register = function() end, trigger = function() end },
        resources = {
            serverRegistry = function(onDispose)
                local owners = {}
                AddEventHandler('onResourceStop', function(resource)
                    for id, owner in pairs(owners) do
                        if owner == resource then owners[id] = nil; onDispose(id) end
                    end
                end)
                return {
                    track = function(resource, id) owners[id] = resource end,
                    untrack = function(id) local owner = owners[id]; owners[id] = nil; return owner end,
                    owner = function(id) return owners[id] end,
                }
            end,
        },
    }

    return {
        registeredExports = registered,
        clientEvents = clientEvents,
        localEvents = localEvents,
        eventHandlers = eventHandlers,
        commands = commands,
        intervals = intervals,

        ---Advances the driven clock.
        advance = function(ms) clock = clock + ms end,
        now = function() return clock end,
        setInvokingResource = function(resource) invokingResource = resource end,

        ---Puts a ped into a vehicle for the unit-snapshot path.
        setVehicle = function(src, vehicle, vehicleType)
            vehicleOf[1000 + src] = vehicle
            _G.__vehicleType = vehicleType
        end,

        ---Overrides one player's server-side ped position.
        setCoords = function(src, coords)
            positionOfPed[1000 + src] = coords
        end,

        ---Puts a player on/off duty in a job.
        setPlayer = function(src, job, onDuty, extra)
            players[src] = { job = job, onDuty = onDuty and true or false,
                             name = extra and extra.name, callsign = extra and extra.callsign }
        end,
        removePlayer = function(src) players[src] = nil end,

        ---Every recorded TriggerClientEvent with a given name.
        eventsNamed = function(name)
            local out = {}
            for _, e in ipairs(clientEvents) do if e.name == name then out[#out + 1] = e end end
            return out
        end,
        clearEvents = function()
            for i = #clientEvents, 1, -1 do clientEvents[i] = nil end
            for i = #localEvents, 1, -1 do localEvents[i] = nil end
        end,
    }
end

return M
