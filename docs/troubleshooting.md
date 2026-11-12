---
title: Troubleshooting
sidebar_position: 12
---

# Troubleshooting

## The feed never appears

- Dispatch shows nothing unless the player's job is allowed by `Config.access` and (by default) on duty. Check job type against `Config.services`.
- `/dispatchstatus` prints on-duty counts per service to the server console.
- A call reaching `0` recipients means nobody on duty matched. Raise a call with `/dispatchtest` and read the notification.

## createCall returns false

The second value is the reason. Common ones: `resource "x" is not allowed to create dispatch calls` (add it to `Config.trustedCallers`), `no registered job carries the type 'x'` (wrong type name or job not registered), `a call targets exactly one service` (split into one call per service), `a call needs a title or a message`.

## Cannot accept a call

`you are already en route to a call` means the unit hit `Config.dispatch.maxActiveCalls`; clear or detach first. `this call was not sent to your department` means the call was raised with specific `jobs` that do not include the player's job. `wrong service for this call` and `not on duty` speak for themselves.

## Map is blank or markers are misplaced

Check the F8 console for failed tile requests under `nui://kora_dispatch/web/build/map/...`, and that `tilePath`, `tileExtension`, `grid` and `minZoom` match the files. For misplaced markers recalibrate, see [The rendered map](./map.md).

## Everything vanished after a restart

Calls are held in memory only. Restarting the resource clears all calls and history.

## Known caveats (verified in code)

- `Config.feed.pageSize` is not read by any Lua code. The tablet uses fixed page sizes (6, 8, 10, 9).
- The `web/` React sources (`Tablet.tsx`, `Feed.tsx`, `MapView.tsx` and so on) and `web/build/index.html` plus `web/build/assets/` are not used at runtime: the manifest has no `ui_page` and only `web/build/map/**/*` is declared in `files`. The tablet and feed come from `kora_lib`. Features visible only in those sources (for example Active, Mine, History filters, a Detach button, crosshair re-centre) do not exist in the running UI.
- The tablet draws every unit with a car icon even though the server sends a vehicle type.
- `Config.debug` ships as `true`: dev commands are registered and every created call prints a console line.
- `getCall`, `getCalls`, `getOnDutyUnits` and `setUnitState` can be called by any server resource, not only trusted callers.
- `setUiOptions` does not validate `position` or `maxVisible` beyond their types.
