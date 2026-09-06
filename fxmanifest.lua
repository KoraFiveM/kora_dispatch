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
    'server/units.lua',
    'server/callbacks.lua',
    'server/compat.lua',
    -- Development commands, self-disabling unless Config.debug is on. Last, so
    -- every function it drives already exists.
    'server/dev.lua',
}

-- state.lua owns the local call cache every other client file reads; ui.lua
-- registers the NUI bridge everything pushes through. sync.lua wires the
-- inbound events and must come after both; keybinds/exports come last because
-- they are entry points into everything above.
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

ui_page 'web/build/index.html'

files {
    'web/build/index.html',
    -- A bare trailing '**' does NOT match files in FiveM's resource globber --
    -- it needs the '/*'. With 'web/build/assets/**' the hashed JS/CSS bundles
    -- are silently never served: index.html loads, its <script> 404s, React
    -- never mounts, and the UI is simply invisible with no error anywhere.
    'web/build/assets/**/*',
    -- Vendored basemap tile pyramids, served to the NUI as
    -- nui://qbdispatch/web/build/map/{style}/{z}/{x}/{y}.{ext} -- 'mainmap'
    -- (the in-game pause map, z1-z3, .png) is what Config.map ships pointing
    -- at; 'atlas' (the stylised tourist map, z0-z3, .jpg) is kept as the
    -- documented alternative. See docs/map.md.
    --
    -- '**/*' is the RECURSIVE form, and the only one FiveM honours for a nested
    -- tree: CFX's own resources ship 'nui/**/*', 'panel/**/*' and
    -- 'web/public/**/*' for exactly this. A multi-level 'atlas/*/*/*.jpg' has no
    -- precedent anywhere in the server's own resources and does NOT match --
    -- that spelling was tried here and served nothing, leaving every tile as a
    -- broken image with no error to find. A single '*' is only good for one
    -- segment, as in CFX's own 'html/vendor/*.css'.
    'web/build/map/**/*',
}
