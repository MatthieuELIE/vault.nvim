vim.api.nvim_create_user_command('VaultToggleTodo', function()
    require('vault').toggle_todo()
end, {})

vim.api.nvim_create_user_command('VaultToggleCheckbox', function()
    require('vault').toggle_checkbox()
end, {})
