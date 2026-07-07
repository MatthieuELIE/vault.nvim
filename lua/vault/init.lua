local config = require('vault.config')
local notes = require('vault.notes')

local M = {}

M.get_project_root = notes.get_project_root
M.toggle_todo = notes.toggle_todo
M.toggle_checkbox = notes.toggle_checkbox
M.toggle_diary = notes.toggle_diary
M.diary_next_day = notes.diary_next_day
M.diary_prev_day = notes.diary_prev_day
M.diary_goto = notes.diary_goto
M.search_todos = notes.search_todos

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

    if keys.toggle_todo then
        vim.keymap.set('n', keys.toggle_todo, M.toggle_todo, { noremap = true, desc = 'Toggle project todo' })
    end

    if keys.toggle_diary then
        vim.keymap.set('n', keys.toggle_diary, M.toggle_diary, { noremap = true, desc = 'Toggle today diary' })
    end

    if keys.diary_next then
        vim.keymap.set('n', keys.diary_next, M.diary_next_day, { noremap = true, desc = 'Go to next diary day' })
    end

    if keys.diary_prev then
        vim.keymap.set('n', keys.diary_prev, M.diary_prev_day, { noremap = true, desc = 'Go to previous diary day' })
    end

    if keys.diary_goto then
        vim.keymap.set('n', keys.diary_goto, M.diary_goto, { noremap = true, desc = 'Go to a diary date' })
    end

    if keys.search_todos then
        vim.keymap.set(
            'n',
            keys.search_todos,
            M.search_todos,
            { noremap = true, desc = 'Search todos across projects' }
        )
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
