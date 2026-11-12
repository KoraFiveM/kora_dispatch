---
title: Exports
sidebar_position: 4
---

# Exports

Everything that creates or changes a call is a **server** export. The only client exports are presentation helpers.

## Server exports

### createCall

`exports.kora_dispatch:createCall(payload)` returns `callId, recipientCount` or `false, error`.

Restricted to resources in `Config.trustedCallers`. The recipient count is the number of on-duty players the call was pushed to; `0` means nobody was on duty.

| Field | Type | Notes |
| --- | --- | --- |
| `jobTypes` | string or array of strings | Service(s). Must resolve to exactly one service. A type with no registered job is refused. |
| `jobs` | string or array of strings | Specific job names. An unknown job is refused. |
| `title` | string | Falls back to `message`. |
| `message` | string | Description. At least one of `title` or `message` is required. |
| `code` | string | Short radio code shown as a badge. |
| `priority` | number | 1 critical, 2 high, 3 routine. Anything else falls back to `Config.defaultPriority`. |
| `coords` | vector3 or table with x, y, z | Without coordinates the call has no map marker or blip. |
| `icon` | string | Icon key. |
| `duration` | number | Lifetime in ms, overriding the priority `ttl`. Must be positive. |
| `sound` | table | Overrides the service tone: `name` and `set`. |
| `data` | table | Free-form, sent to clients. The key `street` is shown as the call location. |
| `onAccept` | string | Server event fired when a unit first attaches. |

At least one of `jobs` or `jobTypes` is required. Accepted aliases: `description` for `message`, `job` for `jobs`, `jobType` for `jobTypes`, `dispatchCode` for `code`.

When `jobs` is used, only those jobs receive the call and only those jobs may attach to it. When only `jobTypes` is used, every job of that type is covered.

```lua
local id, reached = exports.kora_dispatch:createCall({
    jobTypes = { 'leo' },
    code = '10-90',
    title = 'Bank Robbery',
    message = 'Silent alarm at the bank.',
    priority = 1,
    coords = coords,
    icon = 'banknote',
    data = { street = 'Legion Square', plate = 'ABC123' },
})
if not id then print('refused: ' .. tostring(reached)) end
```

### updateCall

`exports.kora_dispatch:updateCall(id, patch)` returns `ok, error`. Trusted callers only.

Revises an open call and re-pushes it to recipients. Patchable fields: `code`, `title`, `message`, `priority`, `icon`, `sound`, `data`, `coords`, and `duration`. `id`, service, jobs, origin and creation time cannot change. A closed call cannot be updated. Changing `priority` or `duration` re-bases the expiry on the call's creation time. An unknown priority or a non-positive duration is rejected before anything is changed.

### closeCall

`exports.kora_dispatch:closeCall(id, reason)` returns `ok, error`. Trusted callers only. The call leaves the live feed, stays in history and carries `reason` (string) as `closeReason`. Closing an already closed call succeeds.

### getCall and getCalls

`exports.kora_dispatch:getCall(id)` returns the wire form of a call or `nil`.

`exports.kora_dispatch:getCalls(filter)` returns wire-form calls, newest first within each service. `filter` accepts `service`, `job` and `activeOnly`.

The wire form contains `id`, `service`, `code`, `title`, `message`, `priority`, `coords`, `icon`, `createdAt`, `expiresAt`, `closedAt`, `closeReason`, `origin`, `data`, `sound` and `units` (sorted by attach time). The `onAccept` event name is never included. Timestamps use the server's `GetGameTimer()`.

### setUnitState

`exports.kora_dispatch:setUnitState(src, id, state)` returns the new state or `false, error`.

- `state` omitted: advance one step (`nil`, `en_route`, `on_scene`, `clear`).
- `state` a string (`en_route`, `on_scene`, `clear`): jump to it.
- `state` `false`: detach.

Refused when: the call does not exist or is no longer active (except when detaching), the player is not on duty, their job is not allowed by `Config.access`, their job type differs from the call's service, their job was not among the call's `jobs`, or the first accept would exceed `Config.dispatch.maxActiveCalls` (errors "you are already en route to a call" or "... to N calls"). Only a first attach is capped. A state the walk does not know is rejected by the store.

### getOnDutyUnits

`exports.kora_dispatch:getOnDutyUnits(filter)` returns `kora_core`'s on-duty roster. `filter` accepts `service` (job type) and `job`.

### registerPlayerAlert

`exports.kora_dispatch:registerPlayerAlert(key, definition)` returns `ok, error`. Trusted callers only.

Registers a fixed alert owned by the calling resource. `key` is 1 to 64 characters (letters, digits, `.`, `-`, `_`, `:`), starting with a letter or digit. `definition` takes the same targeting and presentation fields as `createCall` (`onAccept` is discarded), plus:

- `cooldown` - ms per player and key, default `Config.ingress.defaultCooldown`, minimum `Config.ingress.minimumCooldown`.
- `requiredJobType` - only an on-duty unit of that job type may raise it.

`data` is reduced to string, number and boolean values; `sound` to `name` and `set`. Re-registering your own key replaces it. A key owned by another resource is refused. Registrations are removed when the owning resource stops.

### createPlayerCall

`exports.kora_dispatch:createPlayerCall(src, key)` returns `callId, recipientCount` or `false, error` (and the remaining cooldown in ms when cooling down).

Raises a registered alert for player `src`. The key must be owned by the calling resource. Dispatch reads the reporter's ped position server-side, enforces the per-player cooldown and `Config.ingress.maxLiveCalls`, and adds `incident` (the key) and `reporter` (the source) to `data`. The request window is consumed before the live-call check, so a refused request at capacity still starts the cooldown.

Use this pair when a public client event observes an incident. Use `createCall` only for incidents established by trusted server code.

```lua
exports.kora_dispatch:registerPlayerAlert('myresource:alarm', {
    jobTypes = { 'leo' }, title = 'Alarm', message = 'An alarm was activated.',
    priority = 2, cooldown = 30000,
})

RegisterNetEvent('myresource:server:alarm', function()
    exports.kora_dispatch:createPlayerCall(source, 'myresource:alarm')
end)
```

## The onAccept hook

If a call has `onAccept`, dispatch fires `TriggerEvent(onAccept, src, callId, data)` (a local server event) the first time a unit attaches, at whatever state it attaches. Later advances and re-attaches while attached do not fire it again. Detaching and accepting again fires it again. Calls created through `createPlayerCall` never carry the hook.

```lua
AddEventHandler('myresource:server:accepted', function(src, callId, data)
    -- first unit attached
end)
```

## Client exports

| Export | Purpose |
| --- | --- |
| `setTheme(hex)` | This player's accent, `#RRGGBB`. Returns `ok, error`. `nil` restores the service default. |
| `setUiOptions(options)` | Table with `position` (string), `maxVisible` (number), `hidden` (boolean) for the feed. Returns `true`, or `false` when not given a table. `position` is not validated. |
| `setTablet(open)` | Open or close the tablet. Does nothing for a player with no active service. |
| `getService()` | The player's service, or `nil`. |
| `getRoutedCall()` | Id of the call the player has a GPS route to, or `nil`. |

## Permissions on exports

Only `createCall`, `updateCall`, `closeCall` and `registerPlayerAlert` check `Config.trustedCallers`. `createPlayerCall` checks alert ownership. `getCall`, `getCalls`, `getOnDutyUnits` and `setUnitState` have no caller check, so any server resource can use them.
