import { BellOff } from "lucide-react"

import { CallCard } from "./CallCard"
import { KeyChip } from "./KeyChip"
import { isLive } from "../lib/dispatch"
import { useDispatch } from "../lib/state"

const POSITION: Record<string, string> = {
    "left-center": "left-4 top-1/2 -translate-y-1/2",
    "top-left": "left-4 top-4",
    "top-center": "left-1/2 top-4 -translate-x-1/2",
}

/**
 * The always-on overlay feed.
 *
 * Pointer-transparent for its entire lifetime and it never takes NUI focus --
 * the whole feed is driven by the keybinds, so an officer works calls without
 * ever losing camera control. That is the difference between dispatch being
 * usable during a pursuit and being something you deal with afterwards.
 *
 * Placement: qbhud owns bottom-center, bottom-right and top-right; kora_lib's
 * toasts own top-right; qbinventory's item stack owns bottom-right; the native
 * minimap owns bottom-left. Left-center is the only large uncontested region,
 * and it is configurable for servers that have rearranged things.
 */
export function Feed() {
    const { state, now } = useDispatch()

    if (!state.active || state.tabletOpen) return null

    const config = state.config
    const maxVisible = config?.feed?.maxVisible ?? 4
    const position = POSITION[config?.feed?.position ?? "left-center"] ?? POSITION["left-center"]

    // The selection can be scrolled back into history, so the selected call is
    // always shown even when it has expired off the live list -- otherwise
    // pressing respond would act on something invisible.
    const live = state.calls.filter((call) => isLive(call, now)).slice(0, maxVisible)
    const selected = state.calls.find((call) => call.id === state.selected)
    const showing = selected && !live.some((call) => call.id === selected.id) ? [selected, ...live] : live

    if (state.hidden) {
        // Hidden is a state the player chose, so it says so rather than
        // vanishing -- and it says which key brings it back.
        return (
            <div className={`pointer-events-none fixed z-hud ${position}`}>
                <div className="hud-panel flex items-center gap-2 rounded-md px-2.5 py-1.5">
                    <BellOff size={13} className="text-muted-foreground" aria-hidden />
                    <span className="overlay-text text-[11px] leading-[15px] text-muted-foreground">
                        Dispatch muted
                    </span>
                    <KeyChip label={state.keybinds.toggle} />
                </div>
            </div>
        )
    }

    if (showing.length === 0) return null

    return (
        <section
            className={`pointer-events-none fixed z-hud w-[300px] ${position}`}
            aria-live="polite"
            aria-label="Dispatch calls"
        >
            <div className="flex flex-col gap-1.5">
                {showing.map((call) => (
                    <CallCard
                        key={call.id}
                        call={call}
                        now={now}
                        config={config}
                        me={state.me}
                        selected={call.id === state.selected}
                        compact
                    />
                ))}
            </div>

            {/* Key hints appear only while a call is selected. Permanently
                on-screen they would be clutter; absent entirely, the controls
                would be undiscoverable without reading documentation. */}
            {state.selected ? <Hints /> : null}
        </section>
    )
}

function Hints() {
    const { state } = useDispatch()
    const selected = state.calls.find((call) => call.id === state.selected)
    const mine = state.me ? selected?.units.find((unit) => unit.src === state.me?.src) : undefined

    const respondLabel =
        mine?.state === "en_route" ? "On scene" : mine?.state === "on_scene" ? "Clear" : "Accept"

    return (
        <div className="hud-panel mt-1.5 flex items-center gap-2.5 rounded-md px-2.5 py-1.5">
            <span className="inline-flex items-center gap-1">
                <KeyChip label={state.keybinds.previous} />
                <KeyChip label={state.keybinds.next} />
                <span className="overlay-text text-[10px] leading-[14px] text-muted-foreground">Browse</span>
            </span>
            <span className="inline-flex items-center gap-1">
                <KeyChip label={state.keybinds.respond} />
                <span className="overlay-text text-[10px] leading-[14px] text-foreground">{respondLabel}</span>
            </span>
            <span className="ml-auto inline-flex items-center gap-1">
                <KeyChip label={state.keybinds.tablet} />
                <span className="overlay-text text-[10px] leading-[14px] text-muted-foreground">Map</span>
            </span>
        </div>
    )
}
