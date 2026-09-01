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

h.test('the manifest globs assets with the trailing /* FiveM actually needs', function()
    local file = assert(io.open('fxmanifest.lua', 'r'))
    local manifest = file:read('*a')
    file:close()

    -- A bare trailing '**' matches nothing in FiveM's globber, so the bundle
    -- 404s and React never mounts -- with no error anywhere.
    h.assertTrue(manifest:find("'web/build/assets/%*%*/%*'") ~= nil,
        "assets must be globbed as 'web/build/assets/**/*'")
    h.assertTrue(manifest:find("'web/build/map/%*%*/%*'") ~= nil,
        "map tiles must be globbed as 'web/build/map/**/*'")
end)

h.report('exports')
