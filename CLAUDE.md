# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

vault.nvim is a lightweight Neovim plugin that implements a project-specific
TODO manager and diary. Logic is split across four modules under `lua/vault/`
(see Architecture below); there is no `plugin/` bootstrap file, so the plugin
is entirely driven by `require('vault').setup(opts)`.

## Commands

Tests use plenary.nvim's busted-style runner. Plenary is not vendored in this repo —
CI checks it out to `dependencies/plenary.nvim`, and `tests/minimal_init.lua` adds
both `.` and `dependencies/plenary.nvim` to the runtimepath. Locally, plenary just
needs to already be on your Neovim runtimepath (e.g. installed globally via your
plugin manager) — don't clone it into `dependencies/`, that's only for CI.

Run the suite:

```sh
nvim --headless -c "PlenaryBustedDirectory tests/ {minimal_init = 'tests/minimal_init.lua'}" -c "qa"
```

Run a single test file (there's only one, `tests/vault_spec.lua`) — `PlenaryBustedFile`
doesn't accept the inline `{minimal_init = ...}` table, so pass it via `-u` instead:

```sh
nvim --headless -u tests/minimal_init.lua -c "PlenaryBustedFile tests/vault_spec.lua" -c "qa"
```

Lint and format (both enforced in CI, see `.github/workflows/ci.yml`):

```sh
luacheck .
stylua --check .   # drop --check to auto-format
```

Formatting rules are in `.stylua.toml` (4-space indent, single quotes preferred,
120 column width, always-parenthesized calls).

## Code style

- Prefer explicit variable names over single-letter abbreviations, even in
  small local functions (e.g. `year`, `month`, `day` rather than `y`, `m`, `d`).

## Testing

- Structure each test as Arrange-Act-Assert: set up state/stubs, invoke the
  function under test, then group all `assert.*` calls at the end, separated
  from the arrange/act code by a blank line. Don't interleave assertions with
  setup or intermediate variable extraction.

## Architecture

Logic is split into four modules under `lua/vault/`, in dependency order
(`config` ← `buffer` ← `notes` ← `init`, no cycles):

- **`config.lua`** — owns the single module-level state table (`state.vault`,
  `state.split_cmd`, `state.todos_root`, `state.daily_root`, `state.date_format`,
  `state.templates_path`, `state.template_filenames`), exposed as `M.state`, plus
  the config-merging half of `setup(opts)`. Path resolution order:
  `opts.vault_path` > `$VAULT_PATH` env var > `~/vault`, with `todos_path`/
  `daily_path` independently overridable (defaulting to under `vault_path`).
  `buffer.lua` and `notes.lua` both read `config.state` directly rather than
  going through `init.lua`, to avoid a circular require.
- **`buffer.lua`** — `M.open_or_close(path, note_type)` is the shared toggle
  primitive behind todos and diary. If the target file is already open in a
  buffer, it saves it and closes all windows showing it, then wipes the buffer
  (closing = toggle off). Otherwise it `mkdir -p`s the parent dir and opens the
  file in a new split (toggle on). Save and window-close failures abort the
  close path and `vim.notify` a warning instead of silently discarding content
  — preserve this behavior when touching this function. Exception: if the
  window showing the buffer is the only window left in Neovim, `nvim_win_close`
  cannot close it (`E444`), so it switches that window to its alternate buffer
  (or a fresh empty buffer) instead of closing it — this is what makes
  `split = 'edit'` (which reuses the current window instead of opening a split)
  toggle off correctly. For `note_type == 'daily'`, it also closes any other
  currently-open diary note first (scanning all loaded buffers, not just the
  current one, via `M.diary_date_str_from_bufname`) before opening the
  requested date, so only one diary note is ever open at a time; this does not
  apply to todos, where multiple projects' `todos.md` open at once is
  legitimate.
- **`notes.lua`** — the todo and diary feature functions, built on top of
  `buffer.open_or_close`:
  - **`M.get_project_root()`** — derives the current project name from the
    nearest `.git` upward from cwd (falling back to cwd itself), used to
    namespace todo files per project: `<todos_root>/<project_name>/todos.md`.
  - **`M.toggle_diary(date_str)`** — resolves an optional `YYYY-MM-DD` argument
    (or defaults to today) into `<daily_root>/YYYY/MM/DD-MM-YYYY.md`.
    Invalid/unparseable date strings silently fall back to today rather than
    erroring.
  - **`M.toggle_checkbox()`** — only acts when the current buffer name ends in
    `todos.md`; toggles a leading `- [ ]`/`- [x]` on the current line, adding
    the checkbox prefix if absent, preserving indentation.
  - **`M.search_todos(query)`** — cross-project todo search, preferring
    Telescope, then fzf-lua, then falling back to a quickfix-list grep.
- **`init.lua`** — thin entry point. Re-exports the `notes.lua` public API
  unchanged (so `require('vault').toggle_todo()` etc. keeps working), and
  `M.setup(opts)` calls `config.setup(opts)` then registers the
  `VaultToggleTodo`, `VaultToggleCheckbox`, `VaultToggleDiary` (accepts an
  optional date arg), `VaultDiaryNext`/`VaultDiaryPrev`/`VaultDiaryGoto`, and
  `VaultSearchTodos` user commands, sets keymaps (defaults
  `<leader>vt`/`<leader>vc`/`<leader>vd`/`<leader>vn`/`<leader>vp`/`<leader>vg`/
  `<leader>vs`, overridable via `opts.keys`), and buffer-locally maps the
  checkbox toggle only inside `<vault_path>/*/todos.md` buffers via a
  `BufEnter` autocommand.

Tests stub `vim.notify`, `vim.api.nvim_win_close`, `vim.cmd`, and `os.date` per-case
to exercise failure paths (save failure, window-close failure, invalid dates)
without touching the real filesystem beyond a per-test temp vault dir.
