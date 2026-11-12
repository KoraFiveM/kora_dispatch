---
title: User interface
sidebar_position: 8
---

# User interface

Both surfaces are rendered by `kora_lib` (`Kora.nui.setDispatchFeed` for the feed, `Kora.nui.registerApp` and `openApp` for the tablet). Nothing is shown to players who are not allowed by `Config.access`; when `requireOnDuty` is on, going off duty makes everything disappear and closes the tablet.

## Alert feed

A pointer-transparent overlay that never takes NUI focus. It shows the live calls (up to `Config.feed.maxVisible`), the current selection and key hints. It is not drawn while the tablet is open. `Config.feed.position` places it. A new call also raises a toast (`Config.alerts`) and plays the service tone (call `sound`, then service `sound`, then `Config.defaultService.sound`). Hiding the feed mutes the tone but not the toast or the native blips.

## Keybinds

Registered through `Kora.keybind.add`, so they appear in FiveM key binding settings and are rebindable. Defaults come from `Config.keybinds`.

| Default | Action |
| --- | --- |
| Page Up / Page Down | Move selection to a newer or older call, continuing into history. Ignored while the tablet is open. |
| Home | Respond: accept, then en route to on scene to clear. With nothing selected, selects and responds to the newest live call. Refusals from the server are shown as an error notification. Accepting draws a GPS route to the call, clearing removes it. |
| End | Hide or show the feed. With the tablet open it closes the tablet instead. |
| F9 | Toggle the tablet. For a player in an allowed non-civilian job who is off duty, shows an "off duty" notification; otherwise silent. |

## Tablet

Opens as an AppShell app titled with the service label (1220 by 800). Pages:

- **Live map** - the map with call markers and unit markers, plus a searchable list of active calls (page size 6).
- **Active calls** - searchable list of live calls (page size 8).
- **History** - searchable list of every cached call including expired and closed (page size 10).
- **Selected call** - priority, units assigned, your response, location (`data.street`), origin, created and expires, and the assigned unit timeline. Actions: Accept call, Mark on scene or Clear call (live calls only), and Set route.
- **Units** - on-duty colleagues of your service (page size 9).

Opening and closing the tablet tells the server (`setViewing`), which starts or stops the position heartbeat. Selecting a list item selects that call. Units are drawn on the map with a car icon and the player's own unit is highlighted; the vehicle type the server sends is not used by this UI.

## Theming

A job resource can call `exports.kora_dispatch:setTheme('#3B82F6')` on its client. Without it the accent comes from `Config.services[service].accent`; when that is `nil` it follows `kora_theme` (the server primary and the player's own `/theme` choice).
