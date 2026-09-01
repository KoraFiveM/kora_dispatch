-- The published export surface. A job resource writes against these names, so an
-- accidental rename is a breaking change for every consumer -- worth a test that
-- fails here rather than at someone else's call site.
local h = dofile('test/harness.lua')
local mocks = dofile('test/mocks.lua'); local net = mocks.install()
dofile('config.lua')
dofile('shared/calls.lua')
dofile('server/store.lua')
dofile('server/recipients.lua')
dofile('server/api.lua')

local EXPECTED = {
    'createCall', 'updateCall', 'closeCall',
    'getCall', 'getCalls', 'setUnitState', 'getOnDutyUnits',
}

h.test('every documented server export is registered', function()
    for _, name in ipairs(EXPECTED) do
        h.assertTrue(type(net.registeredExports[name]) == 'function',
            ('exports.qbdispatch:%s must exist'):format(name))
    end
end)

h.test('no undocumented server export leaks out', function()
    local expected = {}
    for _, name in ipairs(EXPECTED) do expected[name] = true end

    for name in pairs(net.registeredExports) do
        h.assertTrue(expected[name], ('unexpected export %q -- document it or make it internal'):format(name))
    end
end)

h.test('the server surface is documented in docs/index.md', function()
    local file = assert(io.open('docs/index.md', 'r'))
    local docs = file:read('*a')
    file:close()

    for _, name in ipairs(EXPECTED) do
        h.assertTrue(docs:find('exports.qbdispatch:' .. name, 1, true) ~= nil,
            ('exports.qbdispatch:%s is missing from docs/index.md'):format(name))
    end
end)

h.test('client-only exports are not published on the server', function()
    -- setTheme/setUiOptions are per-player presentation and live in
    -- client/exports.lua. Publishing them server-side would let one player's
    -- call recolour everybody's UI.
    for _, name in ipairs({ 'setTheme', 'setUiOptions', 'setTablet', 'getService' }) do
        h.assertEqual(net.registeredExports[name], nil,
            ('%s is a client export and must not exist on the server'):format(name))
    end
end)

h.test('the manifest lists every lua file, and every listed file exists', function()
    local file = assert(io.open('fxmanifest.lua', 'r'))
    local manifest = file:read('*a')
    file:close()

    local listed = {}
    for path in manifest:gmatch("'((client)/[%w_/]+%.lua)'") do listed[path] = true end
    for path in manifest:gmatch("'((server)/[%w_/]+%.lua)'") do listed[path] = true end
    for path in manifest:gmatch("'((shared)/[%w_/]+%.lua)'") do listed[path] = true end

    for _, dir in ipairs({ 'client', 'server', 'shared' }) do
        local pipe = assert(io.popen(('ls %s/*.lua 2>/dev/null'):format(dir)))
        for path in pipe:lines() do
            h.assertTrue(listed[path], ('%s exists but is not loaded by fxmanifest.lua'):format(path))
            listed[path] = nil
        end
        pipe:close()
    end

    for path in pairs(listed) do
        h.assertTrue(false, ('fxmanifest.lua loads %s, which does not exist'):format(path))
    end
end)

