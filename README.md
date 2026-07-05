# vault.nvim

A lightweight, project-specific task manager and diary plugin for Neovim.

## Features

- Toggle project-specific Markdown TODO list.
- Open today's diary note (`daily/YYYY/MM/YYYY-MM-DD.md`).
- Navigate to the previous/next diary day.
- Automatically handles directory creation based on git root or active project root.
- Simple, indentation-aware checkbox toggler.

## Installation

Using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
    'username/vault.nvim',
    keys = {
        { '<leader>vt', '<cmd>VaultToggleTodo<CR>', desc = 'Toggle Vault Todo' },
        { '<leader>vc', '<cmd>VaultToggleCheckbox<CR>', desc = 'Toggle Vault Checkbox' },
        { '<leader>vd', '<cmd>VaultToggleDiary<CR>', desc = 'Toggle Vault Diary' },
        { '<leader>vn', '<cmd>VaultDiaryNext<CR>', desc = 'Next Vault Diary Day' },
        { '<leader>vp', '<cmd>VaultDiaryPrev<CR>', desc = 'Previous Vault Diary Day' },
    },
    opts = {}
}
```

## Configuration

You can customize the base path of your vault by setting the `VAULT_PATH` environment variable. By default, it uses `~/vault`.

```lua
opts = {
    vault_path  = '~/vault',        -- or set $VAULT_PATH
    todos_path  = '~/vault/todos',  -- default: vault_path
    daily_path  = '~/vault/daily',  -- default: vault_path/daily
    split       = 'vsplit',         -- 'split' for horizontal
    keys = {
        toggle_todo     = '<leader>vt',
        toggle_checkbox = '<leader>vc',
        toggle_diary    = '<leader>vd',
        diary_next      = '<leader>vn',
        diary_prev      = '<leader>vp',
    },
}
```
