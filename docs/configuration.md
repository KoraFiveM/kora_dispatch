---
title: Configuration
sidebar_position: 6
---

# Configuration

All options live in `config.lua` (shared between client and server). Values below are the shipped defaults.

## Services

`Config.services` maps a job **type** to presentation:

| Field | Meaning |
| --- | --- |
| `label` | Name shown as the tablet title. |
| `accent` | Default accent colour `#RRGGBB`. A client can override it with `setTheme`. `nil` follows `kora_theme`. |
| `sound` | Alert tone `{ name, set }` played on a new call. |

Defaults: `leo` (Police, blue), `ems` (EMS, red), `recovery` (Recovery, amber). `Config.defaultService` (label `Dispatch`, no accent) is the fallback for a service with no entry.

Adding a key to `Config.services` also opens dispatch to that job type unless `Config.access.jobTypes` is set.

## Priorities

`Config.priorities` defines `label`, `ttl` (ms the call stays live) and `color` per priority.

| Priority | Label | Default `ttl` |
| --- | --- | --- |
| 1 | Critical | 600000 (10 min) |
| 2 | High | 300000 (5 min) |
| 3 | Routine | 120000 (2 min) |

`Config.defaultPriority` is `2`. An unknown priority in a payload falls back to the default instead of erroring.

## History

`Config.history`:

| Option | Default | Meaning |
| --- | --- | --- |
| `max` | 50 | Calls retained per service. Only closed or expired calls are dropped; a live call is never evicted. The client cache uses the same limit. |
| `ttl` | 3600000 | Milliseconds a closed or expired call stays in history. |
| `sweepInterval` | 60000 | Milliseconds between retention sweeps. |

## Units and response

| Option | Default | Meaning |
| --- | --- | --- |
| `Config.units.heartbeat` | 3000 | Milliseconds between position broadcasts to tablet viewers. |
| `Config.units.maxDistance` | 0 | Metres. 0 shares the whole map. Above 0 each viewer only gets units within range (the viewer always sees themselves). |
| `Config.dispatch.maxActiveCalls` | 1 | Live calls one player may be attached to (not yet `clear`). Only a first accept is capped. 0 disables the cap. |

## Player-alert ingress

`Config.ingress`, used by `registerPlayerAlert` and `createPlayerCall`:

| Option | Default | Meaning |
| --- | --- | --- |
| `defaultCooldown` | 30000 | Milliseconds per player and alert type when a registration gives none. |
| `minimumCooldown` | 1000 | A registration with a lower cooldown is rejected. |
| `maxLiveCalls` | 100 | Live calls across all services above which `createPlayerCall` is refused. Trusted `createCall` is not subject to it. |
| `maxRegisteredTypes` | 128 | Maximum number of registered alert keys. |

## Trusted callers

`Config.trustedCallers` is a table of resource name to `true`. Resources not listed cannot call `createCall`, `updateCall`, `closeCall` or `registerPlayerAlert`. Default: `kora_housing`, `kora_dispatch`, `kora_core`, `kora_police`, `kora_ambulance`, `kora_businesses`, `kora_robberies`.

If the convar `fft_kora_hooks` is `true` at load time, resource `fft` is added (functional-test seam, development only).

## Feed

`Config.feed`:

| Option | Default | Meaning |
| --- | --- | --- |
| `maxVisible` | 4 | Live cards shown in the overlay feed. |
| `position` | `left-center` | `left-center`, `top-left` or `top-center`. Registered with `kora_lib` as an enum. |
| `pageSize` | 8 | Intended tablet page size. **Not read by the current tablet**; see [Troubleshooting](./troubleshooting.md). |

## Keybinds

`Config.keybinds` sets the default keys: `previous` `PRIOR`, `next` `NEXT`, `respond` `HOME`, `toggle` `END`, `tablet` `F9`. Players can rebind them in FiveM key bindings. See [User interface](./ui.md).

## Map

`Config.map` is described in [The rendered map](./map.md): `showCallBlips`, `maxCallBlips`, `callBlipSprite`, `callBlipScale`, `tilePath`, `tileExtension`, `minZoom`, `maxZoom`, `tileSize`, `grid`, `calibration`, `fadeHoldFraction`, `captureWheel`.

## Alerts

`Config.alerts`: `notify` (default `true`) shows a toast for each newly received call, with `duration` (default 7000 ms). Calls restored by login or duty hydration do not toast.

## Compatibility

`Config.compat`: `legacyInbound` (default `false`) and `coreAlerts` (default `true`). See [Compatibility](./compatibility.md).

## Access

`Config.access` decides who may use dispatch at all:

| Option | Default | Meaning |
| --- | --- | --- |
| `jobs` | empty | Extra job names allowed. |
| `jobTypes` | `nil` | `nil` allows every key of `Config.services`. A list narrows it, for example `leo` and `ems` only. |
| `requireOnDuty` | `true` | If `false`, an off-duty member of an allowed job may open the tablet and read data. Calls are still only delivered to on-duty units and only on-duty units can respond. |

The check runs on the server for every callback.

## Debug

`Config.debug` (default `true` in `config.lua`) registers the development commands in [Commands](./commands.md) and prints a console line for every created call. Set it to `false` in production.
