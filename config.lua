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

-- --- response ---------------------------------------------------------------
Config.dispatch = {
    -- How many live calls one unit may be committed to at once. A unit at the
    -- cap must clear (or drop) a call before accepting another, which is what
    -- keeps a single officer from claiming every call on the board and leaving
    -- them all unattended.
    --
    -- Counted per PLAYER, not per call: a call may still gather as many
    -- responders as turn up. Only the accept is checked -- advancing en route ->
    -- on scene -> clear is always allowed, or a capped unit could never release
    -- the call holding it at the cap. `clear`, closed and expired calls do not
    -- count. Set 0 to disable the cap entirely.
    maxActiveCalls = 1,
}

-- --- player-originated alert ingress ---------------------------------------
--
-- A gameplay resource can register a fixed alert type and then raise it for a
-- player through `createPlayerCall`. The player supplies neither presentation
-- nor coordinates: qbdispatch reads their networked ped position and reuses the
-- registered definition. This is the safe bridge for client-observed incidents
-- such as shots fired; fully server-observed incidents keep using createCall.
Config.ingress = {
    defaultCooldown = 30000, -- ms per player and registered alert type
    minimumCooldown = 1000,  -- registrations cannot accidentally disable throttling
    maxLiveCalls = 100,      -- public-ingress calls allowed live across all services
    maxRegisteredTypes = 128, -- bounds registry/cooldown state on highly modular servers
}

-- `createCall` is the unrestricted server-to-server API: its caller chooses
-- wording, service and coordinates. Keep that power with known first-party
-- resources. Add a resource name here when installing another trusted server
-- script that intentionally raises free-form dispatch calls.
Config.trustedCallers = {
    qbdispatch = true,
    qbcore = true,
    qbpolice = true,
    qbambulance = true,
    qbbusinesses = true,
    qbrobberies = true,
}

-- --- feed -------------------------------------------------------------------
Config.feed = {
    maxVisible = 4,          -- live cards shown at once before older ones roll off
    position = 'left-center',-- 'left-center' | 'top-left' | 'top-center'
    -- Cards per page in the tablet's call list. The overlay feed above is a
    -- rolling window (maxVisible) and is not paginated -- it is glanceable, not
    -- browsable. The tablet is the browsable one.
    pageSize = 8,
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
-- A small, bounded set of ordinary map blips lets officers see live calls
-- without opening the tablet. These markers never set a GPS route; accepting a
-- call still creates the one route blip managed by client/blip.lua.
Config.map = {
    -- Keep the native map readable and avoid consuming GTA's finite blip pool
    -- during a busy shift. The highest-priority live calls win a slot.
    showCallBlips = true,
    maxCallBlips = 4,
    callBlipSprite = 161,
    callBlipScale = 0.85,

    -- Tile pyramid vendored under web/build/map/. 256px tiles,
    -- {z}/{x}/{y}.png, zoom 1..3 (2048x3072 at the deepest level).
    --
    -- This is the IN-GAME pause-map style -- the dark landmass and white road
    -- network the player already knows -- rather than the bright stylised
    -- "atlas" tourist map that shipped before. The atlas set is still vendored
    -- at map/atlas (square, 2048x2048, .jpg, zoom 0..3); switching back is
    -- tilePath + tileExtension + grid + a recalibration, nothing more.
    tilePath = 'map/mainmap',
    tileExtension = 'png',

    -- Starts at 1, not 0. This tile set's zoom-0 tile squeezes the whole
    -- 2:3 map into one 256x256 square, so it is not a uniform reduction of
    -- zoom 1 and would render the map vertically squashed. It is not shipped.
    minZoom = 1,
    maxZoom = 3,
    tileSize = 256,

    -- Tiles across and down at maxZoom. This basemap is NOT square -- 8x12 --
    -- so both axes have to be stated; a square pyramid can omit `grid`.
    grid = { x = 8, y = 12 },

    -- World -> map projection, expressed as two reference points rather than
    -- opaque multipliers, so a server owner swapping in their own map image can
    -- recalibrate by standing on two landmarks and reading /dispatchcoords.
    -- `image` coordinates are pixels at maxZoom (2048x3072 at zoom 3).
    --
    -- These two are far apart on both axes (Legion Square in the south, Paleto
    -- Bay in the far north) so the derived scale is accurate across the whole
    -- map rather than fitted to one region.
    --
    -- Derived by registering this tile set's landmass against the previously
    -- verified atlas set's, then VERIFIED by projecting nine known world
    -- positions and checking each against the rendered imagery -- see
    -- docs/map.md for both the method and the numbers.
    calibration = {
        a = { world = { x = 195.17, y = -933.77 }, image = { x = 985.2, y = 2126.8 } }, -- Legion Square
        b = { world = { x = -220.0, y = 6355.0  }, image = { x = 890.1, y = 474.3  } }, -- Paleto Bay
    },

    -- A call marker holds full opacity for this fraction of its life, then eases
    -- out over the remainder. Fading from the very first second reads as "the UI
    -- is broken" rather than "this call is going stale".
    fadeHoldFraction = 0.6,
}

-- --- immediate call alert ---------------------------------------------------
-- The tablet is optional, so a new call also produces a toast while it is
-- closed. Existing calls restored during login/on-duty hydration stay quiet.
Config.alerts = {
    notify = true,
    duration = 7000,
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

-- Development commands (/dispatchtest, /dispatchclear, /dispatchstatus) are
-- registered only while this is on, and are admin-gated even then. Turn it on to
-- exercise dispatch without needing a second player or an actual crime.
Config.debug = true

-- Registers this resource-owned configuration with qblib without changing its public Config table.
if QB and QB.config and QB.config.adopt then
    Config.feed.position = QB.config.enum(Config.feed.position, {
        label = 'Dispatch feed position',
        description = 'Selects where live dispatch cards appear on the screen. Left centre avoids the standard minimap, HUD, notification, and inventory surfaces; use a top position only when no other overlay occupies that area.',
        options = {
            { value = 'left-center', label = 'Left centre' },
            { value = 'top-left', label = 'Top left' },
            { value = 'top-center', label = 'Top centre' },
        },
    })
    Config = QB.config.adopt(Config)
end
