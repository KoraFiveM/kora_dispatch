---
title: "Player-originated alerts"
sidebar_position: 3
---


# Player-originated alerts

The safe bridge for incidents first observed by a client (for example a client-detected gunshot): a gameplay resource registers a fixed alert definition once, then raises it by key for a specific player. The player supplies no wording, priority, coordinates or metadata.

Namespace: `exports.kora_dispatch` · Source: `server/ingress.lua`

## How it works

registerPlayerAlert and createPlayerCall both re-check GetInvokingResource() against the key's owner, so an export call cannot be redirected to act as a different resource; the owner cannot be forged through the export boundary because the internal register() third argument (used only by server/compat.lua's own registrations) is not exposed by the public export.

## Functions

Two exports: register the fixed definition, then raise it by key for a given source.

### `exports.kora_dispatch:registerPlayerAlert(key, definition)`

Registers a fixed, named alert type owned by the calling resource. Gated by Config.trustedCallers.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `key` | string | 1-64 chars, letters/numbers/dots/dashes/underscores/colons (pattern '^[%w][%w:._%-]*$'). |
| `definition` | table | Same fields as createCall's payload, plus cooldown? (ms, default Config.ingress.defaultCooldown, floored at Config.ingress.minimumCooldown) and requiredJobType? (string job type). |

**Returns**

- **ok** — true on success, false otherwise.
- **error** — string reason when ok is false (bad key, untrusted caller, owned by another resource, registry full at Config.ingress.maxRegisteredTypes, or a normalisation failure).

**Example**

```lua
exports.kora_dispatch:registerPlayerAlert('myresource:alarm', { jobTypes = { 'leo' }, title = 'Alarm', message = 'An alarm was activated.', priority = 2, cooldown = 30000 })
```

**Representative console output**

```text
Strips any onAccept from the definition, deep-copies jobs/jobTypes/data/sound so later mutation of the caller's table cannot rewrite live policy, and auto-removes the registration when the owning resource stops (Kora.resources.serverRegistry).
```

### `exports.kora_dispatch:createPlayerCall(src, key)`

Raises a previously registered alert for src, reading the reporter's position server-side. Callable only by the resource that owns key.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `src` | integer | Player server id of the reporter. |
| `key` | string | A key already registered (by the SAME invoking resource) via registerPlayerAlert. |

**Returns**

- **callId** — integer id on success, false on failure.
- **errorOrRecipientCount** — error string on failure, recipient count on success.
- **remainingCooldownMs** — present only on a cooldown refusal.

**Example**

```lua
local id, result = exports.kora_dispatch:createPlayerCall(source, 'myresource:alarm')
if not id then return print('alert refused:', result) end
```

**Representative console output**

```text
Enforces per-player/per-type cooldown, requiredJobType (if set), and Config.ingress.maxLiveCalls (global live-call ceiling across all services) before delegating to Dispatch.api.createCall.
```

## Limits and related APIs

Server only. Use createCall directly (not this pair) for incidents fully established by trusted server code; use this pair only for incidents a public client event merely reports.

## Related guides

- [Server API](./server-api.md)

## Additional behaviour notes

- `key` must start with a letter or digit.
- `data` is reduced to string, number and boolean values; `sound` to `name` and `set`. Re-registering your own key replaces it. A key owned by another resource is refused. Registrations are removed when the owning resource stops.
- `requiredJobType` means only an on-duty unit of that job type may raise the alert.
- `createPlayerCall` adds `incident` (the key) and `reporter` (the source) to `data`. The request window is consumed before the live-call check, so a request refused at capacity still starts the cooldown.
- `onAccept` is discarded from definitions, so calls created through `createPlayerCall` never carry the hook.
