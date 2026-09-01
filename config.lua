Config = {}

-- --- services ---------------------------------------------------------------
--
-- A "service" is a qbcore JOB TYPE (`type` in qbcore/shared/jobs.lua), not a job
-- name. One service covers every job carrying that type -- 'leo' reaches police,
-- sheriff and state troopers at once -- which is the whole reason calls target
-- types rather than enumerating job names.
--
-- Note what is deliberately NOT here: there is no 'emergency' service. A scene
-- needing both police and paramedics is TWO calls, one per service, with the
-- wording each service actually needs. Bundling them would give both a feed they
-- can't clear independently and a history full of other people's calls.
--
-- `accent` is only the DEFAULT theme. A job resource sets its own at runtime
-- with exports.qbdispatch:setTheme('#RRGGBB') from its client, which is what
-- lets one player's dispatch be blue and another's red on the same server.
Config.services = {
    leo = {
        label = 'Police',
        accent = '#3B82F6', -- blue
        sound = { name = 'Lose_1st', set = 'GTAO_FM_Events_Soundset' },
    },
    ems = {
        label = 'EMS',
        accent = '#EF4444', -- red
        sound = { name = 'Lose_1st', set = 'GTAO_FM_Events_Soundset' },
    },
    recovery = {
        label = 'Recovery',
        accent = '#F59E0B', -- amber
        sound = { name = 'Menu_Accept', set = 'Phone_SoundSet_Default' },
    },
}

-- Fallback for a service with no entry above, so an unconfigured job type still
-- produces a working (if unbranded) dispatch rather than erroring.
Config.defaultService = {
    label = 'Dispatch',
    accent = '#DC143C',
    sound = { name = 'Lose_1st', set = 'GTAO_FM_Events_Soundset' },
}

-- --- priorities -------------------------------------------------------------
--
-- `ttl` is how long a call stays on the live feed and fades out on the map. It
-- is a SEVERITY signal, not a guess at response time: a carjacking is stale
-- within a couple of minutes because the vehicle has left, while a bank robbery
-- is still the most important thing on the map ten minutes later.
--
-- Expiry only removes a call from the LIVE view. It always stays in history.
Config.priorities = {
    [1] = { label = 'Critical', ttl = 600000, color = '#F04444' }, -- 10 minutes
    [2] = { label = 'High',     ttl = 300000, color = '#F59E0B' }, -- 5 minutes
    [3] = { label = 'Routine',  ttl = 120000, color = '#949494' }, -- 2 minutes
}
Config.defaultPriority = 2

-- --- history ----------------------------------------------------------------
Config.history = {
    max = 50,        -- calls retained per service; the oldest is dropped past this
    ttl = 3600000,   -- ms a closed/expired call stays readable in history (1 hour)
    sweepInterval = 60000, -- ms between retention sweeps
}

-- --- unit heartbeat ---------------------------------------------------------
--
-- Colleague positions are read SERVER-side (GetEntityCoords on the networked
-- ped) so this costs connected clients nothing at all, and it only runs while
-- somebody on that service actually has the tablet open -- an idle server does
-- zero work here.
Config.units = {
    heartbeat = 3000,   -- ms between position broadcasts to tablet viewers
    maxDistance = 0,    -- metres; 0 = whole map. Set >0 to only share nearby units.
}

-- --- feed -------------------------------------------------------------------
Config.feed = {
    maxVisible = 4,          -- live cards shown at once before older ones roll off
    position = 'left-center',-- 'left-center' | 'top-left' | 'top-center'
    -- Every other overlay in the framework has already claimed a corner: qbhud
    -- owns bottom-center/bottom-right/top-right, qblib toasts own top-right,
    -- qbinventory's item stack owns bottom-right, and the native minimap owns
    -- bottom-left. Left-center is the only large uncontested region.
}

-- --- keybinds ---------------------------------------------------------------
--
-- Defaults only. Every one of these is rebindable by the player through FiveM's
-- own key-binding settings, because QB.keybind.add registers a real key mapping.
Config.keybinds = {
    previous = 'PRIOR', -- Page Up   -- move selection towards newer calls
    next     = 'NEXT',  -- Page Down -- move selection towards older calls, into history
    respond  = 'HOME',  -- accept, then advance en route -> on scene -> clear
    toggle   = 'END',   -- hide/show the whole feed
    tablet   = 'F9',    -- open the large view (this one takes NUI focus)
}

-- --- map --------------------------------------------------------------------
--
-- Calls are NEVER drawn as game blips: the blip pool is small and a busy shift
-- would exhaust it. The tablet renders its own map instead, and exactly one real
-- blip exists at a time -- the route to the call you personally accepted.
Config.map = {
    -- Tile pyramid vendored under web/build/map/. 256px tiles, {z}/{x}/{y}.jpg,
    -- zoom 0..3 (a 2048x2048 image at the deepest level).
    tilePath = 'map/atlas',
    minZoom = 0,
    maxZoom = 3,
    tileSize = 256,

    -- World -> map projection, expressed as two reference points rather than
    -- opaque multipliers, so a server owner swapping in their own map image can
    -- recalibrate by standing on two landmarks and reading /dispatchcoords.
    -- `image` coordinates are pixels at maxZoom (2048x2048 at zoom 3).
    --
    -- These two are far apart on both axes (Legion Square in the south, Paleto
    -- Bay in the far north) so the derived scale is accurate across the whole
    -- map rather than fitted to one region.
    --
    -- The values come from the tile set's own coordinate system, and were
    -- VERIFIED against the shipped imagery rather than trusted: decoding the
    -- tiles and locating the largest inland body of water puts its centroid at
    -- world (1081, 4094) once inverted through this projection, which is the
    -- Alamo Sea to within about 100 metres. Ten land/water probe points across
    -- the map agree. See docs/map.md.
    calibration = {
        a = { world = { x = 195.17, y = -933.77 }, image = { x = 970.7,  y = 1535.5 } }, -- Legion Square
        b = { world = { x = -220.0, y = 6355.0  }, image = { x = 901.9,  y = 340.2  } }, -- Paleto Bay
    },

    -- A call marker holds full opacity for this fraction of its life, then eases
    -- out over the remainder. Fading from the very first second reads as "the UI
    -- is broken" rather than "this call is going stale".
    fadeHoldFraction = 0.6,
}

-- --- legacy compat ----------------------------------------------------------
Config.compat = {
    -- Turn the legacy police:server:policeAlert / hospital:server:ambulanceAlert
    -- events into real dispatch calls, for a third-party script written against
    -- qb-policejob.
    --
    -- OFF by default, and the reason matters. Two other things already listen on
    -- those names:
    --   * qbambulance's own server/compat/hospital.lua, which knows its job and
    --     its own wording -- a better call than this generic one can build.
    --   * qbcore itself, whose Core.dispatch.alert fires police:server:policeAlert
    --     as a LOCAL TriggerEvent in its legacy fan-out. With this enabled and
    --     `coreAlerts` on, one exports.qbcore:alert would produce TWO calls: one
    --     from the mirror below, one from the legacy event it just fired.
    --
    -- Enable it only on a server with no job resource handling these names.
    legacyInbound = false,
    -- qbcore's own Core.dispatch.alert push (qbcore:client:dispatchAlert) is
    -- also rendered, so anything calling exports.qbcore:alert directly still
    -- reaches a real UI instead of nothing.
    coreAlerts = true,
}

Config.debug = false
