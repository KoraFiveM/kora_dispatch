---
title: "Server API"
sidebar_position: 2
---


# Server API

The authoritative call lifecycle: create, revise, close, read and respond to calls, plus the on-duty roster. Every export here is server-only — a call must be authoritative, and the recipient roster only exists on the server.

Namespace: `exports.kora_dispatch` · Source: `server/api.lua, server/store.lua, server/recipients.lua`

## How it works

Dispatch.api.toWire(call) is the shape every client-facing read and push uses: id, service, code, title, message, priority, coords, icon, createdAt, expiresAt, closedAt, closeReason, origin, data, sound, units (the units map flattened to an array sorted by attach time). onAccept is deliberately never included in the wire form — it is a server event name and a client has no business knowing it. Dispatch.store keeps calls bucketed per service plus a flat id index; a retention sweep (Config.history.sweepInterval) drops only closed/expired calls past Config.history.max or Config.history.ttl, and a live call is never evicted no matter how far over budget a service is.

## Terms used on this page

| Term | Meaning |
| --- | --- |
| Service | A kora_core job type (leo, ems, recovery, ...). A call targets exactly one. |
| Trusted caller | A server resource listed in Config.trustedCallers, checked against GetInvokingResource(). Required for createCall/updateCall/closeCall, not for the read exports or setUnitState. |
| Wire form | The subset of a call a client is allowed to see (Dispatch.api.toWire) — notably excludes onAccept. |

## Push mechanics

Every push is one TriggerClientEvent per on-duty recipient of the call's service/jobs (Dispatch.recipients.sources), never a -1 broadcast — a broadcast would leak every live call's coordinates and description to every connected player regardless of job.

## Detach on drop / off-duty

server/api.lua listens for kora_core:server:playerDropped and QBCore:Server:SetDuty(src, false) and detaches the unit from every call it was attached to, re-pushing each affected call so other units stop seeing a responder who is not coming.

## Functions

Seven exports: five around the call record itself, plus setUnitState (the response state machine) and getOnDutyUnits.

### `exports.kora_dispatch:createCall(payload)`

Raises a new call. Gated by Config.trustedCallers (see Security in How to use).

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `payload` | table | See "Raising a call: createCall" in How to use for the full field list (jobs/jobTypes, title/message, code, priority, coords, icon, duration, sound, data, onAccept). |

**Returns**

- **callId** — integer id, or false on failure.
- **recipientCount** — integer count of on-duty units reached, or the error string when callId is false.

**Example**

```lua
local id, reached = exports.kora_dispatch:createCall({ jobTypes = { 'leo' }, title = 'Robbery', message = '...', priority = 1, coords = coords })
if not id then return print('call refused:', reached) end
```

**Representative console output**

```text
Normalises the payload, resolves recipients, stores the call, pushes kora_dispatch:client:call to every recipient, and (with Config.debug on) logs a one-line summary to the console.
```

### `exports.kora_dispatch:updateCall(id, patch)`

Revises an open call in place. Gated by Config.trustedCallers.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `id` | integer | Call id returned by createCall. |
| `patch` | table | Any of code, title, message, priority, icon, sound, data, coords, duration. id/service/jobs cannot be patched. |

**Returns**

- **ok** — true on success, false on failure.
- **error** — string reason when ok is false.

**Example**

```lua
local ok, err = exports.kora_dispatch:updateCall(id, { message = 'Suspect vehicle is now a red Sultan.' })
```

**Representative console output**

```text
Pushes kora_dispatch:client:callUpdated to every current recipient after a successful patch. Raising priority (or passing duration) re-bases the expiry on the call's original createdAt.
```

### `exports.kora_dispatch:closeCall(id, reason?)`

Closes a call: it leaves the live feed immediately and stays in history with the reason attached. Gated by Config.trustedCallers.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `id` | integer | Call id. |
| `reason?` | string | Stored as closeReason; anything non-string is dropped (stored as nil). |

**Returns**

- **ok** — true (including when the call was already closed), false only for an unknown id or a trust failure.
- **error** — string reason when ok is false.

**Example**

```lua
exports.kora_dispatch:closeCall(id, 'suspect apprehended')
```

**Representative console output**

```text
Pushes kora_dispatch:client:callUpdated so every recipient's feed and map drop the call immediately.
```

