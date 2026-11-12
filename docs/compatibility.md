---
title: Compatibility
sidebar_position: 10
---

# Compatibility

## kora_core alerts (on by default)

With `Config.compat.coreAlerts` on, dispatch listens to the server event `kora_core:server:dispatchAlert` that `kora_core` fires for `exports.kora_core:alert`. The payload is passed to `createCall` as origin `kora_dispatch` (a trusted caller), so it needs the same fields as a normal call payload, including the aliases `description`, `job` and `dispatchCode`. A non-table payload is ignored; a payload that fails validation is silently dropped.

## Legacy qb inbound events (off by default)

With `Config.compat.legacyInbound` on, dispatch registers these net events:

| Event | Raises |
| --- | --- |
| `police:server:policeAlert` | Priority 1 `10-13` Officer Alert to `leo`. The reporter must be an on-duty `leo` unit. |
| `hospital:server:ambulanceAlert` | Priority 1 `10-52` Medical Emergency to `ems`. |
| `hospital:server:SendDoctorAlert` | Priority 3 `10-51` Doctor Requested to `ems`. |

The client payload is ignored. Each event raises a fixed, registered alert through the ingress path (cooldown, live-call ceiling, server-read position), so these never carry client-supplied wording or coordinates.

Leave this off if another resource already handles these event names (for example a job resource), or enabling both would produce two calls per alert.

## Payload aliases

`createCall` accepts `description`, `job`, `jobType`, `dispatchCode` so ps-dispatch or qb-phone style payloads work after changing the export name.

## QBCore style events

Dispatch follows duty and job changes through `QBCore:Server:SetDuty`, `QBCore:Server:OnJobUpdate` and the client events `QBCore:Client:OnPlayerLoaded`, `OnJobUpdate`, `SetDuty`, `OnPlayerUnload`. These must be fired by `kora_core` or the compatibility layer.

## Other resources

- `kora_theme` is optional at runtime for colours (see [Installation](./installation.md)).
- Resources named in `Config.trustedCallers` are expected to call `createCall` and friends; this repository does not verify that those resources exist.
