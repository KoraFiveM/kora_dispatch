---
title: "Commands"
sidebar_position: 4
---


# Commands

Three server commands exist only while `Config.debug` is `true` (the shipped default); `/dispatchcoords` is a client command that always registers. The three debug commands are additionally gated behind an admin check (`Kora.permissions.hasLevel`, accepting either the `kora_core.<level>` or bare `group.<level>` ACE principal, levels `god`/`admin`/`mod`/`user`) — a non-admin typing them gets nothing.

## Commands

### `/dispatchtest [priority] [service]`

Raises a real, representative sample call (one of three canned payloads per priority) against a service, so dispatch can be exercised solo without committing a crime or waiting for a colleague.

| Field | Details |
| --- | --- |
| Context | In-game · server command (registered only while Config.debug is true) |
| Arguments | priority? — 1, 2 or 3 (default Config.defaultPriority). service? — a job type such as leo/ems/recovery; defaults to the caller's own job type, refusing with an error if the caller has no dispatch job type. |
| Access | Admin only (god/admin/mod/user ladder via Kora.permissions.hasLevel). Not registered unless Config.debug is true. |

**Example**

```text
/dispatchtest
/dispatchtest 1 leo
```

**Result**

A success notification with the new call id, service, priority and recipient count, or an error notification. If the call reached 0 units it specifically tells the admin whether that is because they are off duty themselves or because nobody is on duty for that service.

### `/dispatchclear`

Closes every currently live call on the caller's own service (reason `'cleared by an admin'`).

| Field | Details |
| --- | --- |
| Context | In-game · server command (registered only while Config.debug is true) |
| Arguments | No arguments. |
| Access | Admin only, and only while Config.debug is true. Refuses with an error notification if the caller has no job type. |

**Example**

```text
/dispatchclear
```

**Result**

A notification with the number of calls closed.

### `/dispatchstatus`

Prints tablet viewer count and, per service, live/total call counts and on-duty unit count to the server console.

| Field | Details |
| --- | --- |
| Context | Server console (via the command) · server command (registered only while Config.debug is true) |
| Arguments | No arguments. |
| Access | Admin only, and only while Config.debug is true. |

**Example**

```text
/dispatchstatus
```

**Result**

Console lines plus an in-game info notification confirming it printed.

### `/dispatchcoords`

Prints the player's current world position alongside the pixel the current `Config.map.calibration` projects it to, for recalibrating the tablet map against a different tile set. Reads nothing and changes nothing.

| Field | Details |
| --- | --- |
| Context | In-game · client command |
| Arguments | No arguments. |
| Access | Any player. Always registered, independent of Config.debug. |

**Example**

```text
/dispatchcoords
```

**Result**

A console line: `[kora_dispatch] world (x, y, z) -> map pixel (x, y)`.

## Permissions summary

- Dev commands: the `admin` level, checked with `Kora.permissions.hasLevel` (prefix `kora_core`, levels `god`, `admin`, `mod`, `user`), so `kora_core.admin` or `group.admin` and higher levels pass.
- `/dispatchtest` and `/dispatchclear` run as a trusted caller because they run inside this resource.
- `/dispatchtest` raises sample calls at your position: priority 1 Bank Robbery `10-90`, 2 Shots Fired `10-31`, 3 Vehicle Theft `10-16`. With a job type of `none` or `civ`, or no job, you must pass a service.
- Using dispatch: `Config.access` (job based), checked server-side. See [Configuration](./configuration.md).
- Call creation exports: `Config.trustedCallers`. See [Server API](./api/server-api.md).
- There are no other ACE permissions and no other commands.
