/** The `{ action, data }` envelope every SendNUIMessage in this framework uses. */
export interface NuiWireMessage<T = unknown> {
    action: string
    data: T
}

export type UnitState = "en_route" | "on_scene" | "clear"

export interface CallUnit {
    src: number
    state: UnitState
    at: number
    name?: string
    callsign?: string
    job?: string
}

export interface DispatchCall {
    id: number
    service: string
    code?: string
    title: string
    message?: string
    priority: number
    coords?: { x: number; y: number; z: number }
    icon?: string
    createdAt: number
    expiresAt: number
    closedAt?: number
    closeReason?: string
    origin?: string
    data?: Record<string, unknown>
    units: CallUnit[]
}

export interface UnitSnapshot {
    src: number
    name?: string
    callsign?: string
    job?: string
    jobLabel?: string
    grade?: string
    coords: { x: number; y: number; z: number }
    heading: number
    /** Grouped vehicle type from the server, or "foot". */
    vehicle: string
    plate?: string
    /** mph */
    speed: number
}

export interface PriorityConfig {
    label: string
    ttl: number
    color: string
}

export interface CalibrationPoint {
    world: { x: number; y: number }
    image: { x: number; y: number }
}

export interface MapConfig {
    tilePath: string
    /** Tile file extension, without the dot. Defaults to `jpg`. */
    tileExtension?: string
    minZoom: number
    maxZoom: number
    tileSize: number
    /**
     * Tiles across and down at `maxZoom`. Omit for a square pyramid, where both
     * are `2 ** maxZoom`. The in-game-style basemap is 8x12, not square, so the
     * projection cannot assume one number for both axes.
     */
    grid?: { x: number; y: number }
    calibration: { a: CalibrationPoint; b: CalibrationPoint }
    fadeHoldFraction: number
}

export interface ServiceConfig {
    label: string
    accent: string
    /** Lua sends a 1-based array as an object; both shapes are handled. */
    priorities: Record<string, PriorityConfig> | PriorityConfig[]
    feed: { maxVisible: number; position: string; pageSize?: number }
    map: MapConfig
}

export interface Me {
    src: number
    citizenid: string
    name: string
    callsign?: string
    job: string
    jobLabel?: string
    jobType: string
    gradeLabel?: string
}

export interface Keybinds {
    previous: string
    next: string
    respond: string
    toggle: string
    tablet: string
}

/** The single state push from client/ui.lua's render(). */
export interface DispatchState {
    active: boolean
    service?: string
    config?: ServiceConfig
    hidden: boolean
    tabletOpen: boolean
    selected?: number
    me?: Me
    calls: DispatchCall[]
    units: UnitSnapshot[]
    keybinds: Keybinds
    /** GetGameTimer() at the moment of the push, the clock every call timestamp is in. */
    now: number
}

export type ThemeTokens = Record<string, string>