h.test('dev commands are admin-gated and self-disable without Config.debug', function()
    -- /dispatchtest can put arbitrary text and coordinates in front of every
    -- on-duty player of a service. It must never be reachable by an ordinary
    -- player, and must not exist at all on a server that has not opted in.
    local file = assert(io.open('server/dev.lua', 'r'))
    local source = file:read('*a')
    file:close()

    h.assertTrue(source:find('if not Config.debug then return end', 1, true) ~= nil,
        'the whole file must bail before registering anything when debug is off')

    -- Every command in the file carries a permission gate.
    local commands, gated = 0, 0
    for _ in source:gmatch("QB%.commands%.add%(") do commands = commands + 1 end
    for _ in source:gmatch("permission = 'admin'") do gated = gated + 1 end

    h.assertTrue(commands > 0, 'sanity: the file registers commands')
    h.assertEqual(gated, commands, 'every dev command must be admin-gated')

    -- Delegated to qblib rather than hand-rolled. A bare
    -- IsPlayerAceAllowed(src, 'qbcore.admin') refuses an admin who holds the
    -- bare `group.admin` principal -- which is how this framework's own
    -- server.cfg grants it -- and ignores level ranking, so a 'god' would fail
    -- an 'admin' gate.
    h.assertTrue(source:find('QB.permissions.hasLevel', 1, true) ~= nil,
        'the permission check must go through qblib, not a hand-rolled ACE test')
    -- Comment lines stripped first: the rationale above mentions the native by
    -- name, and matching prose would make this assertion unfixable.
    local code = source:gsub('%-%-[^\n]*', '')
    h.assertTrue(code:find('IsPlayerAceAllowed(', 1, true) == nil,
        'no hand-rolled ACE check should remain in the code')
end)

h.test('map tiles opt out of Preflight image clamping', function()
    -- Tailwind's Preflight ships `img,video{max-width:100%;height:auto}`, and an
    -- inline `width` does NOT override `max-width` -- they are separate
    -- properties. Without max-w-none every tile is clamped to the container's
    -- width while its position keeps spreading with the zoom, tearing the map
    -- into strips pinned to the edges. It is invisible at low zoom, where tiles
    -- are smaller than the container and nothing clamps, which is exactly what
    -- makes it worth a test.
    local file = assert(io.open('web/src/components/MapView.tsx', 'r'))
    local source = file:read('*a')
    file:close()

    local tileImg = source:match('<img.-/>')
    h.assertTrue(tileImg ~= nil, 'sanity: the tile layer renders an img')
    h.assertTrue(tileImg:find('max-w-none', 1, true) ~= nil,
        'the tile image must opt out of Preflight max-width clamping')

    -- And the utility has to survive into the built stylesheet, not just the
    -- source: Tailwind only emits classes it can see.
    local css = assert(io.popen("cat web/build/assets/*.css 2>/dev/null"))
    local built = css:read('*a')
    css:close()
    h.assertTrue(built:find('.max-w-none{max-width:none}', 1, true) ~= nil,
        'max-w-none must be present in the built CSS')
end)

h.test('the manifest globs assets with the trailing /* FiveM actually needs', function()
    local file = assert(io.open('fxmanifest.lua', 'r'))
    local manifest = file:read('*a')
    file:close()

    -- A bare trailing '**' matches nothing in FiveM's globber, so the bundle
    -- 404s and React never mounts -- with no error anywhere.
    h.assertTrue(manifest:find("'web/build/assets/%*%*/%*'") ~= nil,
        "assets must be globbed as 'web/build/assets/**/*'")
    -- The tile tree is nested ({z}/{x}/{y}.jpg), so it needs the RECURSIVE
    -- '**/*' form -- the one CFX's own resources use for nested trees
    -- ('nui/**/*', 'panel/**/*', 'web/public/**/*').
    --
    -- A multi-level 'atlas/*/*/*.jpg' matches under a shell but NOT under
    -- FiveM's globber, and was shipped here once: every tile came back a broken
    -- image with nothing in any log. Asserting the literal pattern is the only
    -- honest check available offline -- counting shell matches (which the
    -- previous version of this test did) proves nothing about FiveM and gave
    -- false confidence.
    h.assertTrue(manifest:find("'web/build/map/%*%*/%*'") ~= nil,
        "map tiles need the recursive '**/*' glob; a multi-level '*/*/*' matches nothing in FiveM")

    local tiles = assert(io.popen("find web/build/map -name '*.jpg' | wc -l"))
    local total = tonumber(tiles:read('*a'))
    tiles:close()
    h.assertTrue(total > 0, 'sanity: basemap tiles are vendored')
end)

h.report('exports')
