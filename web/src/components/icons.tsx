import {
    AlertTriangle, Banknote, Bike, Car, Crosshair, Flame, HeartPulse, Home, Package, PersonStanding,
    Plane, Radio, Ship, Siren, Stethoscope, Truck, Users, Wrench,
} from "lucide-react"
import type { LucideIcon } from "lucide-react"

/**
 * Calls name their icon as a string (`icon = 'banknote'`) because the icon is
 * chosen server-side by whichever job resource raised the call, and a Lua table
 * cannot hold a React component. Anything unrecognised falls back rather than
 * rendering a hole -- a robbery script naming an icon this build doesn't have
 * should still produce a usable alert.
 */
const CALL_ICONS: Record<string, LucideIcon> = {
    banknote: Banknote,
    car: Car,
    crosshair: Crosshair,
    fire: Flame,
    "heart-pulse": HeartPulse,
    home: Home,
    package: Package,
    person: PersonStanding,
    radio: Radio,
    siren: Siren,
    stethoscope: Stethoscope,
    truck: Truck,
    wrench: Wrench,
}

export function callIcon(name?: string): LucideIcon {
    return (name && CALL_ICONS[name]) || AlertTriangle
}

/**
 * Vehicle-class groups from server/units.lua. The server sends "what shape is
 * this unit" rather than GTA's 22-way class taxonomy, so a glance at the map
 * says whether backup is a car, a bike or the helicopter.
 */
const UNIT_ICONS: Record<string, LucideIcon> = {
    foot: PersonStanding,
    car: Car,
    sports: Car,
    offroad: Truck,
    van: Truck,
    truck: Truck,
    bike: Bike,
    boat: Ship,
    heli: Plane,
    emergency: Siren,
    military: Truck,
    service: Truck,
}

export function unitIcon(name?: string): LucideIcon {
    return (name && UNIT_ICONS[name]) || Users
}
