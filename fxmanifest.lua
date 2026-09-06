fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'qbdispatch'
author 'qbcore2'
version '0.1.0'
description 'Job-agnostic dispatch: call lifecycle, keyboard-driven alert feed, and a tablet with a rendered map'

-- Every job resource that raises calls depends on this one, so it has to be
-- running before them. qbcore supplies the job/duty indexes the recipient
-- resolution reads; qblib supplies keybinds, timers, sound and blips.
dependency 'qbtheme'
dependency 'qblib'
dependency 'qbcore'

shared_script '@qblib/init.lua'
shared_script '@qbcore/init.lua'

shared_scripts {
    'config.lua',
    'shared/calls.lua',
}

-- Explicit, never globbed -- alphabetic glob order would not respect the real
-- load-order dependencies here. store.lua defines the call registry every other
-- server file mutates and must load first; compat.lua registers the legacy
-- inbound events and must load last so it can call the real API above it.
server_scripts {
    'server/store.lua',
    'server/recipients.lua',
    'server/api.lua',
    -- ingress.lua builds the rate-limited, registered player-alert boundary on
    -- top of api.lua and must exist before compat.lua wires legacy events.
    'server/ingress.lua',
    'server/units.lua',
    'server/callbacks.lua',
    'server/compat.lua',
    -- Development commands, self-disabling unless Config.debug is on. Last, so
    -- every function it drives already exists.
    'server/dev.lua',
}

-- state.lua owns the local call cache every other client file reads; ui.lua
-- projects it through qblib's shared AppShell. sync.lua wires inbound events
-- and keybinds/exports are the entry points into everything above.
client_scripts {
    '@qbtheme/client/bridge.lua',
    'client/state.lua',
    'client/ui.lua',
    'client/theme.lua',
    'client/blip.lua',
    'client/sync.lua',
    'client/keybinds.lua',
    'client/exports.lua',
}
