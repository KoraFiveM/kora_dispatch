import { useCallback, useEffect, useLayoutEffect, useMemo, useRef, useState } from "react"
import { Crosshair, Minus, Plus } from "lucide-react"

import { callIcon, unitIcon } from "./icons"
import { isLive, makeProjection, opacity, priorityOf, tint } from "../lib/dispatch"
import type { DispatchCall, MapConfig, Me, ServiceConfig, UnitSnapshot } from "../lib/types"

interface Props {
    map: MapConfig
    config?: ServiceConfig
    calls: DispatchCall[]
    units: UnitSnapshot[]
    me?: Me
    now: number
    selected?: number
    onSelect: (id: number) => void
}

/**
 * The rendered basemap.
 *
 * This exists so calls never become game blips. GTA's blip pool is small and
 * shared with every other resource on the server -- a busy shift dropping a blip
 * per call would exhaust it and silently break garages, shops and job markers
 * everywhere else. Rendering our own map means an unlimited number of markers
 * that cost the game engine nothing.
 *
 * A deliberate ~150 lines instead of Leaflet: a tile layer is a transform and
 * some absolutely-positioned images, and pulling in a mapping library would add
 * ~150KB plus a stylesheet that fights the design system for pan and zoom we can
 * write directly.
 */
export function MapView({ map, config, calls, units, me, now, selected, onSelect }: Props) {
    const projection = useMemo(() => makeProjection(map), [map])

    const containerRef = useRef<HTMLDivElement>(null)
    const [viewport, setViewport] = useState({ width: 0, height: 0 })

    // `scale` is basemap pixels -> screen pixels; `centre` is the basemap pixel
    // under the middle of the viewport. Keeping the camera in basemap space (not
    // world space) means the tile maths never has to invert the projection.
    const [scale, setScale] = useState(0.5)
    const [centre, setCentre] = useState(() => ({ x: projection.size / 2, y: projection.size / 2 }))
    const [following, setFollowing] = useState(true)

    const drag = useRef<{ x: number; y: number; cx: number; cy: number } | null>(null)

    useLayoutEffect(() => {
        const element = containerRef.current
        if (!element) return

        const observer = new ResizeObserver(([entry]) => {
            setViewport({ width: entry.contentRect.width, height: entry.contentRect.height })
        })
        observer.observe(element)
        return () => observer.disconnect()
    }, [])

    // Following recentres on the selected call, or on you when nothing is
    // selected -- the two things you actually want in view. Panning by hand
    // turns it off, so the map stops fighting the player for control.
    const focus = useMemo(() => {
        const call = selected ? calls.find((entry) => entry.id === selected) : undefined
        if (call?.coords) return projection.toImage(call.coords)
        const self = units.find((unit) => unit.src === me?.src)
        if (self) return projection.toImage(self.coords)
        return null
    }, [selected, calls, units, me, projection])

    useEffect(() => {
        if (following && focus) setCentre(focus)
    }, [following, focus])

    const toScreen = useCallback(
        (image: { x: number; y: number }) => ({
            x: (image.x - centre.x) * scale + viewport.width / 2,
            y: (image.y - centre.y) * scale + viewport.height / 2,
        }),
        [centre, scale, viewport],
    )

    // Panning is tracked with WINDOW listeners rather than setPointerCapture.
    // Capturing on the container retargets the subsequent `click` to the capture
    // element in Chromium, which would stop every call marker and zoom button on
    // the map from ever firing its handler. Window listeners also keep a drag
    // alive when the pointer leaves the map, which capture was there for.
    function onPointerDown(event: React.PointerEvent) {
        drag.current = { x: event.clientX, y: event.clientY, cx: centre.x, cy: centre.y }
    }

    useEffect(() => {
        function move(event: PointerEvent) {
            const start = drag.current
            if (!start) return

            // A few pixels of slop, so a click that wobbles is still a click and
            // does not silently turn off follow mode.
            if (Math.hypot(event.clientX - start.x, event.clientY - start.y) < 3) return

            setFollowing(false)
            setCentre({
                x: start.cx - (event.clientX - start.x) / scale,
                y: start.cy - (event.clientY - start.y) / scale,
            })
        }

        function up() {
            drag.current = null
        }

        window.addEventListener("pointermove", move)
        window.addEventListener("pointerup", up)
        window.addEventListener("pointercancel", up)
        return () => {
            window.removeEventListener("pointermove", move)
            window.removeEventListener("pointerup", up)
            window.removeEventListener("pointercancel", up)
        }
    }, [scale])

    function zoomBy(factor: number) {
        setScale((current) => Math.min(4, Math.max(0.12, current * factor)))
    }

    // Only live calls are drawn. An expired call has left the map by definition
    // -- that is what the fade is counting down to -- but it is still readable
    // in the list beside it.
    const visible = calls.filter((call) => call.coords && isLive(call, now))

    return (
        <div
            ref={containerRef}
            onPointerDown={onPointerDown}
            onWheel={(event) => zoomBy(event.deltaY < 0 ? 1.15 : 1 / 1.15)}
            className="relative h-full w-full cursor-grab select-none overflow-hidden bg-background active:cursor-grabbing"
            role="application"
            aria-label="Dispatch map"
        >
            <TileLayer map={map} centre={centre} scale={scale} viewport={viewport} />

            {visible.map((call) => (
                <CallMarker
                    key={call.id}
                    call={call}
                    at={toScreen(projection.toImage(call.coords!))}
                    colour={priorityOf(config, call.priority)?.color ?? "#949494"}
                    opacity={opacity(call, now, map.fadeHoldFraction)}
                    selected={call.id === selected}
                    onSelect={onSelect}
                />
            ))}

            {units.map((unit) => (
                <UnitMarker
                    key={unit.src}
                    unit={unit}
                    at={toScreen(projection.toImage(unit.coords))}
                    isSelf={unit.src === me?.src}
                />
            ))}

            <div className="pointer-events-auto absolute bottom-3 right-3 flex flex-col gap-1">
                <MapButton label="Zoom in" onClick={() => zoomBy(1.4)}>
                    <Plus size={14} aria-hidden />
                </MapButton>
                <MapButton label="Zoom out" onClick={() => zoomBy(1 / 1.4)}>
                    <Minus size={14} aria-hidden />
                </MapButton>
                <MapButton
                    label={following ? "Following" : "Recentre"}
                    active={following}
                    onClick={() => setFollowing(true)}
                >
                    <Crosshair size={14} aria-hidden />
                </MapButton>
            </div>
        </div>
    )
}

