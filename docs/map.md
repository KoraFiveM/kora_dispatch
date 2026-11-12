---
title: The rendered map
sidebar_position: 9
---

# The rendered map

## Two kinds of map output

- **Tablet map** - shows every live call that has coordinates, plus colleague units. It costs the game no blips.
- **Native map blips** - GTA's blip pool is shared by every resource, so dispatch creates at most `Config.map.maxCallBlips` (default 4) ordinary blips for live calls, chosen by priority (most urgent first, then newest). They are in the `Dispatch` blip category, never set a GPS route and carry priority, street and message in their info panel. Disable with `Config.map.showCallBlips = false`. The set is refreshed on changes and every 5 seconds so expiry removes markers.
- **Route blip** - exactly one at a time, for the call you accepted (or chose with Set route). It is removed when you clear the call, when the call closes, and when you go off duty.

## Marker fade

A call marker keeps full opacity for the first `Config.map.fadeHoldFraction` (default 0.6) of its life, then fades out until expiry. Expired markers leave the map; the call stays in history.

## The tiles

Tiles are served from `web/build/map/mainmap/`, with files matching `z/x/y.png`, 256 px tiles, zoom 1 to 3 (the manifest `files` entry is `web/build/map/**/*`). The default set is the in-game pause map style and is not square: 8 tiles across and 12 down at zoom 3 (`Config.map.grid`). `minZoom` is 1 because the upstream zoom-0 tile is not a uniform reduction of zoom 1 and is not shipped. A square pyramid may omit `grid`.

The tablet requests tiles as `https://cfx-nui-kora_dispatch/web/build/tilePath/z/x/y.tileExtension`. If `tileExtension` is missing it assumes `jpg`.

## Projection

`Config.map.calibration` has two reference points, `a` (Legion Square) and `b` (Paleto Bay). Each pairs a world position (`world.x`, `world.y`) with the pixel (`image.x`, `image.y`) it has at maximum zoom. Two points far apart on both axes give an accurate scale over the whole map. `/dispatchcoords` applies the same linear mapping, so it matches what the tablet projects.

## Recalibrating for a different basemap

1. Put tiles under `web/build/map/NAME/z/x/y.EXT`, set `Config.map.tilePath` (for example `map/NAME`), `tileExtension`, `minZoom`, `maxZoom`, `tileSize` and `grid`. Tiles must be covered by the manifest `files` pattern.
2. Stand on a recognisable landmark and run `/dispatchcoords`.
3. Find the pixel that landmark occupies in your maximum-zoom image.
4. Repeat at a landmark far away on both axes.
5. Put both pairs into `Config.map.calibration` and restart the resource.

The repository also ships an older square atlas tile set under `web/build/map/atlas` (`Config.map` comments describe it as 2048 by 2048 `jpg`, zoom 0 to 3). Switching to it means changing `tilePath`, `tileExtension`, `minZoom`, `grid` and the calibration; the existing calibration values are for the default set only.

## Wheel zoom

`Config.map.captureWheel` (default `true`) lets the map consume the mouse wheel. Set `false` to let the wheel pass to the page.
