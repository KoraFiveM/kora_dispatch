---
title: Testing
sidebar_position: 11
---

# Testing

## Offline smoke tests

`test/run.sh` runs every file in `test/smoke/` with plain Lua (set `LUA` to pick the interpreter). It needs no FiveM and no database; `test/mocks.lua` provides host stubs and a driven clock, so expiry, fade and retention are deterministic. Suites: `api`, `call_alerts`, `call_blips`, `callbacks`, `calls`, `compat`, `exports`, `focus`, `ingress`, `response_cap`, `units`. The `exports` suite fails if an export is added or removed without updating its list. Run it from the repository root:

```bash
bash test/run.sh
```

This documentation pass did not run the suite.

## Web sources

`web/` has `pnpm typecheck` and `pnpm build` scripts. See [Installation](./installation.md) and [Troubleshooting](./troubleshooting.md) for what is actually served.

## kora_qa scenarios

`tests/checklist-police-and-ems.feature` holds manual QA scenarios, registered by `qa_feature 'tests/*.feature'` in `fxmanifest.lua`.

## In-game checklist

The dev commands need `Config.debug` on and admin rights, see [Commands](./commands.md).

1. Get on duty in a job whose type is a service (how you do that depends on your `kora_core` and job resources).
2. `/dispatchtest 1`, `/dispatchtest 2`, `/dispatchtest 3`: a card with badge, code and title appears, the toast and tone fire, and the feed does not take mouse or camera. `/dispatchtest 1 ems` raises to another service.
3. Page Up and Page Down move the selection. Home accepts (GPS route appears), Home again marks on scene, Home again clears and removes the route. End hides the feed.
4. F9 opens the tablet, which shows the map, calls and units. Close it and confirm mouse control returns.
5. Raise a priority 3 and a priority 1 call. The routine one fades and leaves the live view after about two minutes, the critical one remains; both are in History.
6. Go off duty: the feed disappears and F9 shows the off duty notice.
7. With a second player on duty in the same service, each sees the other on the tablet map and the other's state in the call. A player of another service sees nothing.
8. `/dispatchclear` closes your service's live calls; `/dispatchstatus` prints counts to the server console.
