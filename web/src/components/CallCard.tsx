import { Users } from "lucide-react"

import { callIcon } from "./icons"
import { elapsed, isLive, priorityOf, tint } from "../lib/dispatch"
import type { DispatchCall, Me, ServiceConfig } from "../lib/types"

interface Props {
    call: DispatchCall
    now: number
    config?: ServiceConfig
    me?: Me
    selected: boolean
    compact?: boolean
    onSelect?: (id: number) => void
}

/**
 * One call, used by both the overlay feed and the tablet's list.
 *
 * The anatomy follows the design system's alert recipe: a neutral charcoal
 * surface with a 4px semantic left edge, a 16px icon, a title, and supporting
 * metadata. The surface stays charcoal even for a critical call -- painting the
 * whole card red would make three simultaneous emergencies unreadable and leave
 * nothing louder to escalate to.
 */
export function CallCard({ call, now, config, me, selected, compact, onSelect }: Props) {
    const priority = priorityOf(config, call.priority)
    const Icon = callIcon(call.icon)
    const live = isLive(call, now)

    const mine = me ? call.units.find((unit) => unit.src === me.src) : undefined
    const attending = call.units.length

    const Wrapper = onSelect ? "button" : "div"

    return (
        <Wrapper
            {...(onSelect
                ? {
                      type: "button" as const,
                      onClick: () => onSelect(call.id),
                      "aria-pressed": selected,
                  }
                : {})}
            className={[
                "group relative w-full overflow-hidden rounded-md border text-left transition-colors duration-fast",
                compact ? "hud-panel" : "panel",
                selected ? "border-brand-border bg-brand-soft" : "border-border",
                onSelect ? "pointer-events-auto hover:bg-surface-hover focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring" : "",
                // An expired or closed call stays readable in history but must
                // not compete with the live ones above it.
                live ? "" : "opacity-60",
            ].join(" ")}
        >
            {/* The 4px severity edge. Colour alone never carries meaning here --
                the priority label appears in the metadata row too. */}
            <span
                aria-hidden
                className="absolute inset-y-0 left-0 w-1"
                style={{ background: priority?.color ?? "hsl(var(--muted-foreground))" }}
            />

            <div className="flex items-start gap-2 py-2 pl-3 pr-2.5">
                <span
                    className="icon-badge mt-px"
                    style={{
                        background: tint(priority?.color ?? "#949494", 0.14),
                        color: priority?.color ?? "hsl(var(--muted-foreground))",
                    }}
                >
                    <Icon size={14} strokeWidth={2} aria-hidden />
                </span>

                <div className="min-w-0 flex-1">
                    <div className="flex items-baseline gap-1.5">
                        {call.code ? (
                            <span className="font-mono text-[11px] font-semibold leading-[18px] text-foreground">
                                {call.code}
                            </span>
                        ) : null}
                        <span className="truncate text-[13px] font-semibold leading-[18px] text-foreground">
                            {call.title}
                        </span>
                    </div>

                    {!compact && call.message ? (
                        <p className="mt-0.5 line-clamp-2 text-[12px] leading-[17px] text-muted-foreground">
                            {call.message}
                        </p>
                    ) : null}

                    <div className="mt-1 flex flex-wrap items-center gap-x-2 gap-y-0.5 text-[11px] leading-[15px] text-muted-foreground">
                        <span>{priority?.label ?? `P${call.priority}`}</span>
                        <span aria-hidden>·</span>
                        <span className="font-mono tabular-nums">{elapsed(call, now)}</span>
                        {call.data?.street ? (
                            <>
                                <span aria-hidden>·</span>
                                <span className="truncate">{String(call.data.street)}</span>
                            </>
                        ) : null}
                        {attending > 0 ? (
                            <span className="ml-auto inline-flex items-center gap-1">
                                <Users size={11} aria-hidden />
                                <span className="tabular-nums">{attending}</span>
                            </span>
                        ) : null}
                    </div>
                </div>
            </div>

            {/* Your own involvement is the one thing that must be obvious at a
                glance in a stack of otherwise identical cards. */}
            {mine ? (
                <div className="border-t border-border bg-brand-soft px-3 py-1 text-[11px] font-medium leading-[15px] text-foreground">
                    {mine.state === "en_route" ? "You are en route" : null}
                    {mine.state === "on_scene" ? "You are on scene" : null}
                    {mine.state === "clear" ? "You have cleared" : null}
                </div>
            ) : null}
        </Wrapper>
    )
}
