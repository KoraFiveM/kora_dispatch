---
title: Commands
sidebar_position: 6
---

# Commands

## Development commands (server)

Registered only while `Config.debug` is `true` (the shipped default). Each requires the `admin` level. The check uses `Kora.permissions.hasLevel` with prefix `kora_core` and the ranked levels `god`, `admin`, `mod`, `user`, so `kora_core.admin` or `group.admin` (and higher levels) pass.

| Command | Arguments | Behaviour |
| --- | --- | --- |
| `/dispatchtest` | `priority` (1 to 3, default 2), `service` | Raises a sample call at your position via `createCall`: priority 1 Bank Robbery `10-90`, 2 Shots Fired `10-31`, 3 Vehicle Theft `10-16`. The service defaults to your job type; with a type of `none` or `civ` or no job you must pass one. Tells you how many units it reached, and warns when it reached none (for example when you are off duty). |
| `/dispatchclear` | none | Closes every live call of your job type with reason "cleared by an admin". |
| `/dispatchstatus` | none | Prints viewer count and per-service live, history and on-duty counts to the server console. |

`/dispatchtest` and `/dispatchclear` run as a trusted caller because they run inside this resource.

## Client command

| Command | Behaviour |
| --- | --- |
| `/dispatchcoords` | Prints your world position and the map pixel the current `Config.map.calibration` projects it to, to the client console. Always registered, no permission restriction; changes nothing. Used for [recalibration](./map.md). |

## Permissions summary

- Dev commands: admin level as above.
- Using dispatch: `Config.access` (job based), checked server-side. See [Configuration](./configuration.md).
- Calling creation exports: `Config.trustedCallers`. See [Exports](./exports.md).
- There are no other ACE permissions and no other commands.
