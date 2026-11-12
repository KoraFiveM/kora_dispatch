---
title: "Installation"
sidebar_position: 2
---


# Installation

Kora Dispatch is a job-agnostic call lifecycle: any resource raises a call against a service (a kora_core job type), on-duty units for that service get a keyboard-driven alert feed plus an optional tablet with a rendered map, and dispatch itself knows nothing about police, medicine or towing. It also answers to the `kora_dispatch` export name.

## Install Kora Dispatch

1. **Add the folder** — Place the `kora_dispatch` folder in your resources directory. Keep the folder name unchanged: job resources call `exports.kora_dispatch:...`.

2. **Install its dependencies** — The manifest declares `dependency 'kora_theme'`, `dependency 'kora_lib'` and `dependency 'kora_core'`, and loads `@kora_lib/init.lua` then `@kora_core/init.lua` as shared scripts. kora_core supplies the job/duty indexes recipient resolution reads; kora_lib supplies keybinds, timers, sound, blips and the shared AppShell the tablet is built from.

3. **Start it before every job resource that raises calls** — Every resource that calls `exports.kora_dispatch:createCall` (or the other mutating exports) must start after kora_dispatch, because a job resource depends on dispatch, not the other way around.

   ```bash title="server.cfg"
   ensure kora_theme
   ensure kora_lib
   ensure kora_core
   ensure kora_dispatch
   # ...then kora_police, kora_ambulance, and any other resource that raises calls
   ```

4. **Add trusted callers to config.lua** — The free-form, call-mutating API (`createCall`, `updateCall`, `closeCall`) only works from server resources listed in `Config.trustedCallers`. Add a resource there only when it intentionally owns server-authoritative dispatch creation; by default it lists `kora_housing`, `kora_dispatch`, `kora_core`, `kora_police`, `kora_ambulance`, `kora_businesses` and `kora_robberies`.

## What the manifest sets up

- Server scripts load in a fixed, explicit order (never globbed, because alphabetic order would not respect it): `server/store.lua` (the call registry every other server file mutates) first, then `server/recipients.lua`, `server/api.lua`, `server/ingress.lua`, `server/units.lua`, `server/callbacks.lua`, `server/compat.lua` (wires legacy inbound events, so it must see the real API above it), then `server/dev.lua` last (so every function it drives already exists).
- Client scripts also load in a fixed order: `client/state.lua` (the local call cache every other client file reads) first, then `client/ui.lua`, `client/theme.lua`, `client/blip.lua`, `client/sync.lua` (wires inbound net events), `client/keybinds.lua`, `client/exports.lua`.
- `files { 'web/build/map/**/*' }` ships only the prebuilt map tile pyramid (`web/build/map/mainmap` and the vendored `web/build/map/atlas`), served statically to the AppShell's browser frame at `https://cfx-nui-kora_dispatch/web/build/...`. There is no `ui_page` and the `web/src` React source tree is not part of the manifest at all — it is dead source, not the UI this resource actually renders.
- The real tablet is a `kora_lib` AppShell app registered by `client/ui.lua` (`Kora.nui.registerApp`) and the overlay alert feed is pushed through `Kora.nui.setDispatchFeed`; both are driven entirely from `Dispatch.state`.

## Adding a new service

A non-emergency service is a config entry, not a code change.

```lua title="config.lua"
-- kora_core/shared/jobs.lua
{ name = 'tow', label = 'Recovery', type = 'recovery', grades = { ... } }

-- kora_dispatch/config.lua
Config.services.recovery = {
    label = 'Recovery',
    accent = '#F59E0B',
    sound = { name = 'Menu_Accept', set = 'Phone_SoundSet_Default' },
}
```

- Stock service types (job types) are `leo`, `ems`, `recovery`, `civ`. There is deliberately no `emergency` type: a scene needing both police and paramedics is two calls, one per service.

## Dependencies in detail

Declared with `dependency` in `fxmanifest.lua`:

| Resource | Used for |
| --- | --- |
| `kora_theme` | Declared dependency. The client also optionally reads `exports.kora_theme:getPlayerTheme()` (guarded by `GetResourceState`) and listens to `kora_theme:playerThemeChanged`. |
| `kora_lib` | Shared init, callbacks with rate limits, keybinds, timers, notifications, sound, blips, commands, permissions, and the AppShell/feed NUI (`Kora.nui`). |
| `kora_core` | Shared init, job/type data (`getShared`, `allShared`), on-duty indexes (`getPlayersByJobType`, `getPlayersByJob`, `getOnDutyRoster`), `getJob`, `getPlayerData`. |

Dispatch must start before every resource that raises calls, and after the three above.

## Further setup notes

- No SQL import is needed.
- Review [Configuration](./configuration.md). Set `Config.debug` to `false` on a production server.
- Make sure each job that should use dispatch has a `type` matching a key of `Config.services` (or add the type to `Config.access`).
- The tile images under `web/build/map/` are served to the NUI by the manifest `files` entry. `web/build/` is committed, so no build step is needed at resource start.

## Optional: rebuilding the web sources

`web/` contains a Vite/React project (see `web/package.json`) with `pnpm typecheck` and `pnpm build`. The current tablet and feed are rendered by `kora_lib`, and the manifest declares no `ui_page`, so the only part of `web/build/` the resource serves is the map tiles. See [Troubleshooting](./troubleshooting.md).

## Per-server overrides

`config.lua` ends by registering `Config` with `kora_lib` (`Kora.config.adopt`) and describing `Config.feed.position` as an enum. `config.local.lua` is git-ignored and is where generated per-server overrides are written by `kora_lib`.
