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

h.test('the manifest globs assets with the trailing /* FiveM actually needs', function()
    local file = assert(io.open('fxmanifest.lua', 'r'))
    local manifest = file:read('*a')
    file:close()

    -- A bare trailing '**' matches nothing in FiveM's globber, so the bundle
    -- 404s and React never mounts -- with no error anywhere.
    h.assertTrue(manifest:find("'web/build/assets/%*%*/%*'") ~= nil,
        "assets must be globbed as 'web/build/assets/**/*'")
    -- Spelled out to the exact {z}/{x}/{y} depth, and asserted to actually
    -- match every tile on disk -- a pattern that silently matches nothing would
    -- leave the map blank with no error anywhere.
    h.assertTrue(manifest:find("'web/build/map/atlas/%*/%*/%*%.jpg'") ~= nil,
        "map tiles must be globbed at their real depth")

    local pipe = assert(io.popen('ls web/build/map/atlas/*/*/*.jpg 2>/dev/null | wc -l'))
    local matched = tonumber(pipe:read('*a'))
    pipe:close()

    local all = assert(io.popen("find web/build/map -name '*.jpg' | wc -l"))
    local total = tonumber(all:read('*a'))
    all:close()

    h.assertTrue(total > 0, 'sanity: tiles are vendored')
    h.assertEqual(matched, total, 'the manifest pattern must match every vendored tile')
end)

h.report('exports')
