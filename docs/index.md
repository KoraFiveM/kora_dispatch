# qbdispatch

Job-agnostic dispatch for the qblib framework: a call lifecycle, a keyboard-driven
alert feed, and an optional tablet with a rendered map.

Dispatch knows nothing about police, medicine or towing. It transports and
presents calls; deciding that a gunshot is a police matter belongs to the police
resource, and a bank robbery's alert belongs to the robbery script.

---

## Services, not jobs

A **service** is a qbcore job **type** (`type` in `qbcore/shared/jobs.lua`), not a
job name. One service covers every job carrying that type, so a call to `leo`
reaches police, sheriff and state troopers at once — and a server that adds a
department gets it on the radio with no code change anywhere.

Stock types: `leo`, `ems`, `recovery`, `civ`.

**A call belongs to exactly one service.** There is deliberately no `emergency`
type. A scene needing both police and paramedics is **two calls**:

```lua
exports.qbdispatch:createCall({ jobTypes = { 'leo' }, code = '10-99', title = 'Officer Down', ... })
exports.qbdispatch:createCall({ jobTypes = { 'ems' }, code = '10-52', title = 'Officer Down', ... })
```

Each service then gets the wording it actually needs (one asks for backup, the
other for a patient), its own history, and the ability to clear independently. A
call targeting two services is **refused**, with an error saying so — that is a
caller bug worth reporting, not something to paper over.

---

## Server exports

Everything that creates or mutates a call is server-side: a call must be
authoritative, and the recipient roster only exists on the server.

### `exports.qbdispatch:createCall(payload)`

Raises a call. Returns `callId, recipientCount`, or `false, error`.

The recipient count is how a caller tells "help is coming" from "nobody is on
duty" — worth surfacing to whoever raised it.

| Field | Type | Notes |
| --- | --- | --- |
| `jobTypes` | `string[] \| string` | The service(s). Must resolve to exactly one. |
| `jobs` | `string[] \| string` | Specific job names instead of, or alongside, `jobTypes`. |
| `title` | `string` | Falls back to `message` when omitted. |
| `message` | `string` | Full description. Either this or `title` is required. |
| `code` | `string` | Short radio code shown as a badge (`10-90`). |
| `priority` | `1 \| 2 \| 3` | 1 critical, 2 high, 3 routine. Defaults to 2. Out-of-range falls back rather than erroring. |
| `coords` | `vector3 \| {x,y,z}` | Where. Without it the call has no map marker. |
| `icon` | `string` | Lucide icon key — see `web/src/components/icons.tsx`. |
| `duration` | `number` | ms, overriding the priority's own lifetime. |
| `sound` | `table` | Overrides the service's alert tone. |
| `data` | `table` | Freeform, passed through untouched and rendered in the detail panel. |
| `onAccept` | `string` | Server event fired when a unit **first** attaches. See below. |

Aliases accepted for drop-in compatibility with ps-dispatch/qb-phone era
payloads: `description` → `message`, `job` → `jobs`, `dispatchCode` → `code`.

```lua
local id, reached = exports.qbdispatch:createCall({
    jobTypes = { 'leo' },
    code     = '10-90',
    title    = 'Bank Robbery',
    message  = 'Silent alarm — Fleeca, Legion Square.',
    priority = 1,
    coords   = coords,
    icon     = 'banknote',
    data     = { plate = 'ABC123', vehicle = 'Sultan' },
})

if reached == 0 then
    -- nobody on duty; tell the caller, or fall back to something else
end
```

### `exports.qbdispatch:updateCall(id, patch)`

Revises an **open** call in place and re-pushes it to every recipient — for "the
suspect vehicle is now a red Sultan", not for closing.

`id`, `service` and `jobs` are identity and cannot be patched; letting an update
rewrite them would silently move a call between feeds. Raising `priority`
re-bases the deadline on the call's creation time, so a call escalated to
critical gains a critical call's lifetime while its elapsed timer stays honest.

Returns `ok, error`.

### `exports.qbdispatch:closeCall(id, reason?)`

Closes a call. It leaves the live feed immediately and stays in history with the
reason attached. Returns `ok, error`.

### `exports.qbdispatch:getCall(id)`

The wire form of one call, or `nil`.

### `exports.qbdispatch:getCalls(filter?)`

Newest first. `filter` accepts `service`, `job`, `activeOnly`.

### `exports.qbdispatch:setUnitState(src, id, state?)`

Attaches a unit, advances them, or detaches them.

- omit `state` → advance one step (`nil → en_route → on_scene → clear`)
- pass a state explicitly to jump to it
- pass `false` to detach

Returns the new state, or `false, error`. Refuses a player who is off duty or on
a different service to the call.

### `exports.qbdispatch:getOnDutyUnits(filter?)`

The on-duty roster, straight from qbcore's maintained index. `filter` accepts
`service` and `job`.

---

## The `onAccept` hook

A call may name a server event to fire when a unit **first** attaches:

```lua
exports.qbdispatch:createCall({
    jobTypes = { 'ems' },
    title    = 'House Call',
    onAccept = 'qbambulance:server:housecallAccepted',
    data     = { requestId = 7 },
})
```

```lua
RegisterNetEvent('qbambulance:server:housecallAccepted', function(src, callId, data)
    if source ~= 0 and source ~= nil then return end -- server-raised only
    claim(src, data.requestId)
end)
```

It fires **once**, on the first attach only. Later advances (on scene, clear) are
progress reports, not fresh acceptances — firing again would have a work queue
hand the same job out three times.