### `exports.kora_dispatch:getCall(id)`

Reads the wire form of one call. Not gated by Config.trustedCallers — any server code may read a call by id.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `id` | integer | Call id. |

**Returns**

- **call** — the wire-shaped table (see toWire in behavior), or nil when the id is unknown.

**Example**

```lua
local call = exports.kora_dispatch:getCall(id)
```

**Representative console output**

```text
No push, no mutation; a pure read of the store.
```

### `exports.kora_dispatch:getCalls(filter?)`

Lists calls, newest first.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `filter?` | &#123; service?: string, job?: string, activeOnly?: boolean &#125; | service narrows to one service (otherwise every service); job further narrows to calls whose jobs list includes it; activeOnly drops closed/expired calls. |

**Returns**

- **calls** — array of wire-shaped call tables, newest first.

**Example**

```lua
local live = exports.kora_dispatch:getCalls({ service = 'leo', activeOnly = true })
```

**Representative console output**

```text
Used internally by the hydrate and getCalls callbacks, and by the dev commands.
```

### `exports.kora_dispatch:setUnitState(src, id, state?)`

Attaches, advances, or detaches a unit on a call. See "The unit response state machine" in How to use for the full rule set.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `src` | integer | Player server id of the unit. |
| `id` | integer | Call id. |
| `state?` | 'en_route' \| 'on_scene' \| 'clear' \| false \| nil | Omit to advance one step from the unit's current state; pass a state to jump to it; pass false to detach. |

**Returns**

- **state** — the unit's new state string on success, or false on failure.
- **error** — string reason, present only when state is false.

**Example**

```lua
local state, err = exports.kora_dispatch:setUnitState(source, callId)  -- advance one step
if state == false then print('refused:', err) end
```

**Representative console output**

```text
Not gated by Config.trustedCallers. Checks on-duty membership, service match, department match and (accept only) Config.dispatch.maxActiveCalls; fires the call's onAccept event on first attach; pushes kora_dispatch:client:callUpdated.
```

### `exports.kora_dispatch:getOnDutyUnits(filter?)`

Reads the on-duty roster straight from kora_core's maintained index.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `filter?` | &#123; service?: string, job?: string &#125; | service maps to kora_core jobType; job to an exact job name. |

**Returns**

- **units** — array of kora_core roster records.

**Example**

```lua
local onDuty = exports.kora_dispatch:getOnDutyUnits({ service = 'ems' })
```

**Representative console output**

```text
A thin pass-through to exports.kora_core:getOnDutyRoster.
```

## Limits and related APIs

Server only. createCall/updateCall/closeCall require the invoking resource to be in Config.trustedCallers; there is no per-call ownership check beyond that (a trusted resource may mutate any call by id).

## Related guides

- [Player-originated alerts](./ingress.md)
- [Client presentation exports](./client-presentation.md)

## Call payload fields

Reference for the `payload` of `createCall`.

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

At least one of `jobs` or `jobTypes` is required. Accepted aliases: `description` for `message`, `job` for `jobs`, `jobType` for `jobTypes`, `dispatchCode` for `code`. When `jobs` is used, only those jobs receive the call and only those jobs may attach to it. When only `jobTypes` is used, every job of that type is covered.

## Additional behaviour notes

- `createCall` returns `callId, recipientCount`; the recipient count is the number of on-duty players the call was pushed to, and `0` means nobody was on duty.
- `updateCall`: a closed call cannot be updated. Changing `priority` or `duration` re-bases the expiry on the call's creation time. An unknown priority or a non-positive duration is rejected before anything is changed.
- `getCalls` returns calls newest first within each service. Timestamps in the wire form use the server's `GetGameTimer()`.
- `setUnitState`: a first accept that would exceed `Config.dispatch.maxActiveCalls` fails with "you are already en route to a call" (or "... to N calls"). Only a first attach is capped. A state the walk does not know is rejected by the store.
- `onAccept`: see [How to use](../how-to-use.md) for when the hook fires.

## Which exports check the caller

Only `createCall`, `updateCall`, `closeCall` and `registerPlayerAlert` check `Config.trustedCallers`. `createPlayerCall` checks alert ownership. `getCall`, `getCalls`, `getOnDutyUnits` and `setUnitState` have no caller check, so any server resource can use them.
