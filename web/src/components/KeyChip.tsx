/**
 * A keyboard key rendered as a chip. Deliberately shows the CONFIGURED key
 * rather than a hard-coded one -- every dispatch bind is rebindable in FiveM's
 * own settings, so a hard-coded hint would start lying the moment a player
 * changed it.
 */
export function KeyChip({ label }: { label: string }) {
    return (
        <kbd className="rounded-xs border border-border-strong bg-surface-raised px-1 py-px font-mono text-[10px] font-medium leading-[14px] tracking-wide text-muted-foreground">
            {label}
        </kbd>
    )
}