function MapButton({
    label, active, onClick, children,
}: { label: string; active?: boolean; onClick: () => void; children: React.ReactNode }) {
    return (
        <button
            type="button"
            onClick={onClick}
            aria-label={label}
            title={label}
            className={[
                "flex h-8 w-8 items-center justify-center rounded-md border transition-colors duration-fast",
                "focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring",
                active
                    ? "border-brand-border bg-brand-soft text-foreground"
                    : "border-border bg-card text-muted-foreground hover:bg-surface-hover hover:text-foreground",
            ].join(" ")}
        >
            {children}
        </button>
    )
}

/**
 * Renders only the tiles the viewport can actually see, at the deepest zoom
 * level whose tiles are still bigger than a screen pixel. Naively drawing the
 * whole pyramid would be 85 image elements every frame; this is typically six to
 * twelve.
 */
function TileLayer({
    map, centre, scale, viewport,
}: { map: MapConfig; centre: { x: number; y: number }; scale: number; viewport: { width: number; height: number } }) {
    if (!viewport.width || !viewport.height) return null

    const full = map.tileSize * 2 ** map.maxZoom

    // Pick the zoom level whose native resolution is closest to what is on
    // screen: one level up from `scale` reaching 1:1 at that level.
    const ideal = map.maxZoom + Math.log2(scale)
    const zoom = Math.max(map.minZoom, Math.min(map.maxZoom, Math.round(ideal)))

    const tilesPerSide = 2 ** zoom
    // How many basemap pixels one tile covers at this level.
    const tileSpan = full / tilesPerSide
    const screenSpan = tileSpan * scale

    const left = centre.x - viewport.width / 2 / scale
    const top = centre.y - viewport.height / 2 / scale

    const firstX = Math.max(0, Math.floor(left / tileSpan))
    const lastX = Math.min(tilesPerSide - 1, Math.floor((left + viewport.width / scale) / tileSpan))
    const firstY = Math.max(0, Math.floor(top / tileSpan))
    const lastY = Math.min(tilesPerSide - 1, Math.floor((top + viewport.height / scale) / tileSpan))

    const tiles = []
    for (let x = firstX; x <= lastX; x++) {
        for (let y = firstY; y <= lastY; y++) {
            tiles.push(
                <img
                    key={`${zoom}/${x}/${y}`}
                    src={`./${map.tilePath}/${zoom}/${x}/${y}.jpg`}
                    alt=""
                    draggable={false}
                    className="absolute origin-top-left"
                    style={{
                        // +1px on the size closes the hairline seams that
                        // sub-pixel positioning otherwise leaves between tiles.
                        left: (x * tileSpan - left) * scale,
                        top: (y * tileSpan - top) * scale,
                        width: screenSpan + 1,
                        height: screenSpan + 1,
                        // The atlas is a bright daytime map; this settles it into
                        // the charcoal palette so markers stay the loudest thing
                        // on screen.
                        filter: "brightness(0.62) saturate(0.72) contrast(1.05)",
                    }}
                />,
            )
        }
    }

    return <div aria-hidden>{tiles}</div>
}

