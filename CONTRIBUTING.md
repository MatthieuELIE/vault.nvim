# Contributing

See [ARCHITECTURE.md](ARCHITECTURE.md) for how the code is organized.

## Running tests

Tests use plenary.nvim's busted-style runner. Plenary isn't vendored in this
repo — CI checks it out to `dependencies/plenary.nvim` (see
`.github/workflows/ci.yml`), and `tests/minimal_init.lua` adds both `.` and
`dependencies/plenary.nvim` to the runtimepath. Locally, plenary just needs to
already be on your Neovim runtimepath (e.g. installed globally via your
plugin manager) — don't clone it into `dependencies/`, that's CI-only.

Run the whole suite:

```sh
nvim --headless -c "PlenaryBustedDirectory tests/ {minimal_init = 'tests/minimal_init.lua'}" -c "qa"
```

Run the single test file (`tests/vault_spec.lua`) — `PlenaryBustedFile`
doesn't accept the inline `{minimal_init = ...}` table, so pass it via `-u`
instead:

```sh
nvim --headless -u tests/minimal_init.lua -c "PlenaryBustedFile tests/vault_spec.lua" -c "qa"
```

### Test style

Structure each test as Arrange-Act-Assert: set up state/stubs, invoke the
function under test, then group all `assert.*` calls at the end, separated
from the arrange/act code by a blank line. Don't interleave assertions with
setup or intermediate variable extraction.

## Lint and format

Both enforced in CI:

```sh
luacheck .
stylua --check .   # drop --check to auto-format
```

Formatting rules live in `.stylua.toml`: 4-space indent, single quotes
preferred, 120 column width, calls always parenthesized. Luacheck config is in
`.luacheckrc` (`vim` is the only allowed global; `os` is additionally allowed
in `tests/`).

## Code style

Prefer explicit variable names over single-letter abbreviations, even in
small local functions — e.g. `year`, `month`, `day` rather than `y`, `m`, `d`.

## CI

`.github/workflows/ci.yml` runs two jobs on every push/PR: `lint` (stylua
check + luacheck) and `test` (checks out plenary.nvim, sets up Neovim stable,
runs the full test directory).
