import type { DispatchState } from "./types"

/**
 * Fixture used only when the app runs in a plain browser (`pnpm dev`), so the
 * feed, tablet, map and every call state can be worked on without a running
 * game. It is never reachable in CEF: isBrowserEnv is false there.
 */
export function devState(): DispatchState {
    const now = 1_000_000

    return {
        active: true,
        service: "leo",
        hidden: false,
        tabletOpen: true,
        selected: 3,
        now,
        keybinds: { previous: "PRIOR", next: "NEXT", respond: "HOME", toggle: "END", tablet: "F9" },
        me: {
            src: 1,
            citizenid: "ABC12345",
            name: "Jane Doe",
            callsign: "1-ADAM-12",
            job: "police",
            jobLabel: "Law Enforcement",
            jobType: "leo",
            gradeLabel: "Sergeant",
        },
        config: {
            label: "Police",
            accent: "#3B82F6",
            priorities: {
                "1": { label: "Critical", ttl: 600000, color: "#F04444" },
                "2": { label: "High", ttl: 300000, color: "#F59E0B" },
                "3": { label: "Routine", ttl: 120000, color: "#949494" },
            },
            feed: { maxVisible: 4, position: "left-center" },
            map: {
                tilePath: "map/atlas",
                minZoom: 0,
                maxZoom: 3,
                tileSize: 256,
                calibration: {
                    a: { world: { x: 195.17, y: -933.77 }, image: { x: 970.7, y: 1535.5 } },
                    b: { world: { x: -220, y: 6355 }, image: { x: 901.9, y: 340.2 } },
                },
                fadeHoldFraction: 0.6,
            },
        },
        calls: [
            {
                id: 3,
                service: "leo",
                code: "10-90",
                title: "Bank Robbery",
                message: "Silent alarm triggered at Fleeca, Legion Square. Two suspects reported.",
                priority: 1,
                coords: { x: 150, y: -1040, z: 29 },
                icon: "banknote",
                createdAt: now - 45_000,
                expiresAt: now - 45_000 + 600_000,
                data: { plate: "46EEK572", vehicle: "Sultan", suspects: "2" },
                units: [
                    { src: 2, state: "en_route", at: now - 20_000, name: "Sam Reed", callsign: "1-LINCOLN-4" },
                ],
            },
            {
                id: 2,
                service: "leo",
                code: "10-31",
                title: "Shots Fired",
                message: "Automatic gunfire reported on Vespucci Boulevard.",
                priority: 2,
                coords: { x: -1200, y: -1500, z: 4 },
                icon: "crosshair",
                createdAt: now - 120_000,
                expiresAt: now - 120_000 + 300_000,
                units: [],
            },
            {
                id: 1,
                service: "leo",
                code: "10-16",
                title: "Vehicle Theft",
                message: "Grey Bison taken from Mirror Park.",
                priority: 3,
                coords: { x: 1100, y: -600, z: 57 },
                icon: "car",
                createdAt: now - 110_000,
                expiresAt: now - 110_000 + 120_000,
                units: [{ src: 1, state: "on_scene", at: now - 60_000, name: "Jane Doe", callsign: "1-ADAM-12" }],
            },
        ],
        units: [
            {
                src: 2, name: "Sam Reed", callsign: "1-LINCOLN-4", job: "police", jobLabel: "Law Enforcement",
                grade: "Officer", coords: { x: 300, y: -900, z: 30 }, heading: 90, vehicle: "car", speed: 42, plate: "LSPD 402",
            },
            {
                src: 3, name: "Ade Cole", callsign: "AIR-1", job: "police", jobLabel: "Law Enforcement",
                grade: "Pilot", coords: { x: -800, y: 200, z: 300 }, heading: 210, vehicle: "heli", speed: 96,
            },
        ],
    }
}
