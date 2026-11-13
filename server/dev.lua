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
-- which a bare IsPlayerAceAllowed(src, 'kora_core.admin') does not.
local LEVELS = { 'god', 'admin', 'mod', 'user' }
local PERMISSION_OPTIONS = { prefix = 'kora_core' }

---Delegates to kora_lib rather than hand-rolling an ACE check.
---
---Kora.permissions.hasLevel accepts EITHER `kora_core.<level>` or the bare
---`group.<level>` principal, and folds in Discord roles where a server
---configures them. The hand-rolled version this replaces only ever tested
---`kora_core.admin`, so an admin who held `group.admin` -- which is how this test
---server's own server.cfg grants it -- was refused by dispatch while every
---other admin command on the server accepted them.
---@param source integer
---@param permission string
---@return boolean
local function isAdmin(source, permission)
    return Kora.permissions.hasLevel(source, permission, LEVELS, PERMISSION_OPTIONS)
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
    [1] = { code = '10-90', title = Kora.lang('Debug.sample_bank_title'), icon = 'banknote',
            message = Kora.lang('Debug.sample_bank_message'),
            data = { plate = '46EEK572', vehicle = 'Sultan', suspects = '2' } },
    [2] = { code = '10-31', title = Kora.lang('Debug.sample_shots_title'), icon = 'crosshair',
            message = Kora.lang('Debug.sample_shots_message'),
            data = { weapon = 'Assault Rifle' } },
    [3] = { code = '10-16', title = Kora.lang('Debug.sample_theft_title'), icon = 'car',
            message = Kora.lang('Debug.sample_theft_message'),
            data = { plate = 'ABC 123', vehicle = 'Bison' } },
}

Kora.commands.add('dispatchtest', Kora.lang('Debug.command_test'), {
    { name = 'priority', help = Kora.lang('Debug.arg_priority') },
    { name = 'service', help = Kora.lang('Debug.arg_service') },
}, false, function(source, args)
    local service = args[2]

    if not service then
        -- Default to the caller's own service, so the call actually arrives in
        -- the feed they are looking at.
        local job = exports.kora_core:getJob(source)
        service = job and job.type
        if not service or service == 'none' or service == 'civ' then
            return Kora.notify.send(source, {
                message = Kora.lang('Debug.no_service_test'),
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
        return Kora.notify.send(source, { message = Kora.lang('Debug.test_refused', count), type = 'error' })
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
        return Kora.notify.send(source, {
            message = (selfService == service and not (job and job.onduty))
                and Kora.lang('Debug.raised_no_units_off_duty', id, service, priority)
                or Kora.lang('Debug.raised_no_units', id, service, priority),
            type = 'error',
        })
    end

    Kora.notify.send(source, {
        message = Kora.lang('Debug.raised_units', id, service, priority, count),
        type = 'success',
    })
end, { permission = 'admin', checkPermission = isAdmin })

Kora.commands.add('dispatchclear', Kora.lang('Debug.command_clear'), {}, false, function(source)
    local job = exports.kora_core:getJob(source)
    local service = job and job.type
    if not service then
        return Kora.notify.send(source, { message = Kora.lang('Debug.no_service'), type = 'error' })
    end

    local closed = 0
    for _, call in ipairs(Dispatch.api.getCalls({ service = service, activeOnly = true })) do
        if Dispatch.api.closeCall(call.id, 'cleared by an admin') then closed = closed + 1 end
    end

    Kora.notify.send(source, { message = Kora.lang('Debug.closed_calls', closed), type = 'success' })
end, { permission = 'admin', checkPermission = isAdmin })

Kora.commands.add('dispatchstatus', Kora.lang('Debug.command_status'), {}, false, function(source)
    print('[kora_dispatch] ---- status ----')
    print(('  tablet viewers: %d'):format(Dispatch.units.viewerCount()))

    for _, service in ipairs(Dispatch.store.services()) do
        local live = #Dispatch.api.getCalls({ service = service, activeOnly = true })
        local total = #Dispatch.api.getCalls({ service = service })
        local onDuty = #exports.kora_core:getOnDutyRoster({ jobType = service })
        print(('  %-10s %d live / %d in history, %d on duty'):format(service, live, total, onDuty))
    end

    Kora.notify.send(source, { message = Kora.lang('Debug.status_printed'), type = 'info' })
end, { permission = 'admin', checkPermission = isAdmin })
