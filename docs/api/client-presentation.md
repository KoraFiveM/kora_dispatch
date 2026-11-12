---
title: "Client presentation exports"
sidebar_position: 4
---


# Client presentation exports

Presentation only, because presentation is per-player: an officer and a paramedic on the same server see different accents at the same moment. Nothing here creates, reads or mutates a call on the server — all five exports only affect what this one client renders.

Namespace: `exports.kora_dispatch` · Source: `client/exports.lua, client/theme.lua, client/blip.lua, client/state.lua`

## How it works

kora_lib applies the accent override inside the shared AppShell's own browser frame and restores the configured kora_theme palette when the tablet closes. A nil accent means "follow kora_theme" rather than a fixed colour.

## Functions

Five client-only exports.

### `exports.kora_dispatch:setTheme(hex?)`

Sets this player's dispatch accent colour.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `hex?` | string | `#RRGGBB`. Omit/nil to restore the service default (which itself falls back to the kora_theme player/server colour when the service has no configured accent). |

**Returns**

- **ok** — true on success, false on an invalid (non-hex) value.
- **error** — string reason when ok is false.

**Example**

```lua
exports.kora_dispatch:setTheme('#3B82F6')
```

**Representative console output**

```text
Re-renders the feed/tablet immediately with the new accent tokens.
```

### `exports.kora_dispatch:setUiOptions(options)`

Overrides feed placement and density for this player.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `options` | &#123; position?: string, maxVisible?: integer, hidden?: boolean &#125; | position overrides Config.feed.position; maxVisible overrides Config.feed.maxVisible; hidden toggles the feed exactly like the toggle keybind. |

**Returns**

- **ok** — true when options was a table (even if no recognised field was set), false otherwise.

**Example**

```lua
exports.kora_dispatch:setUiOptions({ position = 'top-left', maxVisible = 6 })
```

**Representative console output**

```text
Mutates the local client state table directly and re-renders.
```

### `exports.kora_dispatch:setTablet(open)`

Opens or closes the tablet programmatically — for binding it to an in-world computer or an item instead of the F9 key.

**Parameters**

| Name | Type | Description |
| --- | --- | --- |
| `open` | boolean | true to open, false to close. |

**Returns**

- **No return value.**

**Example**

```lua
exports.kora_dispatch:setTablet(true)
```

**Representative console output**

```text
Equivalent to the tablet keybind, including the NUI-focus and tablet-viewer wiring; a no-op if the player is not on an active dispatch service.
```

### `exports.kora_dispatch:getService()`

This player's current service.

**Parameters**



**Returns**

- **service** — string job type (e.g. 'leo'), or nil when off duty / not on a dispatch job.

**Example**

```lua
local service = exports.kora_dispatch:getService()
```

**Representative console output**

```text
Read-only; mirrors the local state set by the last hydrate.
```

### `exports.kora_dispatch:getRoutedCall()`

The call this player currently has a GPS route to.

**Parameters**



**Returns**

- **callId** — integer, or nil when no route is active.

**Example**

```lua
local routedId = exports.kora_dispatch:getRoutedCall()
```

**Representative console output**

```text
Reflects client/blip.lua's single active route blip.
```

## Limits and related APIs

Client only. These never reach the server and have no bearing on what other players see or on access control.

## Related guides

- [Server API](./server-api.md)

## Additional behaviour notes

- `setUiOptions` does not validate `position`; it returns `true` for any table and `false` otherwise.
- `setTablet` does nothing for a player with no active service.
