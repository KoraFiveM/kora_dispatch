import { useMemo, useState } from "react"
import { MapPin, Navigation, Search, X } from "lucide-react"

import { CallCard } from "./CallCard"
import { KeyChip } from "./KeyChip"
import { MapView } from "./MapView"
import { callIcon } from "./icons"
import { fetchNui } from "../lib/fetchNui"
import { useDispatch } from "../lib/state"
import { STATE_LABELS, bearing, distance2d, elapsed, formatDistance, isLive, priorityOf, tint } from "../lib/dispatch"
import type { DispatchCall } from "../lib/types"

type Filter = "active" | "mine" | "all"

const FILTERS: { key: Filter; label: string }[] = [
    { key: "active", label: "Active" },
    { key: "mine", label: "Mine" },
    { key: "all", label: "History" },
]

/**
 * The large view: call list, map, and the detail of whatever is selected.
 *
 * This is the only surface that takes NUI focus, and it is deliberately optional
 * -- everything needed to work a call is on the keyboard already. The tablet is
 * for when you want the map or the history, not a step in the normal flow.
 */
export function Tablet() {
    const { state, now } = useDispatch()
    const [filter, setFilter] = useState<Filter>("active")
    const [query, setQuery] = useState("")

    // Every hook runs before the early return below: the tablet mounts and
    // unmounts constantly, and a conditional hook would change the hook count
    // between renders and tear the component down on the first toggle.
    const calls = useMemo(() => {
        const term = query.trim().toLowerCase()
        return state.calls.filter((call) => {
            if (filter === "active" && !isLive(call, now)) return false
            if (filter === "mine" && !call.units.some((unit) => unit.src === state.me?.src)) return false
            if (!term) return true
            return [call.title, call.message, call.code].some((field) =>
                field?.toLowerCase().includes(term),
            )
        })
    }, [state.calls, state.me, filter, query, now])

    if (!state.active || !state.tabletOpen) return null

    const config = state.config
    const selected = state.calls.find((call) => call.id === state.selected)

    return (
        <div className="pointer-events-auto fixed inset-0 z-overlay flex items-center justify-center bg-black/[.68] p-4">
            <div className="panel flex h-[min(680px,calc(100vh-2rem))] w-[min(1100px,calc(100vw-2rem))] flex-col overflow-hidden rounded-xl shadow-modal">
                <Header onClose={() => fetchNui("qbdispatch:close")} />

                <div className="grid min-h-0 flex-1 grid-cols-[320px_minmax(0,1fr)_300px]">
                    <aside className="flex min-h-0 flex-col border-r border-border">
                        <div className="flex items-center gap-2 border-b border-border px-3 py-2">
                            <Search size={14} className="shrink-0 text-muted-foreground" aria-hidden />
                            <input
                                value={query}
                                onChange={(event) => setQuery(event.target.value)}
                                placeholder="Search calls"
                                aria-label="Search calls"
                                className="w-full bg-transparent text-[13px] leading-5 text-foreground placeholder:text-muted-foreground focus:outline-none"
                            />
                        </div>

                        <div className="flex gap-1 border-b border-border px-3 py-2">
                            {FILTERS.map((entry) => (
                                <button
                                    key={entry.key}
                                    type="button"
                                    onClick={() => setFilter(entry.key)}
                                    aria-pressed={filter === entry.key}
                                    className={[
                                        "rounded-sm px-2 py-1 text-[12px] font-medium leading-4 transition-colors duration-fast",
                                        "focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring",
                                        filter === entry.key
                                            ? "bg-brand-soft text-foreground"
                                            : "text-muted-foreground hover:bg-surface-hover hover:text-foreground",
                                    ].join(" ")}
                                >
                                    {entry.label}
                                </button>
                            ))}
                        </div>

                        <div className="scroll-thin min-h-0 flex-1 space-y-1.5 overflow-y-auto p-2">
                            {calls.length === 0 ? (
                                <p className="px-2 py-6 text-center text-[12px] leading-[17px] text-muted-foreground">
                                    {filter === "active"
                                        ? "No active calls. Everything is clear."
                                        : "Nothing matches this filter."}
                                </p>
                            ) : (
                                calls.map((call) => (
                                    <CallCard
                                        key={call.id}
                                        call={call}
                                        now={now}
                                        config={config}
                                        me={state.me}
                                        selected={call.id === state.selected}
                                        onSelect={(id) => fetchNui("qbdispatch:select", { id })}
                                    />
                                ))
                            )}
                        </div>
                    </aside>

                    <div className="min-h-0">
                        {config?.map ? (
                            <MapView
                                map={config.map}
                                config={config}
                                calls={state.calls}
                                units={state.units}
                                me={state.me}
                                now={now}
                                selected={state.selected}
                                onSelect={(id) => fetchNui("qbdispatch:select", { id })}
                            />
                        ) : null}
                    </div>

                    <Detail call={selected} />
                </div>

                <footer className="flex items-center gap-3 border-t border-border px-4 py-2 text-[11px] leading-[15px] text-muted-foreground">
                    <span className="inline-flex items-center gap-1">
                        <KeyChip label={state.keybinds.tablet} />
                        Close
                    </span>
                    <span className="inline-flex items-center gap-1">
                        <KeyChip label={state.keybinds.respond} />
                        Respond from the feed
                    </span>
                    <span className="ml-auto tabular-nums">
                        {state.units.length} colleague{state.units.length === 1 ? "" : "s"} on duty
                    </span>
                </footer>
            </div>
        </div>
    )
}

