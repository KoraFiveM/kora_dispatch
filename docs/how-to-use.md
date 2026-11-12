---
title: "How to use"
sidebar_position: 3
---


# How to use

Dispatch transports and presents calls; deciding that a gunshot is a police matter belongs to the resource that calls it in, not to dispatch. A call targets a service, reaches every on-duty unit of that service, shows up in a keyboard-driven overlay feed, and optionally in a tablet with a rendered map.

## Services, not jobs

A service is a kora_core job type (`type` in `kora_core/shared/jobs.lua`), not a job name. One service covers every job carrying that type, so a call to `leo` reaches police, sheriff and state troopers at once. A call that resolves to more than one service is refused outright, with an error naming the services found.

```text title="two calls, not one"
-- A call belongs to exactly one service. Needing both police and EMS is TWO calls:
exports.kora_dispatch:createCall({ jobTypes = { 'leo' }, code = '10-99', title = 'Officer Down', message = '...' })
exports.kora_dispatch:createCall({ jobTypes = { 'ems' }, code = '10-52', title = 'Officer Down', message = '...' })
```

## Raising a call: createCall

`exports.kora_dispatch:createCall(payload)` is the unrestricted, free-form API. It is gated: only server resources listed in `Config.trustedCallers` may call it (see Installation and Security below). Returns `callId, recipientCount` on success, or `false, error`.

```lua title="server/robbery.lua"
local id, reached = exports.kora_dispatch:createCall({
    jobTypes = { 'leo' },
    code     = '10-90',
    title    = 'Bank Robbery',
    message  = 'Silent alarm -- Fleeca, Legion Square.',
    priority = 1,
    coords   = coords,
    icon     = 'banknote',
    data     = { plate = 'ABC123', vehicle = 'Sultan' },
})

if reached == 0 then
    -- nobody on duty; tell the caller, or fall back to something else
end
```

- Required: a `title` or a `message` (title falls back to message), and `jobTypes` and/or `jobs` resolving to exactly one service.
- Aliases accepted for drop-in compatibility with ps-dispatch/qb-phone era payloads: `description` → `message`, `job` → `jobs`, `dispatchCode` → `code`.
- `priority` is `1` (critical, 10 min default lifetime), `2` (high, 5 min, the default priority) or `3` (routine, 2 min); an out-of-range value falls back to the default rather than erroring.
- `coords` without it means the call has no map marker. `icon` is a Lucide icon key. `duration` (ms) overrides the priority's own lifetime. `sound` overrides the service's alert tone. `data` is freeform and rendered in the tablet detail panel untouched.

## Raising a call from a player-observed event: registerPlayerAlert + createPlayerCall

Use this pair, not `createCall`, when a public client event is what observes the incident (for example "shots fired" detected client-side). The reporter supplies no wording, priority, service, coordinates or metadata — dispatch reuses the registered definition and reads the networked ped's position on the server.

```lua title="server/myresource.lua"
-- Register once, at resource start
exports.kora_dispatch:registerPlayerAlert('myresource:alarm', {
    jobTypes = { 'leo' }, title = 'Alarm', message = 'An alarm was activated.',
    priority = 2, cooldown = 30000,
})

-- Raise it from a public client-observed event
RegisterNetEvent('myresource:server:alarm', function()
    exports.kora_dispatch:createPlayerCall(source, 'myresource:alarm')
end)
```

- `registerPlayerAlert(key, definition)` is also gated by `Config.trustedCallers` (checked against `GetInvokingResource()`); `definition` takes the same fields as `createCall`, plus an optional `cooldown` (ms, default `Config.ingress.defaultCooldown` = 30000, floored at `Config.ingress.minimumCooldown` = 1000) and `requiredJobType` (only an on-duty member of that service may raise it).
- `createPlayerCall(src, key)` can only be called by the resource that registered `key` (checked against `GetInvokingResource()` again at call time) — a key is owned by whichever resource first registers it, re-registering under the same owner replaces the definition.
- A registered definition can never carry a server `onAccept` hook: it is stripped during normalisation, so a repeatedly-raised public alert can never repeatedly invoke arbitrary server behaviour.
- Per-player, per-type cooldowns and `Config.ingress.maxLiveCalls` (default 100 live calls across all services, counted before the new call is created) are enforced centrally; a throttled or over-capacity request returns `false, error[, remainingCooldownMs]`.

## Revising and closing a call: updateCall / closeCall

