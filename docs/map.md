# The rendered map

## Why dispatch renders its own

GTA's blip pool is small and shared with every resource on the server. A busy
shift dropping a blip per call would exhaust it and start silently breaking
garages, shops and job markers everywhere else — a failure that shows up far from
its cause and is miserable to diagnose.

So calls are never blips. The tablet renders its own basemap, where the marker
count costs the game engine nothing, and exactly one real blip exists at a time:
the GPS route to the call **you** accepted, which is the one thing that genuinely
benefits from the real map.

## The tiles

`web/build/map/atlas/{z}/{x}/{y}.jpg` — a 256px tile pyramid, zoom 0 to 3, 85
files and about 1.8 MB. Zoom 3 is a 2048×2048 image of San Andreas.

A pyramid rather than one large image because it zooms for free, needs no
build-time image tooling, and loads only the six to twelve tiles a viewport can
actually see rather than the whole map every frame.

`web/build/` is committed, so the tiles ship with the resource and there is no
build step at resource-start. `vite.config.ts` sets `emptyOutDir: false` for
exactly this reason — a normal Vite build would delete them.

The atlas (stylised) style is used rather than satellite: it survives the
`brightness(0.62) saturate(0.72)` filter that settles it into the charcoal
palette, and keeps markers the loudest thing on screen. Satellite goes to mud.

## The projection

`Config.map.calibration` holds two reference points, each pairing a world
coordinate with its pixel position at maximum zoom:

```lua
calibration = {
    a = { world = { x = 195.17, y = -933.77 }, image = { x = 970.7, y = 1535.5 } }, -- Legion Square
    b = { world = { x = -220.0, y = 6355.0  }, image = { x = 901.9, y = 340.2  } }, -- Paleto Bay
}
```

Two points rather than opaque scale/offset multipliers, so recalibrating for a
different image is a matter of standing somewhere recognisable rather than
reverse-engineering a transform.

They are far apart on both axes — Legion Square in the south, Paleto Bay in the
far north — so the derived scale stays accurate across the whole map instead of
being fitted to one region.

### How these were verified

Not assumed. The shipped tiles were decoded and the largest inland body of water
located by flood fill; inverting its centroid through this projection gives world
`(1081, 4094)`, which is the Alamo Sea to within about 100 metres. Ten further
land/water probe points across the map (Legion Square, LS Airport, Sandy Shores,
Mount Chiliad, Paleto Bay, Grapeseed, Vinewood Hills, and three open-ocean
points) all land on the right kind of terrain.

## Recalibrating for a different basemap

1. Drop your tiles under `web/build/map/<name>/{z}/{x}/{y}.jpg` and point
   `Config.map.tilePath` at it. Set `minZoom`/`maxZoom`/`tileSize` to match.
2. In game, stand somewhere unmistakable and run `/dispatchcoords`. It prints
   your world position alongside the pixel the current calibration projects it
   to.
3. Open your deepest-zoom image, find the pixel that landmark actually sits on,
   and record the pair.
4. Repeat far away on both axes — the north and south ends of the map, not two
   spots in the city.
5. Put both pairs into `Config.map.calibration` and restart.

`/dispatchcoords` reads nothing and changes nothing; it exists only for this.

## Fade

Each marker's opacity comes from how much of its call's life remains, holding
full for the first `Config.map.fadeHoldFraction` (default 60%) and then easing
out. Fading from the very first second reads as a broken UI rather than as a call
going stale.

Lifetime is per priority (`Config.priorities`), so severity decides how long
something stays visible: a carjacking is gone in two minutes because the vehicle
has left, a bank robbery is still there ten minutes later.

Expired markers leave the map. The calls stay in history.
