-- Development commands. Registered only while Config.debug is on, and gated on
-- the same admin ACE kora_core's own tooling uses -- these can put arbitrary text
-- and coordinates in front of every on-duty player of a service, which is not
-- something an ordinary player should be able to do.
--
-- Their whole purpose is making dispatch testable by ONE person: raising a real
-- call otherwise means committing a crime, dying, or waiting for a colleague.

if not Config.debug then return end

Dispatch = Dispatch or {}

-- Ranked levels, most-privileged first, matching kora_admin's own table. Ranked
-- rather than a single ACE string so a 'god' satisfies an 'admin' requirement --
-- which a bare IsPlayerAceAllowed(src, 'qbcore.admin') does not.
local LEVELS = { 'god', 'admin', 'mod', 'user' }
local PERMISSION_OPTIONS = { prefix = 'qbcore' }

---Delegates to kora_lib rather than hand-rolling an ACE check.
---
---QB.permissions.hasLevel accepts EITHER `kora_core.<level>` or the bare
---`group.<level>` principal, and folds in Discord roles where a server
---configures them. The hand-rolled version this replaces only ever tested
---`qbcore.admin`, so an admin who held `group.admin` -- which is how this test
---server's own server.cfg grants it -- was refused by dispatch while every
---other admin command on the server accepted them.
---@param source integer
---@param permission string
---@return boolean
local function isAdmin(source, permission)
    return QB.permissions.hasLevel(source, permission, LEVELS, PERMISSION_OPTIONS)
end

---The caller's own position, so a test call lands somewhere they can drive to
---rather than at the world origin.
---@param src integer
---@return table|nil
local function coordsOf(src)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return nil end
    local position = GetEntityCoords(ped)
    return { x = position.x, y = position.y, z = position.z }
end

-- A representative call per priority, so /dispatchtest exercises the real
-- severity model (badge, colour, lifetime, fade) rather than three identical
-- alerts that only differ by a number.
local SAMPLES = {
    [1] = { code = '10-90', title = 'Bank Robbery', icon = 'banknote',
            message = 'Silent alarm triggered. Two suspects reported inside.',
            data = { plate = '46EEK572', vehicle = 'Sultan', suspects = '2' } },
    [2] = { code = '10-31', title = 'Shots Fired', icon = 'crosshair',
            message = 'Automatic gunfire reported by multiple callers.',
            data = { weapon = 'Assault Rifle' } },
    [3] = { code = '10-16', title = 'Vehicle Theft', icon = 'car',
            message = 'A grey Bison was taken from a driveway.',
            data = { plate = 'ABC 123', vehicle = 'Bison' } },
}

QB.commands.add('dispatchtest', 'Raise a test call to your own service', {
    { name = 'priority', help = '1 critical, 2 high, 3 routine (default 2)' },
    { name = 'service', help = 'Override the service, e.g. leo / ems / recovery' },
}, false, function(source, args)
    local service = args[2]

    if not service then
        -- Default to the caller's own service, so the call actually arrives in
        -- the feed they are looking at.
        local job = exports.kora_core:getJob(source)
        service = job and job.type
        if not service or service == 'none' or service == 'civ' then
            return QB.notify.send(source, {
                message = 'You are not in a dispatch service. Pass one: /dispatchtest 1 leo',
                type = 'error',
            })
        end
    end

    local priority = math.floor(tonumber(args[1]) or Config.defaultPriority)
    local sample = SAMPLES[priority] or SAMPLES[Config.defaultPriority]

    local id, count = Dispatch.api.createCall({
        jobTypes = { service },
        code = sample.code,
        title = sample.title,
        message = sample.message,
        priority = priority,
        icon = sample.icon,
        coords = coordsOf(source),
        data = sample.data,
    })

    if not id then
        return QB.notify.send(source, { message = ('Test call refused: %s'):format(count), type = 'error' })
    end

    -- A call reaching nobody is the single most confusing outcome of this
    -- command: an admin raises it, sees a success notification, and nothing
    -- appears on their screen. Dispatch reaches ON-DUTY members of a service
    -- only, and a job's `type` is readable whether or not you are on duty --
    -- so an off-duty officer testing their own service lands here every time.
    -- Naming the cause is the difference between a one-line fix (/police-duty)
    -- and hunting a phantom bug in the push path.
    if count == 0 then
        local job = exports.kora_core:getJob(source)
        local selfService = job and job.type
        local hint = (selfService == service and not (job and job.onduty))
            and ' You are OFF DUTY -- go on duty and it will reach you.'
            or ' Nobody is on duty for that service.'

        return QB.notify.send(source, {
            message = ('Raised #%d (%s, P%d) but it reached 0 units.%s'):format(id, service, priority, hint),
            type = 'error',
        })
    end

    QB.notify.send(source, {
        message = ('Raised #%d (%s, P%d) to %d unit(s).'):format(id, service, priority, count),
        type = 'success',
    })
end, { permission = 'admin', checkPermission = isAdmin })

QB.commands.add('dispatchclear', 'Close every live call on your service', {}, false, function(source)
    local job = exports.kora_core:getJob(source)
    local service = job and job.type
    if not service then
        return QB.notify.send(source, { message = 'You are not in a dispatch service.', type = 'error' })
    end

    local closed = 0
    for _, call in ipairs(Dispatch.api.getCalls({ service = service, activeOnly = true })) do
        if Dispatch.api.closeCall(call.id, 'cleared by an admin') then closed = closed + 1 end
    end

    QB.notify.send(source, { message = ('Closed %d call(s).'):format(closed), type = 'success' })
end, { permission = 'admin', checkPermission = isAdmin })

QB.commands.add('dispatchstatus', 'Print dispatch state to the server console', {}, false, function(source)
    print('[qbdispatch] ---- status ----')
    print(('  tablet viewers: %d'):format(Dispatch.units.viewerCount()))

    for _, service in ipairs(Dispatch.store.services()) do
        local live = #Dispatch.api.getCalls({ service = service, activeOnly = true })
        local total = #Dispatch.api.getCalls({ service = service })
        local onDuty = #exports.kora_core:getOnDutyRoster({ jobType = service })
        print(('  %-10s %d live / %d in history, %d on duty'):format(service, live, total, onDuty))
    end

    QB.notify.send(source, { message = 'Dispatch status printed to the server console.', type = 'info' })
end, { permission = 'admin', checkPermission = isAdmin })
