---
title: Installation
sidebar_position: 2
---

# Installation

## Dependencies

Declared with `dependency` in `fxmanifest.lua`:

| Resource | Used for |
| --- | --- |
| `kora_theme` | Declared dependency. The client also optionally reads `exports.kora_theme:getPlayerTheme()` (guarded by `GetResourceState`) and listens to `kora_theme:playerThemeChanged`. |
| `kora_lib` | Shared init, callbacks with rate limits, keybinds, timers, notifications, sound, blips, commands, permissions, and the AppShell/feed NUI (`Kora.nui`). |
| `kora_core` | Shared init, job/type data (`getShared`, `allShared`), on-duty indexes (`getPlayersByJobType`, `getPlayersByJob`, `getOnDutyRoster`), `getJob`, `getPlayerData`. |

Dispatch must start before every resource that raises calls, and after the three above.

## Steps

1. Place `kora_dispatch` in your resources folder.
2. Ensure it after its dependencies and before job resources in `server.cfg`:

   ```cfg
   ensure kora_theme
   ensure kora_lib
   ensure kora_core
   ensure kora_dispatch
   ```

3. No SQL import is needed.
4. Review [Configuration](./configuration.md). In particular add every resource that should call `createCall` to `Config.trustedCallers`, and set `Config.debug` to `false` on a production server.
5. Make sure each job that should use dispatch has a `type` matching a key of `Config.services` (or add the type to `Config.access`).

The tile images under `web/build/map/` are served to the NUI by the manifest `files` entry. `web/build/` is committed, so no build step is needed at resource start.

## Optional: rebuilding the web sources

`web/` contains a Vite/React project (see `web/package.json`) with `pnpm typecheck` and `pnpm build`. The current tablet and feed are rendered by `kora_lib`, and the manifest declares no `ui_page`, so the only part of `web/build/` the resource serves is the map tiles. See [Troubleshooting](./troubleshooting.md).

## Per-server overrides

`config.lua` ends by registering `Config` with `kora_lib` (`Kora.config.adopt`) and describing `Config.feed.position` as an enum. `config.local.lua` is git-ignored and is where generated per-server overrides are written by `kora_lib`.
