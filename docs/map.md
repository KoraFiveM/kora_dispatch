# The rendered map

## Why dispatch renders its own

GTA's blip pool is small and shared with every resource on the server. A busy
shift dropping a blip per call would exhaust it and start silently breaking
garages, shops and job markers everywhere else — a failure that shows up far from
its cause and is miserable to diagnose.

The tablet therefore renders the complete queue on its own basemap, where the
marker count costs the game engine nothing. The native map shows only the most
urgent `Config.map.maxCallBlips` calls (four by default), grouped beneath
kora_lib's `Dispatch` category, and the GPS route to the call **you** accepted.

## The tiles

`web/build/map/mainmap/{z}/{x}/{y}.png` -- 256px tiles, zoom 1 to 3, 126 files
and about 4.8 MB. Zoom 3 is a 2048x3072 image of San Andreas.

This is the **in-game pause map**: dark landmass, white road network, the thing
the player has already spent a hundred hours reading. The stylised "atlas"
tourist map that shipped before is still vendored at `web/build/map/atlas`
(square, 2048x2048, `.jpg`, zoom 0 to 3, 1.8 MB) and switching back is four
config values plus a recalibration -- see below.

A pyramid rather than one large image because it zooms for free, needs no
build-time image tooling, and loads only the six to twelve tiles a viewport can
actually see rather than the whole map every frame.

`web/build/` is committed, so the tiles ship with the resource and there is no
build step at resource-start. `vite.config.ts` sets `emptyOutDir: false` for
exactly this reason -- a normal Vite build would delete them.

### Two things about this set that are not true of a normal tile pyramid

**It is not square.** 8 tiles across and 12 down at zoom 3. `Config.map.grid`
states both axes, and `makeProjection` returns `size` as `{width, height}`
rather than one number. A square pyramid can omit `grid` and gets
`2 ** maxZoom` on both axes.

**`minZoom` is 1, not 0.** The upstream set has a zoom-0 tile, but it squeezes
the whole 2:3 map into a single 256x256 square, so it is not a uniform reduction
of zoom 1 -- rendering it would show the map vertically squashed. It is not
vendored, and `minZoom = 1` means nothing asks for it.

No colour correction is applied to the tiles. The old
`brightness(0.62) saturate(0.72)` filter existed to settle the bright atlas into
the charcoal palette; on this basemap it only crushes the road network into the
landmass, so `TileGrid` paints the tiles as they are.

## The projection

`Config.map.calibration` holds two reference points, each pairing a world
coordinate with its pixel position at maximum zoom:

```lua
calibration = {
    a = { world = { x = 195.17, y = -933.77 }, image = { x = 985.2, y = 2126.8 } }, -- Legion Square
    b = { world = { x = -220.0, y = 6355.0  }, image = { x = 890.1, y = 474.3  } }, -- Paleto Bay
}
```

Two points rather than opaque scale/offset multipliers, so recalibrating for a
different image is a matter of standing somewhere recognisable rather than
reverse-engineering a transform.

They are far apart on both axes -- Legion Square in the south, Paleto Bay in the
far north -- so the derived scale stays accurate across the whole map instead of
being fitted to one region.

### How these were derived

Not guessed, and not carried over: the atlas numbers do not transfer, because
the two sets differ in canvas size, aspect and margin.

1. Both pyramids were decoded at zoom 3 and reduced to a **land mask** -- the
   atlas by rejecting its blue water, this set by flood-filling the near-black
   ocean inward from the image border, which stops at the light-grey coastal
   glow and leaves the landmass as the black region inside it.
2. The two land bounding boxes give the atlas-to-this-set transform. Measured
   independently per axis they came out at 1.3786 and 1.3864 -- 0.6% apart,
   which is threshold noise at the coastline, since a to-scale render can only
   have one scale. The mean, 1.38251, was used uniformly, with the offsets
   fitted so the two bounding boxes share a centre.
3. Composing that with the atlas's already-verified world-to-pixel calibration
   gives the numbers above.

### How these were verified

Nine known world positions were projected through the result and each checked
against the rendered imagery: Legion Square, LS International, Del Perro Pier,
Fort Zancudo, Sandy Shores, Grapeseed, Mount Chiliad, Paleto Bay, and the
published centre of the Alamo Sea -- which lands dead centre on the lake the
imagery draws.

Two independent numeric checks agree:

- The two derived axis scales are 0.22906 and 0.22671 px per world unit, equal
  in magnitude to within 1%, as an isotropic render requires.
- Inverting the landmass bounding box gives world `x` in `[-3263, 3953]` and `y`
  in `[-3568, 7115]`, which is San Andreas' actual extent.

Note that the atlas's flood-fill check -- isolate the largest inland water body
and invert its centroid -- **does not work on this basemap**. The coastal glow
and the inland lakes are drawn in the same grey band and are connected through
the river mouths, so the fill escapes the Alamo Sea into the open ocean and
reports a centroid nearly 3000 units out. The failure is in the measuring
technique, not the projection; the landmark checks above are what stands in for
it here.

## Recalibrating for a different basemap

1. Drop your tiles under `web/build/map/<name>/{z}/{x}/{y}.<ext>` and point
   `Config.map.tilePath` at it. Set `tileExtension`, `minZoom`/`maxZoom`,
   `tileSize`, and `grid` (omit `grid` only if the pyramid is square).
2. In game, stand somewhere unmistakable and run `/dispatchcoords`. It prints
   your world position alongside the pixel the current calibration projects it
   to.
3. Open your deepest-zoom image, find the pixel that landmark actually sits on,
   and record the pair.
4. Repeat far away on both axes -- the north and south ends of the map, not two
   spots in the city.
5. Put both pairs into `Config.map.calibration` and restart.

`/dispatchcoords` reads nothing and changes nothing; it exists only for this.

## Wheel zoom

The mouse wheel zooms the map and is consumed there, so the surrounding tablet
or page does not scroll at the same time. `Config.map.captureWheel` (default
`true`) controls this; set it to `false` to let the wheel pass through to the
page and zoom with the buttons only.

## Fade

Each marker's opacity comes from how much of its call's life remains, holding
full for the first `Config.map.fadeHoldFraction` (default 60%) and then easing
out. Fading from the very first second reads as a broken UI rather than as a call
going stale.

Lifetime is per priority (`Config.priorities`), so severity decides how long
something stays visible: a carjacking is gone in two minutes because the vehicle
has left, a bank robbery is still there ten minutes later.

Expired markers leave the map. The calls stay in history.
