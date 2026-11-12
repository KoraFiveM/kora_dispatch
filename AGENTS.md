# kora_dispatch agent guide

`kora_dispatch` is a job-agnostic Kora dispatch resource: a server-authoritative call lifecycle, a keyboard-driven alert feed, and a `kora_lib` AppShell tablet with a rendered map. Layout: `fxmanifest.lua`, `config.lua`, `shared/calls.lua` (pure call helpers), `server/` (store, recipients, api exports, ingress, units, callbacks, compat, dev commands), `client/` (state, ui, theme, blips, sync, keybinds, exports), `web/build/map/` (served map tiles; the rest of `web/` is not loaded at runtime), `test/` (offline Lua smoke tests) and `tests/` (kora_qa feature files).

## Documentation

User-facing documentation lives in `docs/` (Markdown, published via the Kora Docusaurus site, kora_docs_next). Read `docs/index.md` first (overview plus a documentation map). Layout: `index.md` (hub), `installation.md`, `how-to-use.md` (guides and behaviour), `commands.md`, `api/` (`index.md`, `server-api.md`, `ingress.md`, `client-presentation.md`: every export with signatures and payload fields), and topic pages (`configuration.md`, `events.md`, `ui.md`, `map.md`, `compatibility.md`, `testing.md`, `troubleshooting.md`). Update the page that owns the topic; export changes go in `docs/api/`.

Feature and behaviour changes must update the matching docs in the same change. When you add, change, or remove a feature, config option, command, export, event, item, permission, or database table/column, update the matching page in `docs/` in the same change. Keep docs accurate to the code; do not document behaviour that does not exist.

Docs rules: plain Markdown with `title`/`sidebar_position` front matter (no `id`/`slug`), relative links only between docs pages, assets inside `docs/`, fenced code blocks with a language, and no raw `<`, `>`, `{`, `}` outside code (pages are parsed as MDX). The release version comes from `fxmanifest.lua`'s `version` field.