Dispatch has no idea what a house call is. It fires the event name it was given,
which is exactly what keeps job-specific behaviour out of this resource.

---

## Client exports

Presentation only, because presentation is per-player: an officer and a paramedic
on the same server see different accents at the same moment.

| Export | Purpose |
| --- | --- |
| `exports.qbdispatch:setTheme('#3B82F6')` | This player's accent. `nil` restores the service default. |
| `exports.qbdispatch:setUiOptions({ position =, maxVisible =, hidden = })` | Feed placement and density. |
| `exports.qbdispatch:setTablet(open)` | Open/close the tablet programmatically — for binding it to an in-world computer or an item. |
| `exports.qbdispatch:getService()` | This player's service, or `nil` off duty. |
| `exports.qbdispatch:getRoutedCall()` | The call this player has a route to, or `nil`. |

Accent tokens are derived by `QB.theme.tokens()` in qblib, so every framework
surface stays consistent and the HSL maths lives in one place.

---

## Player controls

All rebindable through FiveM's own key-binding settings.

| Default | Action |
| --- | --- |
| `Page Up` / `Page Down` | Move the selection; keeps scrolling past live calls into history. |
| `Home` | Accept, then en route → on scene → clear. With nothing selected it responds to the newest live call. |
| `End` | Hide/show the feed. |
| `F9` | Open the tablet. |

The feed is pointer-transparent and never takes NUI focus, so a call can be
worked without losing camera control — the difference between dispatch being
usable during a pursuit and being something dealt with afterwards. The tablet is
the only surface that takes focus, and it is optional.

Key hints appear only while a call is selected: permanently on-screen they would
be clutter, absent entirely the controls would be undiscoverable.

---

## Blips and the map

**Calls are never game blips.** GTA's blip pool is small and shared with every
other resource on the server; a busy shift dropping a blip per call would exhaust
it and start silently breaking garages, shops and job markers everywhere else.

Exactly one real blip exists at a time: the route to the call **you** accepted.
Everything else is drawn on the tablet's own map, where the marker count costs
the game engine nothing.

See [map.md](map.md) for the basemap, the projection, and how to recalibrate for
a different image.

---

## Severity and fade

`Config.priorities` gives each priority a lifetime. It is a severity signal, not
a guess at response time: a carjacking is stale within a couple of minutes
because the vehicle has left, while a bank robbery is still the most important
thing on the map ten minutes later.

| Priority | Default lifetime |
| --- | --- |
| 1 Critical | 10 minutes |
| 2 High | 5 minutes |
| 3 Routine | 2 minutes |

A marker holds full opacity for the first 60% of a call's life then eases out —
fading from the very first second reads as a broken UI rather than as a call
going stale.

Expiry removes a call from the **live** view only. It always stays in history
(`Config.history`), and retention never evicts a live call to make room, however
long the backlog.

---

## Colleague positions

The tablet shows on-duty colleagues with a vehicle-type icon and callsign.

Two things keep this free:

1. **Positions are read server-side.** Under OneSync the server reads a networked
   ped's coordinates directly, so no client runs a loop, sends its position, or
   waits on a round trip.
2. **The tick only runs while somebody is looking.** Clients announce when their
   tablet opens; a service with no viewers is skipped entirely, and an idle
   server does no work at all.

`Config.units.heartbeat` (default 3000ms) sets the rate.

---

## Legacy compatibility

`exports.qbcore:alert` keeps working: qbcore fires a server-side
`qbcore:server:dispatchAlert` once per alert, and dispatch mirrors it into a real
call. Anything already written against that API gets a proper UI instead of a
notification that vanishes.

`Config.compat.legacyInbound` can additionally claim
`police:server:policeAlert` and `hospital:server:ambulanceAlert`. It ships **off**,
because a job resource usually owns those names already and qbcore re-fires
`police:server:policeAlert` itself — enabling both would produce two calls per
alert. Turn it on only on a server with no job resource handling them.

The legacy signature is not stable across the ecosystem (real qb-policejob fires
`(coords, text)`, qbcore's compat table fires `(message, coords)`), so both orders
are sniffed rather than assumed.

---

## Adding a new service

A non-emergency service is a config entry, not a code change:

```lua
-- qbcore/shared/jobs.lua
{ name = 'tow', label = 'Recovery', type = 'recovery', grades = { ... } }
```

```lua
-- qbdispatch/config.lua
Config.services.recovery = {
    label = 'Recovery',
    accent = '#F59E0B',
    sound = { name = 'Menu_Accept', set = 'Phone_SoundSet_Default' },
}
```

```lua
-- the tow resource's own server code
exports.qbdispatch:createCall({
    jobTypes = { 'recovery' },
    code = '10-72',
    title = 'Vehicle Recovery',
    message = 'A vehicle needs recovering from the Great Ocean Highway.',
    priority = 3,
    coords = coords,
    icon = 'truck',
})
```

```lua
-- and its client, for the amber theme
exports.qbdispatch:setTheme('#F59E0B')
```

---

## Testing

**In game:** see [testing.md](testing.md) — `/dispatchtest` raises a real call to
your own service so the whole system can be exercised solo, without committing a
crime or waiting for a colleague.

**Offline:** `test/run.sh` — plain Lua, no FiveM, no database. The clock in `test/mocks.lua` is
**driven** rather than auto-advancing, so expiry, fade and retention are all
deterministic.

`web/` — `pnpm install && pnpm typecheck && pnpm build`. `web/build/` is
committed (FiveM serves it statically) including the vendored map tiles, so the
Vite config deliberately does not empty the output directory.
