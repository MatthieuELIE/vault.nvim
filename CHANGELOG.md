# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2026-07-09

### Added

- Project-specific TODO list toggle (`VaultToggleTodo`), namespaced per git project root.
- Checkbox toggler (`VaultToggleCheckbox`) for todo lines.
- Daily diary note toggle (`VaultToggleDiary`), with previous/next day navigation
  (`VaultDiaryNext`/`VaultDiaryPrev`) and jump-to-date (`VaultDiaryGoto`).
- Cross-project todo search (`VaultSearchTodos`), using Telescope or fzf-lua if
  installed, falling back to the quickfix list.
- Configurable templates for todos and daily notes.
- Configurable diary filename date format.

### Fixed

- `split = 'edit'` toggle-off when it is the last window.
- Only one diary note open at a time, even when mixing direct toggle and navigation.
- Hardened path resolution, project root detection, and directory creation.

### Changed

- Split `init.lua` into `config`/`buffer`/`notes`/`init` modules.
