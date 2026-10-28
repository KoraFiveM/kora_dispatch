-- Resolving "who does this call reach" -- the one place job names, job types and
-- the single-service rule are enforced.

Dispatch = Dispatch or {}
Dispatch.recipients = {}

---The job type of a registered job, or nil when the job is unknown.
---@param jobName string
---@return string|nil
function Dispatch.recipients.typeOfJob(jobName)
    local record = exports.kora_core:getShared('jobs', jobName)
    return record and (record.type or 'none') or nil
end

---Every registered job name carrying a given type.
---@param jobType string
---@return string[]
function Dispatch.recipients.jobsOfType(jobType)
    local out = {}
    for _, record in ipairs(exports.kora_core:allShared('jobs')) do
        if (record.type or 'none') == jobType then out[#out + 1] = record.name end
    end
    return out
end

---Turns a call's `jobs`/`jobTypes` into one service plus the concrete job names
---it covers.
---
---**A call belongs to exactly one service.** Mixing services is refused rather
---than silently split, because there is no such thing as an "emergency" service:
---police and paramedics attending the same scene want different wording, keep
---separate histories, and clear independently. Making that two explicit calls is
---the whole point, so a mixed target is a caller bug worth reporting, not
---something to paper over.
---@param jobs string[]
---@param jobTypes string[]
---@return string|nil service, string[]|nil jobs, string|nil error
function Dispatch.recipients.resolve(jobs, jobTypes)
    local services, serviceList = {}, {}
    local names, nameList = {}, {}

    local function addService(service)
        if not services[service] then
            services[service] = true
            serviceList[#serviceList + 1] = service
        end
    end

    local function addJob(name)
        if not names[name] then
            names[name] = true
            nameList[#nameList + 1] = name
        end
    end

    for _, jobName in ipairs(jobs) do
        local jobType = Dispatch.recipients.typeOfJob(jobName)
        if not jobType then
            return nil, nil, ("unknown job '%s'"):format(jobName)
        end
        addService(jobType)
        addJob(jobName)
    end

    for _, jobType in ipairs(jobTypes) do
        local ofType = Dispatch.recipients.jobsOfType(jobType)
        -- A type with no registered jobs is refused rather than accepted as an
        -- empty call: it is almost always a typo ('police' passed as a jobType,
        -- 'leo' as a job), and an accepted-but-unreachable call is a silent
        -- failure a robbery script would never notice.
        if #ofType == 0 then
            return nil, nil, ("no registered job carries the type '%s'"):format(jobType)
        end
        addService(jobType)
        for _, name in ipairs(ofType) do addJob(name) end
    end

    if #serviceList > 1 then
        table.sort(serviceList)
        return nil, nil, ('a call targets exactly one service, got %s -- raise one call per service'):format(
            table.concat(serviceList, ', '))
    end

    return serviceList[1], nameList, nil
end

---On-duty sources for a resolved call, deduplicated.
---
---Resolved by job TYPE when the call covers a whole service (one O(1) index
---read) and by job name otherwise, rather than looping every job every time.
---@param service string
---@param jobs string[]
---@return integer[]
function Dispatch.recipients.sources(service, jobs)
    local ofType = Dispatch.recipients.jobsOfType(service)

    -- Covering the whole service means the type index answers it directly.
    if #ofType == #jobs then
        return exports.kora_core:getPlayersByJobType(service, true)
    end

    local seen, out = {}, {}
    for _, jobName in ipairs(jobs) do
        for _, src in ipairs(exports.kora_core:getPlayersByJob(jobName, true)) do
            if not seen[src] then
                seen[src] = true
                out[#out + 1] = src
            end
        end
    end
    return out
end

---The roster record for one source, or nil when they are not on duty anywhere.
---@param src integer
---@return table|nil
function Dispatch.recipients.unitOf(src)
    local job = exports.kora_core:getJob(src)
    if not job then return nil end

    for _, unit in ipairs(exports.kora_core:getOnDutyRoster({ job = job.name })) do
        if unit.src == src then return unit end
    end
    return nil
end