function CallMarker({
    call, at, colour, opacity: alpha, selected, onSelect,
}: {
    call: DispatchCall
    at: { x: number; y: number }
    colour: string
    opacity: number
    selected: boolean
    onSelect: (id: number) => void
}) {
    const Icon = callIcon(call.icon)

    return (
        <button
            type="button"
            onClick={() => onSelect(call.id)}
            title={`${call.code ? `${call.code} ` : ""}${call.title}`}
            className="pointer-events-auto absolute -translate-x-1/2 -translate-y-1/2 rounded-full transition-opacity duration-fast focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
            style={{ left: at.x, top: at.y, opacity: alpha }}
        >
            <span
                className="flex h-6 w-6 items-center justify-center rounded-full border-2 shadow-low"
                style={{
                    borderColor: colour,
                    background: tint(colour, 0.28),
                    color: colour,
                    // The selected call gets a ring rather than a colour change,
                    // so severity colour keeps meaning severity.
                    boxShadow: selected ? `0 0 0 3px ${tint(colour, 0.35)}` : undefined,
                }}
            >
                <Icon size={12} strokeWidth={2.5} aria-hidden />
            </span>
        </button>
    )
}

function UnitMarker({
    unit, at, isSelf,
}: { unit: UnitSnapshot; at: { x: number; y: number }; isSelf: boolean }) {
    const Icon = unitIcon(unit.vehicle)

    return (
        <div
            className="pointer-events-none absolute -translate-x-1/2 -translate-y-1/2"
            style={{ left: at.x, top: at.y }}
            title={[
                isSelf ? "You" : unit.callsign ?? unit.name ?? String(unit.src),
                unit.plate,
                unit.speed ? `${unit.speed} mph` : undefined,
            ]
                .filter(Boolean)
                .join(" · ")}
        >
            {/* Your own marker is filled rather than outlined. Finding yourself
                among a dozen colleagues has to be instant, and a shape/fill
                difference works where a colour difference alone would collide
                with the per-service accent. */}
            <span
                className={[
                    "flex items-center justify-center rounded-full border",
                    isSelf
                        ? "h-[22px] w-[22px] border-primary bg-primary text-primary-foreground"
                        : "h-5 w-5 border-brand-border bg-brand-soft text-foreground",
                ].join(" ")}
            >
                <Icon size={11} strokeWidth={2.5} aria-hidden />
            </span>
            {!isSelf && unit.callsign ? (
                <span className="overlay-text absolute left-1/2 top-full mt-0.5 -translate-x-1/2 whitespace-nowrap font-mono text-[9px] leading-[12px] text-foreground">
                    {unit.callsign}
                </span>
            ) : null}
        </div>
    )
}
