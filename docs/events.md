---
title: Events and callbacks
sidebar_position: 7
---

# Events and callbacks

## Net events sent by the server

Sent with one `TriggerClientEvent` per recipient. They are consumed by this resource's client and are not an API.

| Event | Payload | Purpose |
| --- | --- | --- |
| `kora_dispatch:client:call` | call, server time | A new call (or an unseen one). Shows a toast if `Config.alerts.notify`, plays the tone unless the feed is hidden. |
| `kora_dispatch:client:callUpdated` | call, server time | A call changed: update, close, unit attach, advance or detach. |
| `kora_dispatch:client:units` | list of unit snapshots | Colleague positions for tablet viewers. |

A unit snapshot carries `src`, `name`, `callsign`, `job`, `jobLabel`, `grade`, `coords`, `heading`, `vehicle`, `plate`, `speed` (mph).

## kora_lib callbacks (client to server)

Registered with `Kora.callback.register`, each rate limited and each checked against `Config.access` on the server.

| Callback | Arguments | Returns | Rate limit |
| --- | --- | --- | --- |
| `kora_dispatch:hydrate` | none | Service, unit, server time, config (label, accent, sound, priorities, feed, map) and the player's calls, or `nil` when not allowed. | 5 per 5 s |
| `kora_dispatch:respond` | call id, optional state | New state or `false, error`. Requires an on-duty unit. | 20 per 5 s |
| `kora_dispatch:setViewing` | boolean | `true`, or `false` when not allowed. Starts or stops the position heartbeat for the player and runs one broadcast when opening. | 30 per 10 s |
| `kora_dispatch:getCalls` | optional filter table | The player's service and department calls including history; empty when not allowed. | 10 per 5 s |

The server always overrides the filter's service and job with the caller's own.

## Events consumed

| Event | Side | Behaviour |
| --- | --- | --- |
| `kora_core:server:playerDropped` | server | Detaches the player from all calls, clears viewer and cooldown state. |
| `playerDropped` | server | Clears viewer and cooldown state. |
| `QBCore:Server:SetDuty` | server | Going off duty detaches the player from all calls. |
| `QBCore:Server:OnJobUpdate` | server | Detaches the player from calls their new job was not sent to. |
| `kora_core:server:dispatchAlert` | server | Mirrors a `kora_core` alert into a call when `Config.compat.coreAlerts` is on. |
| `police:server:policeAlert`, `hospital:server:ambulanceAlert`, `hospital:server:SendDoctorAlert` | server | Registered as net events only when `Config.compat.legacyInbound` is on. |
| `QBCore:Client:OnPlayerLoaded`, `OnJobUpdate`, `SetDuty` | client | Re-hydrates. |
| `QBCore:Client:OnPlayerUnload` | client | Clears state and closes the tablet. |
| `onClientResourceStart` | client | Re-renders when `kora_lib` starts; hydrates one second after this resource starts. |
| `kora_theme:playerThemeChanged` | client | Refreshes the feed colours when no accent is pinned. |

## Events fired

The only event dispatch fires on behalf of a call is the call's `onAccept` event, see [API reference](./api/index.md).
