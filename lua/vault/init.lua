local config = require('vault.config')
local notes = require('vault.notes')

local M = vim.tbl_extend('force', {}, notes)

M.setup = function(opts)
    opts = opts or {}
    config.setup(opts)

    vim.api.nvim_create_user_command('VaultToggleTodo', M.toggle_todo, { force = true })
    vim.api.nvim_create_user_command('VaultToggleCheckbox', M.toggle_checkbox, { force = true })
    vim.api.nvim_create_user_command('VaultToggleDiary', function(o)
        M.toggle_diary(o.args)
    end, { force = true, nargs = '?' })
    vim.api.nvim_create_user_command('VaultDiaryNext', M.diary_next_day, { force = true })
    vim.api.nvim_create_user_command('VaultDiaryPrev', M.diary_prev_day, { force = true })
    vim.api.nvim_create_user_command('VaultDiaryGoto', M.diary_goto, { force = true })
    vim.api.nvim_create_user_command('VaultSearchTodos', function(o)
        M.search_todos(o.args)
    end, { force = true, nargs = '?' })

    local keys = vim.tbl_extend('force', {
        toggle_todo = '<leader>vt',
        toggle_checkbox = '<leader>vc',
        toggle_diary = '<leader>vd',
        diary_next = '<leader>vn',
        diary_prev = '<leader>vp',
        diary_goto = '<leader>vg',
        search_todos = '<leader>vs',
    }, opts.keys or {})

    local keymap_specs = {
        { name = 'toggle_todo', fn = M.toggle_todo, desc = 'Toggle project todo' },
        { name = 'toggle_diary', fn = M.toggle_diary, desc = 'Toggle today diary' },
        { name = 'diary_next', fn = M.diary_next_day, desc = 'Go to next diary day' },
        { name = 'diary_prev', fn = M.diary_prev_day, desc = 'Go to previous diary day' },
        { name = 'diary_goto', fn = M.diary_goto, desc = 'Go to a diary date' },
        { name = 'search_todos', fn = M.search_todos, desc = 'Search todos across projects' },
    }
    for _, spec in ipairs(keymap_specs) do
        if keys[spec.name] then
            vim.keymap.set('n', keys[spec.name], spec.fn, { noremap = true, desc = spec.desc })
        end
    end

    if keys.toggle_checkbox then
        vim.api.nvim_create_autocmd('BufEnter', {
            pattern = config.state.vault .. '/*/todos.md',
            callback = function(args)
                vim.keymap.set(
                    'n',
                    keys.toggle_checkbox,
                    M.toggle_checkbox,
                    { noremap = true, buffer = args.buf, desc = 'Toggle markdown checkbox' }
                )
            end,
        })
    end
end

return M