function Header({ onClose }: { onClose: () => void }) {
    const { state } = useDispatch()

    return (
        <header className="flex items-center gap-3 border-b border-border px-4 py-3">
            {/* The slim accent title rail the design system asks for on every
                dialog heading -- a hierarchy cue, not a branded title bar. */}
            <span aria-hidden className="h-5 w-[3px] rounded-full bg-primary" />
            <div className="min-w-0">
                <h1 className="truncate text-[18px] font-semibold leading-6 text-foreground">
                    {state.config?.label ?? "Dispatch"}
                </h1>
                {state.me ? (
                    <p className="truncate text-[12px] leading-[17px] text-muted-foreground">
                        {state.me.callsign ? `${state.me.callsign} · ` : ""}
                        {state.me.name}
                        {state.me.gradeLabel ? ` · ${state.me.gradeLabel}` : ""}
                    </p>
                ) : null}
            </div>

            <button
                type="button"
                onClick={onClose}
                aria-label="Close dispatch"
                className="ml-auto flex h-8 w-8 items-center justify-center rounded-md text-muted-foreground transition-colors duration-fast hover:bg-surface-hover hover:text-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
            >
                <X size={16} aria-hidden />
            </button>
        </header>
    )
}

function Detail({ call }: { call?: DispatchCall }) {
    const { state, now } = useDispatch()

    if (!call) {
        return (
            <aside className="flex items-center justify-center border-l border-border p-6">
                <p className="text-center text-[12px] leading-[17px] text-muted-foreground">
                    Select a call to see its detail and respond.
                </p>
            </aside>
        )
    }

    const priority = priorityOf(state.config, call.priority)
    const Icon = callIcon(call.icon)
    const mine = call.units.find((unit) => unit.src === state.me?.src)

    const self = state.units.find((unit) => unit.src === state.me?.src)
    const range = self && call.coords ? distance2d(self.coords, call.coords) : null

    const nextLabel =
        mine?.state === "en_route" ? "On scene" : mine?.state === "on_scene" ? "Clear" : "Accept"

    return (
        <aside className="scroll-thin min-h-0 overflow-y-auto border-l border-border">
            <div className="space-y-4 p-4">
                <div className="flex items-start gap-2">
                    <span
                        className="icon-badge mt-px"
                        style={{
                            background: tint(priority?.color ?? "#949494", 0.14),
                            color: priority?.color ?? "hsl(var(--muted-foreground))",
                        }}
                    >
                        <Icon size={14} strokeWidth={2} aria-hidden />
                    </span>
                    <div className="min-w-0">
                        <h2 className="text-[16px] font-semibold leading-[22px] text-foreground">{call.title}</h2>
                        <p className="text-[12px] leading-[17px] text-muted-foreground">
                            {call.code ? `${call.code} · ` : ""}
                            {priority?.label ?? `P${call.priority}`} · {elapsed(call, now)} ago
                        </p>
                    </div>
                </div>

                {call.message ? (
                    <p className="text-[13px] leading-[19px] text-foreground">{call.message}</p>
                ) : null}

                {call.closedAt ? (
                    <p className="rounded-md border border-border bg-background px-3 py-2 text-[12px] leading-[17px] text-muted-foreground">
                        Closed{call.closeReason ? `: ${call.closeReason}` : ""}
                    </p>
                ) : null}

                {call.coords ? (
                    <div className="space-y-2">
                        <div className="flex items-center gap-2 text-[12px] leading-[17px] text-muted-foreground">
                            <MapPin size={13} aria-hidden />
                            {range !== null && self ? (
                                <span className="tabular-nums">
                                    {formatDistance(range)} {bearing(self.coords, call.coords)}
                                </span>
                            ) : (
                                <span className="font-mono">
                                    {call.coords.x.toFixed(0)}, {call.coords.y.toFixed(0)}
                                </span>
                            )}
                        </div>
                        <button
                            type="button"
                            onClick={() => fetchNui("qbdispatch:setWaypoint", { id: call.id })}
                            className="inline-flex h-8 items-center gap-1.5 rounded-md border border-border-strong px-3 text-[12px] font-medium leading-4 text-foreground transition-colors duration-fast hover:bg-surface-hover focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
                        >
                            <Navigation size={13} aria-hidden />
                            Route here
                        </button>
                    </div>
                ) : null}

                {call.data && Object.keys(call.data).length > 0 ? (
                    <dl className="space-y-1 rounded-md border border-border bg-background p-3">
                        {Object.entries(call.data).map(([key, value]) => (
                            <div key={key} className="flex gap-2 text-[12px] leading-[17px]">
                                <dt className="w-24 shrink-0 capitalize text-muted-foreground">{key}</dt>
                                <dd className="min-w-0 flex-1 break-words font-mono text-foreground">
                                    {String(value)}
                                </dd>
                            </div>
                        ))}
                    </dl>
                ) : null}

                <div>
                    <h3 className="mb-1.5 text-[12px] font-semibold leading-4 text-muted-foreground">
                        Responding ({call.units.length})
                    </h3>
                    {call.units.length === 0 ? (
                        <p className="text-[12px] leading-[17px] text-muted-foreground">Nobody has responded yet.</p>
                    ) : (
                        <ul className="space-y-1">
                            {call.units.map((unit) => (
                                <li
                                    key={unit.src}
                                    className="flex items-center gap-2 rounded-sm bg-background px-2 py-1.5 text-[12px] leading-[17px]"
                                >
                                    <span className="truncate text-foreground">
                                        {unit.callsign ?? unit.name ?? `Unit ${unit.src}`}
                                    </span>
                                    <span className="ml-auto shrink-0 text-muted-foreground">
                                        {STATE_LABELS[unit.state] ?? unit.state}
                                    </span>
                                </li>
                            ))}
                        </ul>
                    )}
                </div>

                {!call.closedAt ? (
                    <div className="flex gap-2">
                        <button
                            type="button"
                            onClick={() => fetchNui("qbdispatch:respond", { id: call.id })}
                            className="inline-flex h-9 flex-1 items-center justify-center rounded-lg bg-primary px-4 text-[13px] font-medium leading-5 text-primary-foreground shadow-low transition-colors duration-fast hover:bg-brand-hover active:bg-brand-pressed focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
                        >
                            {nextLabel}
                        </button>
                        {mine ? (
                            <button
                                type="button"
                                onClick={() => fetchNui("qbdispatch:respond", { id: call.id, state: false })}
                                className="inline-flex h-9 items-center justify-center rounded-lg px-3 text-[13px] font-medium leading-5 text-muted-foreground transition-colors duration-fast hover:bg-surface-hover hover:text-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
                            >
                                Detach
                            </button>
                        ) : null}
                    </div>
                ) : null}
            </div>
        </aside>
    )
}