`exports.kora_dispatch:updateCall(id, patch)` revises an open call in place and re-pushes it to every recipient (for "the suspect vehicle is now a red Sultan", not for closing). `exports.kora_dispatch:closeCall(id, reason?)` closes it: the call leaves the live feed immediately and stays in history with the reason attached. Both return `ok, error`.

- Both are gated by the same `Config.trustedCallers` check as `createCall` (see Security below) — a resource not listed there cannot revise or close anyone's call, including its own.
- `id`, `service` and `jobs` are identity on a patch and cannot be changed; only `code`, `title`, `message`, `priority`, `icon`, `sound` and `data` are patchable (plus `coords` and `duration`, handled specially below). Patching a non-patchable key is silently ignored, not an error.
- Patching `priority` re-bases the expiry on the call's original `createdAt` (not on "now"), so escalating to critical gives the call a critical call's full lifetime while its elapsed-time display stays honest. `patch.duration` alone (without a `priority` change) re-bases the same way.
- Both fail with `'no such call'` for an unknown id; `updateCall` additionally fails with `'call is closed'` on an already-closed call. `closeCall` on an already-closed call is a no-op success (returns the call, not an error).

## Security: the caller-trust gate on createCall / updateCall / closeCall

All three call-mutating exports share one gate, `checkTrustedCaller(verb)` in `server/api.lua`: it reads `GetInvokingResource()` (falling back to `GetCurrentResourceName()` when dispatch calls itself), and refuses unless `Config.trustedCallers[origin] == true`, returning `false, "resource '<origin>' is not allowed to <verb> dispatch calls"`. This is a resource-identity check, not a per-call ownership check: a trusted resource may update or close any call by id, including one it did not create. Do not add a resource to `Config.trustedCallers` unless it is meant to hold that power.

- `setUnitState` (the respond/accept/clear path units actually use) is not gated by `Config.trustedCallers` at all — it is gated by on-duty membership, service match and department match on the calling player, since any on-duty unit of the right service is expected to call it. See the Functions reference for its checks.

## The onAccept hook

A call may name a server event to fire when a unit first attaches, so a job-specific queue can learn a call was claimed without dispatch knowing what a "house call" is.

```text title="server example"
exports.kora_dispatch:createCall({
    jobTypes = { 'ems' },
    title    = 'House Call',
    onAccept = 'kora_ambulance:server:housecallAccepted',
    data     = { requestId = 7 },
})

RegisterNetEvent('kora_ambulance:server:housecallAccepted', function(src, callId, data)
    if source ~= 0 and source ~= nil then return end -- server-raised only
    claim(src, data.requestId)
end)
```

- It fires on a unit's first attach, at whatever state it attaches (a jump straight to `on_scene` also fires it). Later advances (on scene, clear) and re-attaches while attached are progress reports and never re-fire it. Detaching and accepting again fires it again. Calls created through `createPlayerCall` never carry the hook. It is a local server event (`TriggerEvent(onAccept, src, callId, data)`).

## The unit response state machine

`exports.kora_dispatch:setUnitState(src, id, state?)` attaches, advances or detaches a unit. Omitting `state` advances one step along `nil → en_route → on_scene → clear`; passing a state jumps to it; passing `false` detaches. This is also what the respond keybind and the tablet's action buttons call.

- Refused with `'not on duty'`, `'wrong service for this call'` or `'this call was not sent to your department'` when the calling player is off duty, on a different service than the call, or in a job the call's `jobs` list does not include (service alone is not enough: a call raised against `jobs = { 'police' }` never reached the sheriff's department).
- A non-detach transition on a call that is closed or expired fails with `'call is no longer active'`. Detaching (`state = false`) always succeeds regardless of the call's liveness, since it is cleanup.
- Only the first accept (not yet attached, attaching) is capped by `Config.dispatch.maxActiveCalls` (default 1, counted per player across all live calls, `clear`/closed/expired do not count). Hitting the cap returns `false, 'you are already en route to a call'` (or a pluralised message for a higher cap). Set `maxActiveCalls = 0` to disable the cap. Advancing and detaching are never capped — a capped unit must still be able to clear the call holding it there.

## Recipient resolution

`server/recipients.lua` is the one place job names, job types and the single-service rule are enforced. `Dispatch.recipients.resolve(jobs, jobTypes)` turns a call's `jobs`/`jobTypes` lists into one resolved service plus the concrete job names it covers; a `jobType` with zero registered jobs of that type is refused (almost always a typo) rather than silently accepted as reaching nobody.

