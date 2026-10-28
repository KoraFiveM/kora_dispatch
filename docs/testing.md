# Testing dispatch in game

Everything below works **solo**. The dev commands exist precisely so raising a
real call doesn't mean committing a crime, dying, or waiting for a colleague.

They are registered only while `Config.debug` is on (it is, on this test server)
and are admin-gated even then — `/dispatchtest` can put arbitrary text and
coordinates in front of every on-duty player of a service.

---

## 1. Get on duty

You need a job whose `type` is a dispatch service. Stock: `police` → `leo`,
`ambulance` → `ems`, `tow` → `recovery`.

```
/setjob <your id> police 4
/police-duty
```

`/setjob` is kora_admin. For EMS it's `/ems-duty`; for police `/police-duty` (added
for exactly this reason — duty is normally a target zone at the station, which
means travelling there before you can test anything).

Your server id is in the pause menu, or `/setjob` with a wrong id will tell you.

The feed only appears when you are **on duty**. Off duty is a valid thing to
check too: it should vanish entirely.

---

## 2. Raise a call

```
/dispatchtest          -- priority 2, your own service, at your position
/dispatchtest 1        -- critical: a bank robbery
/dispatchtest 3        -- routine: a vehicle theft
/dispatchtest 1 ems    -- to another service, whatever job you're in
```

Each priority raises a *different, representative* call, so you're exercising the
real severity model — badge, colour, lifetime, fade — not three identical alerts
that differ by a number.

Other helpers:

```
/dispatchclear         -- close every live call on your service
/dispatchstatus        -- print live/history counts and viewers to the server console
/dispatchcoords        -- print your world position and its projected map pixel
```

---

## 3. What to check

### The feed (no keys pressed)
A card appears left-of-centre with a coloured severity edge, the code, the title,
elapsed time, and a unit count. An alert tone plays. It should **not** steal your
mouse or camera.

### The keys
| Key | Expect |
| --- | --- |
| `Page Up` / `Page Down` | Selection moves; a key-hint row appears under the feed. Keep pressing `Page Down` past the live calls — you should scroll into expired ones. |
| `Home` | "You are en route" appears on the card, and a **GPS route** draws on your real minimap. |
| `Home` again | "You are on scene". |
| `Home` again | "You have cleared", and the route blip disappears. |
| `End` | The whole feed collapses to a "Dispatch muted" chip. Press again to restore. |
| `F9` | The tablet opens and takes your mouse. |

All five are rebindable in **FiveM settings → Key Bindings → FiveM**, which is
worth confirming at least once.

### The tablet (`F9`)
- The map should show **San Andreas**, dimmed to match the UI, with your call
  marked where you stood. Drag to pan, scroll to zoom, `Crosshair` button to
  re-centre.
- You are a **filled** marker; colleagues are outlined with their callsign.
- Left column: `Active` / `Mine` / `History` filters and a search box.
- Right column: the call detail, the `data` fields, who is responding, and
  Accept / Detach.
- `Route here` sets the GPS.
- Closing with `F9` or the ✕ must give your mouse back.

### Severity fade
Raise a `/dispatchtest 3` (routine, 2-minute life) and a `/dispatchtest 1`
(critical, 10 minutes). Watch the map: the routine marker holds full opacity for
about 70 seconds, then fades out and disappears at ~2 minutes. The critical one
is still there. Both remain readable under `History`.

### Per-service colour
The whole UI is **blue** as police, **red** as EMS. Change job and duty and it
should recolour without a restart:

```
/setjob <id> ambulance 4
/ems-duty
```

---

## 4. The real triggers (no dev commands)

Once the basics look right, these are the paths that matter in play:

| Action | Expect |
| --- | --- |
| `/backup` on duty | A `10-78` call naming your callsign |
| `F10` (panic) | **Two** calls: `10-99` to police and `10-52` to EMS |
| Fire a gun as a **civilian** | A `10-31 Shots Fired` call to police |
| Try to jack an occupied car | A `10-16 Vehicle Theft` call |
| `/911e stabbed outside the Yellow Jack` | A priority-1 EMS call, and you're told whether anyone heard it |
| Get killed as a civilian | `10-52 Person Down`, then `10-54` if you bleed out |
| Get revived | That patient's call **closes** by itself |
| `/housecall my arm hurts` | A priority-3 EMS call; accepting it removes it for everyone |

Fire a gun while **on duty as police** and nothing should happen — detectors
deliberately exclude on-duty officers, or a firearms unit would alert dispatch
about itself.

---

## 5. Two players

Worth doing once, because a couple of things only exist between people:

- Both on duty in the same service: each sees the other on the tablet map, with
  a vehicle icon that changes when they get in a car or a helicopter.
- One accepts a call: the other's unit list shows them as *En route*.
- The accepter goes off duty: they should drop off the call's unit list.
- One in `leo`, one in `ems`: neither sees the other's calls at all.

---

## 6. If something looks wrong

- **Feed never appears** → are you on duty? `/dispatchstatus` prints the on-duty
  count per service to the server console.
- **Map is blank or grey** → the tiles are served from
  `nui://kora_dispatch/web/build/map/...`; check the F8 console for 404s.
- **Markers in the wrong place** → recalibrate with `/dispatchcoords`, see
  [map.md](map.md).
- **Mouse stuck after the tablet** → that's a bug, not a setting; `/dispatchstatus`
  and the F8 console are the first things to grab.
