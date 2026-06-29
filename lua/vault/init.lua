local M = {}

local vault = vim.fn.expand(vim.env.VAULT_PATH or '~/vault')
local split_cmd = 'vsplit'

M.get_project_root = function()
    local found = vim.fs.find('.git', { upward = true, path = vim.fn.getcwd() })[1]
    local root = found and vim.fs.dirname(found) or vim.fn.getcwd()
    return vim.fn.fnamemodify(root, ':t')
end

local function open_or_close(path)
    for _, win in ipairs(vim.api.nvim_list_wins()) do
        local buf = vim.api.nvim_win_get_buf(win)
        if vim.api.nvim_buf_get_name(buf) == path then
            vim.api.nvim_buf_call(buf, function()
                vim.cmd('silent! write')
            end)
            if vim.bo[buf].modified then
                vim.notify('vault.nvim: could not save ' .. vim.fn.fnamemodify(path, ':t'), vim.log.levels.WARN)
                return
            end
            pcall(vim.api.nvim_win_close, win, false)
            vim.api.nvim_buf_delete(buf, {})
            return
        end
    end
    vim.fn.mkdir(vim.fn.fnamemodify(path, ':h'), 'p')
    vim.cmd(split_cmd .. ' ' .. vim.fn.fnameescape(path))
end

M.toggle_todo = function()
    open_or_close(vault .. '/' .. M.get_project_root() .. '/todos.md')
end

M.toggle_diary = function()
    open_or_close(vault .. '/daily/' .. os.date('%Y') .. '/' .. os.date('%m') .. '/' .. os.date('%Y-%m-%d') .. '.md')
end

M.toggle_checkbox = function()
    if not vim.api.nvim_buf_get_name(0):match('todos%.md$') then
        return
    end

    local line = vim.api.nvim_get_current_line()
    local indent, state, rest = line:match('^(%s*)%- %[([ x])%](.*)')

    if indent and state then
        local new_state = state == 'x' and ' ' or 'x'
        local new_line = string.format('%s- [%s]%s', indent, new_state, rest)
        vim.api.nvim_set_current_line(new_line)
    else
        local indent_only = line:match('^(%s*)')
        local new_line = indent_only .. '- [ ] ' .. line:gsub('^%s*', '')
        vim.api.nvim_set_current_line(new_line)
    end
end

M.setup = function(opts)
    opts = opts or {}
    if opts.vault_path then
        vault = vim.fn.expand(opts.vault_path)
    end
    if opts.split then
        split_cmd = opts.split
    end

    vim.api.nvim_create_user_command('VaultToggleTodo', M.toggle_todo, { force = true })
    vim.api.nvim_create_user_command('VaultToggleCheckbox', M.toggle_checkbox, { force = true })
    vim.api.nvim_create_user_command('VaultToggleDiary', M.toggle_diary, { force = true })

    local keys = vim.tbl_extend('force', {
        toggle_todo = '<leader>vt',
        toggle_checkbox = '<leader>vc',
        toggle_diary = '<leader>vd',
    }, opts.keys or {})

    if keys.toggle_todo then
        vim.keymap.set('n', keys.toggle_todo, M.toggle_todo, { noremap = true, desc = 'Toggle project todo' })
    end

    if keys.toggle_diary then
        vim.keymap.set('n', keys.toggle_diary, M.toggle_diary, { noremap = true, desc = 'Toggle today diary' })
    end

    vim.api.nvim_create_autocmd('BufEnter', {
        pattern = vault .. '/*/todos.md',
        callback = function(args)
            if keys.toggle_checkbox then
                vim.keymap.set(
                    'n',
                    keys.toggle_checkbox,
                    M.toggle_checkbox,
                    { noremap = true, buffer = args.buf, desc = 'Toggle markdown checkbox' }
                )
            end
        end,
    })
end

return M
