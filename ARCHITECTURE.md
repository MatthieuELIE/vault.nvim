# Architecture

For install/config docs see the [README](README.md). This is the internals
map for contributors.

## Module layout

Four modules under `lua/vault/`, in dependency order — each only requires the
ones before it, no cycles:

```
config.lua ← buffer.lua ← notes.lua ← init.lua
```

There's no `plugin/` bootstrap file; nothing runs until a user calls
`require('vault').setup(opts)`.

### `config.lua`

Owns the single module-level state table, `M.state`. Fields: `vault_path`,
`split`, `todos_root`, `daily_root`, `date_format`, `templates_path`,
`template_filenames`.

`vault_path` resolution order: `opts.vault_path` > `$VAULT_PATH` env var >
`~/vault`. `todos_root` and `daily_root` default to `vault_path` and
`vault_path/daily` respectively, but each can be overridden independently via
`opts.todos_path` / `opts.daily_path`. An empty or unresolvable path falls
back to the default and emits a `vim.notify` error rather than failing setup.

`buffer.lua` and `notes.lua` read `config.state` directly instead of going
through `init.lua`, to avoid a circular require.

### `buffer.lua`

`M.open_or_close(path, note_type)` is the toggle primitive shared by todos and
diary:

- If `path` is already open in a buffer: save it, close every window showing
  it, then wipe the buffer (toggle off).
- Otherwise: `mkdir -p` the parent dir, open `path` in a new split per
  `config.state.split`, and apply the template for `note_type` if the file
  didn't already exist on disk (toggle on).

Save and window-close failures abort the close path and `vim.notify` a
warning instead of silently discarding content — preserve this behavior when
touching this function.

One edge case: if the window showing the buffer is the *only* window in
Neovim, `nvim_win_close` raises `E444` (can't close the last window). The code
switches that window to its alternate buffer (or a fresh empty one) instead of
closing it. This is what makes `split = 'edit'` (reuse the current window
instead of splitting) toggle off correctly.

For `note_type == 'daily'`, `open_or_close` also closes any other currently
open diary note first — scanning all loaded buffers via
`M.diary_date_str_from_bufname`, not just the current one — so at most one
diary note is ever open at a time. This does *not* apply to todos: multiple
projects' `todos.md` open simultaneously is expected.

Template application (`apply_template`, private to this module) reads
`config.state.template_filenames[note_type]` and
`config.state.templates_path`; if either is unset, or the template file isn't
readable, it's a no-op and the note opens empty.

### `notes.lua`

The todo/diary/checkbox/search feature functions, built on
`buffer.open_or_close`:

- **`M.get_project_root()`** — walks upward from cwd for the nearest `.git`
  (falling back to cwd itself) and takes that directory's basename as the
  project name, used to namespace todo files:
  `<todos_root>/<project_name>/todos.md`. If the resolved name is empty (e.g.
  running from `/`), falls back to `'root'` and warns.
- **`M.toggle_diary(date_str)`** — resolves an optional `YYYY-MM-DD` argument
  (or defaults to today) to `<daily_root>/YYYY/MM/<formatted-date>.md`, where
  the filename is `os.date(config.state.date_format, ...)`. An
  invalid/unparseable date string silently falls back to today rather than
  erroring.
- **`M.toggle_checkbox()`** — only acts when the current buffer name ends in
  `todos.md`. Toggles a leading `- [ ]` / `- [x]` on the current line,
  preserving indentation, adding the checkbox prefix if the line doesn't have
  one yet.
- **`M.archive_todos()`** — only acts when the current buffer name ends in
  `todos.md`; a no-op otherwise. Splits the buffer's lines into checked
  (`- [x]`, any indentation) and the rest, in document order. If nothing is
  checked, `vim.notify`s an info and stops without touching the buffer or
  disk. Otherwise: sets the buffer to the remaining lines and saves it; if
  the save fails (buffer still `modified` afterwards), warns and aborts
  *before* touching `archive.md`, so a copy is never persisted to the
  archive without the removal being confirmed on disk first — same
  abort-on-save-failure principle as `buffer.close_buffer`. The archived
  lines are then appended to `archive.md` next to `todos.md` (project name
  taken from the parent directory of the path, not `get_project_root()`, so
  it's correct even for a `todos.md` outside the current cwd's project). A
  newly created `archive.md` is prefixed with a `# <project> Archive` title;
  entries are grouped under a `### YYYY-MM-DD` heading, reusing the last
  heading in the file if it already matches today instead of duplicating it.
  There's no tree-aware parsing: if a checked line has an unchecked
  sub-item (a more-indented `- [ ]` line right after it), the sub-item is
  left behind in `todos.md` rather than moved, and a single grouped
  `vim.notify` warning lists which archived items left one behind.
- **`M.search(input)`** — vault-wide search. `input`'s leading word is matched
  against a scope table (`SEARCH_SCOPES`: `todos` → `todos_root`/
  `*/todos.md`, `daily` → `daily_root`/`**/*.md`, default `all` →
  `vault_path`/`**/*.md`); if it matches, that word is consumed as the scope
  and the rest becomes the query, otherwise the whole input is the query and
  scope stays `all`. Prefers Telescope (`live_grep` scoped to the resolved
  dir/glob), otherwise falls back to a hand-rolled case-insensitive substring
  scan that populates the quickfix list. No fzf-lua support.
- `diary_next_day` / `diary_prev_day` shift the current (or, if not in a
  diary buffer, today's) date by ±1 day and re-run `toggle_diary`.
- `diary_goto` prompts via `vim.ui.input`, defaulting to the current diary
  buffer's date if in one, else today.

### `init.lua`

Thin entry point. Re-exports `notes.lua`'s public API unchanged (so
`require('vault').toggle_todo()` etc. keeps working after the split), and
`M.setup(opts)`:

1. Calls `config.setup(opts)`.
2. Registers user commands: `VaultToggleTodo`, `VaultToggleCheckbox`,
   `VaultArchiveTodos`, `VaultToggleDiary` (optional `YYYY-MM-DD` arg),
   `VaultDiaryNext`, `VaultDiaryPrev`, `VaultDiaryGoto`, `VaultSearch`
   (optional `[todos|daily] query` arg).
3. Sets keymaps (defaults `<leader>vt/vc/va/vd/vn/vp/vg/vs`), overridable
   per-key via `opts.keys`.
4. Buffer-locally maps the checkbox toggle and the todo archiver only inside
   `<vault_path>/*/todos.md` buffers, via a shared `BufEnter` autocommand
   iterating a small list of buffer-local specs — so neither keymap shadows
   anything in unrelated buffers.

## Tests

`tests/vault_spec.lua` stubs `vim.notify`, `vim.api.nvim_win_close`,
`vim.cmd`, `os.date`/`os.time`, and `vim.ui.input` per-case to exercise
failure paths (save failure, window-close failure, invalid dates, cancelled
prompts) without touching the real filesystem beyond a per-test temp vault
dir. See [CONTRIBUTING.md](CONTRIBUTING.md) for how to run them.
