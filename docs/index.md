---
title: kora_dispatch
sidebar_position: 1
---

# kora_dispatch

`kora_dispatch` is a job-agnostic dispatch system for Kora servers: a server-authoritative call lifecycle, a keyboard-driven alert feed, a tablet (a `kora_lib` AppShell app) with a rendered map, and a small capped set of native map blips. It does not know what a robbery or a house call is. Other resources raise calls through the server exports and dispatch delivers them to on-duty members of one service.

Current version: see `version` in `fxmanifest.lua`.

## Concepts

- **Service** - a `kora_core` job **type** (`type` in the job definition), not a job name. One service covers every job with that type. Services configured out of the box: `leo`, `ems`, `recovery`.
- **One service per call** - a call belongs to exactly one service. A scene that needs police and paramedics is two calls. A call that resolves to more than one service is refused with an error.
- **Recipients** - only on-duty players whose job is covered by the call receive it. Calls are pushed per player, never broadcast.
- **Live vs history** - a call is live until it is closed or its lifetime (set per priority) ends. Closed and expired calls stay readable in history for a while, see [Configuration](./configuration.md).
- **Server authority** - clients never create, change or expire a call. They can only ask the server for their own service's calls and change their own unit state.

## Features

- Call lifecycle: create, update, close, expire, retention. See [API reference](./api/index.md).
- Unit response states `en_route`, `on_scene`, `clear`, a per-player cap on concurrent accepted calls, and a one-shot `onAccept` server event hook.
- Player-originated alert ingress (`registerPlayerAlert` and `createPlayerCall`) with server-side cooldowns, a live-call ceiling and server-read coordinates.
- Alert feed overlay and tablet UI with live map, queue, history, call detail and on-duty units. See [User interface](./ui.md).
- Native map blips for the most urgent live calls plus one GPS route to the call you accepted.
- Colleague positions on the tablet map, read server-side and only while somebody has the tablet open.
- Per-player accent theme exports for job resources.
- Legacy compatibility mirror for `kora_core` alerts and optional legacy qb events. See [Compatibility](./compatibility.md).
- Admin development commands when `Config.debug` is on. See [Commands](./commands.md).

## Documentation map

- [Installation](./installation.md) - dependencies, load order, server.cfg, manifest setup, adding a service
- [How to use](./how-to-use.md) - services, raising/revising calls, unit states, access, controls, map, compatibility
- [Commands](./commands.md) - dev commands and `/dispatchcoords`, permissions
- [API reference](./api/index.md) - module overview
  - [Server API](./api/server-api.md) - call lifecycle exports, payload fields, on-duty roster
  - [Player-originated alerts](./api/ingress.md) - `registerPlayerAlert` and `createPlayerCall`
  - [Client presentation exports](./api/client-presentation.md) - theme, feed options, tablet, service, route
- [Configuration](./configuration.md) - every `Config` option
- [Events and callbacks](./events.md) - net events, local events consumed, kora_lib callbacks
- [User interface](./ui.md) - feed, keybinds, tablet, theming
- [The rendered map](./map.md) - tiles, projection, recalibration, blips, fade
- [Compatibility](./compatibility.md) - legacy alert paths and integrations
- [Testing](./testing.md) - offline smoke tests and an in-game checklist
- [Troubleshooting](./troubleshooting.md) - common problems and known caveats

## Not used by this resource

- **Database**: no SQL tables or columns are read or written. All calls live in server memory and are lost on resource restart.
- **Items**: no items are registered or used.
- **Locales**: user-facing strings are hard-coded English; there is no locale file.
