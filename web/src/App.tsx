import { Feed } from "./components/Feed"
import { Tablet } from "./components/Tablet"
import { DispatchProvider } from "./lib/state"

/**
 * Two surfaces, both mounted unconditionally and each deciding for itself
 * whether to render -- the headless-registry pattern kora_lib's own App.tsx uses.
 *
 * The Feed is pointer-transparent and always available; the Tablet is the only
 * thing that takes NUI focus, and only while it is open.
 */
export default function App() {
    return (
        <DispatchProvider>
            <Feed />
            <Tablet />
        </DispatchProvider>
    )
}
