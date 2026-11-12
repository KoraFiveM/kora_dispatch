import type { CalibrationPoint, DispatchCall, MapConfig, PriorityConfig, ServiceConfig } from "./types"

/**
 * The game clock advances while the browser's own clock does too, but the two
 * are not the same number. Every timestamp on a call is `GetGameTimer()`, so the
 * UI keeps a local estimate of it: the last value Lua sent, plus however long
 * ago the browser received it.
 *
 * Without this, timers and the fade would only move when Lua happened to push,
 * which is on state changes -- a quiet minute would freeze every countdown.
 */
export class GameClock {
    private base = 0
    private receivedAt = 0

    sync(now: number) {
        this.base = now
        this.receivedAt = performance.now()
    }

    now(): number {
        if (!this.receivedAt) return this.base
        return this.base + (performance.now() - this.receivedAt)
    }
}

/**
 * Priority definitions can arrive in two shapes and they index differently.
 *
 * The server re-keys them to strings precisely so this is unambiguous, but a
 * DENSE Lua array (`[1]`, `[2]`, `[3]`) goes through json.encode as a JSON
 * ARRAY, where index 0 is priority 1 -- reading `table["1"]` off that returns
 * priority 2's definition and shifts every label, colour and lifetime by one.
 * Both shapes are handled rather than assumed.
 */
export function priorityOf(
    config: ServiceConfig | undefined,
    priority: number,
): PriorityConfig | undefined {
    const table = config?.priorities
    if (!table) return undefined

    if (Array.isArray(table)) return table[priority - 1]
    return (table as Record<string, PriorityConfig>)[String(priority)]
}

export function isLive(call: DispatchCall, now: number): boolean {
    return !call.closedAt && now < call.expiresAt
}

/**
 * Marker opacity: full for the first `hold` of a call's life, then a linear ease
 * out. Mirrors Dispatch.calls.opacity in shared/calls.lua -- fading from the
 * very first second reads as a broken UI rather than as a call going stale.
 */
export function opacity(call: DispatchCall, now: number, holdFraction: number): number {
    const span = call.expiresAt - call.createdAt
    if (span <= 0) return 0

    const left = Math.max(0, Math.min(1, (call.expiresAt - now) / span))
    const hold = 1 - holdFraction
    if (hold <= 0) return left > 0 ? 1 : 0
    return left >= hold ? 1 : left / hold
}

/** "4m 12s" / "38s" -- how long a call has been open. */
export function elapsed(call: DispatchCall, now: number): string {
    const seconds = Math.max(0, Math.floor((now - call.createdAt) / 1000))
    if (seconds < 60) return `${seconds}s`
    return `${Math.floor(seconds / 60)}m ${String(seconds % 60).padStart(2, "0")}s`
}

/** "240m" / "1.4km" -- distance to a call from wherever the viewer is. */
export function formatDistance(metres: number): string {
    if (metres < 1000) return `${Math.round(metres)}m`
    return `${(metres / 1000).toFixed(1)}km`
}

/**
 * GTA heading convention: 0 is north (+Y) and it increases counter-clockwise, so
 * 90 is west. Reversing this is the classic bearing bug -- it puts every call on
 * the opposite side of the compass from where it is.
 */
const COMPASS = ["N", "NW", "W", "SW", "S", "SE", "E", "NE"]

export function bearing(from: { x: number; y: number }, to: { x: number; y: number }): string {
    const heading = ((Math.atan2(-(to.x - from.x), to.y - from.y) * 180) / Math.PI + 360) % 360
    return COMPASS[Math.round(heading / 45) % 8]
}

export function distance2d(a: { x: number; y: number }, b: { x: number; y: number }): number {
    return Math.hypot(a.x - b.x, a.y - b.y)
}

/**
 * World -> basemap pixel projection, derived from the two calibration reference
 * points rather than hard-coded multipliers, so swapping in a different map
 * image is a config change and not a code change.
 *
 * Returns pixels at the deepest zoom level; the tile layer scales from there.
 */
export function makeProjection(map: MapConfig) {
    const { a, b }: { a: CalibrationPoint; b: CalibrationPoint } = map.calibration

    const scaleX = (b.image.x - a.image.x) / (b.world.x - a.world.x)
    const scaleY = (b.image.y - a.image.y) / (b.world.y - a.world.y)

    return {
        toImage(world: { x: number; y: number }) {
            return {
                x: a.image.x + (world.x - a.world.x) * scaleX,
                y: a.image.y + (world.y - a.world.y) * scaleY,
            }
        },
        toWorld(image: { x: number; y: number }) {
            return {
                x: a.world.x + (image.x - a.image.x) / scaleX,
                y: a.world.y + (image.y - a.image.y) / scaleY,
            }
        },
        /**
         * Full basemap size in pixels at the deepest zoom.
         *
         * Two numbers, not one: the basemap is not necessarily square. The
         * in-game-style pyramid is 8 tiles across and 12 down, and treating it
         * as square put the initial camera a third of the map below the coast
         * and let the tile grid ask for rows that do not exist.
         */
        size: {
            width: map.tileSize * (map.grid?.x ?? 2 ** map.maxZoom),
            height: map.tileSize * (map.grid?.y ?? 2 ** map.maxZoom),
        },
    }
}

export const STATE_LABELS: Record<string, string> = {
    en_route: "En route",
    on_scene: "On scene",
    clear: "Clear",
}

/**
 * Hex -> `rgba()` at a given alpha.
 *
 * Deliberately not CSS `color-mix()`, which only landed in Chromium 111 --
 * FiveM's bundled CEF lags well behind that, and an unsupported colour function
 * fails SILENTLY: the declaration is dropped and the swatch renders transparent,
 * so every priority tint would just disappear with no error to find.
 */
export function tint(hex: string, alpha: number): string {
    const value = hex.replace("#", "")
    const full = value.length === 3 ? value.split("").map((c) => c + c).join("") : value
    const int = Number.parseInt(full, 16)

    if (!Number.isFinite(int) || full.length !== 6) return `rgba(148, 148, 148, ${alpha})`

    return `rgba(${(int >> 16) & 255}, ${(int >> 8) & 255}, ${int & 255}, ${alpha})`
}
