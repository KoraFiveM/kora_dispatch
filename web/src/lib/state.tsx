import { createContext, useContext, useEffect, useMemo, useRef, useState } from "react"
import type { ReactNode } from "react"

import { fetchNui, isBrowserEnv } from "./fetchNui"
import { useNuiEvent } from "./useNuiEvent"
import { GameClock } from "./dispatch"
import { devState } from "./dev"
import type { DispatchState } from "./types"

const EMPTY: DispatchState = {
    active: false,
    hidden: false,
    tabletOpen: false,
    calls: [],
    units: [],
    keybinds: { previous: "PRIOR", next: "NEXT", respond: "HOME", toggle: "END", tablet: "F9" },
    now: 0,
}

interface Store {
    state: DispatchState
    /** Estimated live GetGameTimer(), advancing between pushes. */
    now: number
}

const Context = createContext<Store>({ state: EMPTY, now: 0 })

export function useDispatch(): Store {
    return useContext(Context)
}

export function DispatchProvider({ children }: { children: ReactNode }) {
    const [state, setState] = useState<DispatchState>(isBrowserEnv ? devState() : EMPTY)
    const clock = useRef(new GameClock())
    const [now, setNow] = useState(0)

    useNuiEvent<DispatchState>("kora_dispatch:state", (next) => {
        if (!next) return
        clock.current.sync(next.now)
        setState(next)
    })

    // Announce the frame is mounted. SendNUIMessage is postMessage-like, not a
    // mailbox -- anything Lua sent before this point was queued on its side, and
    // this ping is what releases it. Without it the UI stays blank until the
    // next state change, which on a quiet server can be minutes.
    useEffect(() => {
        fetchNui("kora_dispatch:ready").catch((error) => {
            console.error("[kora_dispatch] ready ping failed:", error)
        })
    }, [])

    // One shared ticker drives every countdown and the marker fade. A timer per
    // call would mean dozens of intervals fighting over the same frame; 500ms is
    // under the resolution anyone can perceive on a minutes-long countdown.
    useEffect(() => {
        const id = window.setInterval(() => setNow(clock.current.now()), 500)
        return () => window.clearInterval(id)
    }, [])

    const store = useMemo<Store>(() => ({ state, now: now || state.now }), [state, now])

    return <Context.Provider value={store}>{children}</Context.Provider>
}