- `Dispatch.recipients.sources(service, jobs)` returns the on-duty sources to push to: an O(1) lookup by job type when the call covers the whole service, otherwise a per-job-name lookup merged and deduplicated.
- The push itself (`server/api.lua`'s local `push` function) sends one `TriggerClientEvent` per recipient rather than a `-1` broadcast with a client-side filter — a broadcast would hand every connected player the coordinates and description of every crime in progress.

## Access control

Only allowed jobs can use dispatch at all — the feed, the tablet, and every callback (`hydrate`, `getCalls`, `respond`, `setViewing`). The check runs on the server for every callback and response, so it cannot be bypassed by a modified client; the client applies the same rule only to decide whether to render anything.

```lua title="config.lua"
Config.access = {
    jobs = {},            -- extra job NAMES, e.g. { 'mechanic' }
    jobTypes = nil,       -- nil = every Config.services key (leo, ems, recovery); or { 'leo', 'ems' }
    requireOnDuty = true, -- false: off-duty members of an allowed job may open the tablet
}
```

- Adding an entry to `Config.services` opens dispatch to that job type. Calls and responses still only ever reach on-duty units, regardless of `requireOnDuty`.

## Player controls (all rebindable through FiveM key-binding settings)

- `Page Up` / `Page Down` (`Config.keybinds.previous` / `next`) — move the selection; scrolls past live calls into history.
- `Home` (`respond`) — accept, then en route → on scene → clear. With nothing selected, responds to the newest live call.
- `End` (`toggle`) — hide/show the overlay feed. With the tablet open it closes the tablet instead, since that is what holds NUI focus.
- `F9` (`tablet`) — open the tablet. An off-duty member of an allowed job gets a notification explaining why it did not open; anyone else pressing it (it is a common default bind) gets silence.
- The overlay feed never takes NUI focus and is pointer-transparent; only the tablet takes focus, and it is optional.

## The map and blips

The complete call set only ever lives on the tablet's rendered map (served from the vendored `web/build/map` tile pyramid), where marker count costs the game engine nothing. The native GTA map receives only the `Config.map.maxCallBlips` (default 4) most urgent live calls, grouped under kora_lib's `Dispatch` blip category, plus the single GPS route blip for the call the player personally accepted.

- Native-map call blips never carry a route — only `exports.kora_dispatch`-triggered accept (via `client/blip.lua`'s `route`) creates the one routed blip, and it is cleared automatically when the call closes or the unit's own state reaches `clear`.
- A local 5-second client timer (`client/blip.lua`) re-synchronises the bounded native-map blips, since an otherwise-quiet call's expiry is clock-based and has no server push to remove its marker.
- A marker holds full opacity for `Config.map.fadeHoldFraction` (default 60%) of the call's remaining life, then eases out — fading from the first second would read as a broken UI.
- Recalibrating the map for a different tile set is documented in `docs/map.md`; the in-game `/dispatchcoords` client command (always registered, no permission gate, reads and changes nothing) prints world position next to the pixel the current calibration projects it to.

## Colleague positions on the tablet

The tablet shows on-duty colleagues with a vehicle-type icon and callsign. Positions are read server-side (`GetEntityCoords` on the networked ped under OneSync), so no client runs a loop or sends its own position. The heartbeat (`Config.units.heartbeat`, default 3000 ms) only runs for services that currently have at least one viewer with the tablet open — an idle server does zero work here.

## Legacy compatibility

`exports.kora_core:alert` keeps working: kora_core fires a server-side `kora_core:server:dispatchAlert` once per alert, and `server/compat.lua` mirrors it into a real call when `Config.compat.coreAlerts` is on (default `true`).

- `Config.compat.legacyInbound` (default `false`) additionally claims `police:server:policeAlert`, `hospital:server:ambulanceAlert` and `hospital:server:SendDoctorAlert` as fixed, throttled, server-side-coordinate incidents. It ships off because kora_ambulance's own compat and kora_core's own re-fire of `police:server:policeAlert` already handle those names on a typical server — enabling both would double the calls.
- The compat events ignore whatever payload the client sent; coordinates always come from the reporting player's own networked ped.

## Presentation client exports

A job resource can call these from its own client code to brand or control dispatch for the local player; none of them creates, reads or mutates a call on the server. See the Client presentation module for exact signatures.
