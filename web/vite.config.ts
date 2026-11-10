import path from "path"
import react from "@vitejs/plugin-react"
import { defineConfig } from "vite"
import kora_theme from "../../kora_theme/vite-plugin.mjs"

// FiveM's CEF NUI browser loads this page from a local resource path, not from
// a domain root -- asset URLs must be relative ("./assets/..") or every
// script/style 404s in-game. Do NOT change `base` back to "/". Same convention
// as kora_lib's and kora_hud's own vite configs.
export default defineConfig({
    plugins: [kora_theme(), react()],
    base: "./",
    build: {
        outDir: "build",
        // The vendored basemap tiles live under build/map and are committed, so
        // the output directory must NOT be emptied on every build.
        //
        // The cost of that is stale hashed bundles piling up in build/assets,
        // which then get committed alongside the live one. The `prebuild` script
        // in package.json clears build/assets specifically, which keeps the
        // output clean without touching the tiles.
        emptyOutDir: false,
    },
    resolve: {
        alias: {
            "@": path.resolve(__dirname, "./src"),
        },
    },
})
