import { useEffect, useRef } from "react"

import type { NuiWireMessage } from "./types"

/**
 * Subscribes to messages sent from Lua via SendNUIMessage for one `action`.
 *
 * The window listener is only attached/removed when `action` changes -- the
 * latest handler is reached through a ref, so passing a fresh inline arrow
 * every render doesn't tear the listener down and re-add it each time.
 *
 * Deliberately no event.source/event.origin check. FiveM posts SendNUIMessage
 * from the game's own NUI window (origin "nui://game"), not from this page, so
 * any source/origin gate silently discards every real message from Lua. The
 * same warning is on qblib's and qbhud's copies of this file.
 */
export function useNuiEvent<T = unknown>(action: string, handler: (data: T) => void) {
    const handlerRef = useRef(handler)
    handlerRef.current = handler

    useEffect(() => {
        function listener(event: MessageEvent<NuiWireMessage<T>>) {
            if (event.data?.action === action) handlerRef.current(event.data.data)
        }

        window.addEventListener("message", listener)
        return () => window.removeEventListener("message", listener)
    }, [action])
}
