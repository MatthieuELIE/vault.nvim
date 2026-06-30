local M = {}

local vault = vim.fn.expand(vim.env.VAULT_PATH or '~/vault')
local split_cmd = 'vsplit'
local todos_root = vault
local daily_root = vault .. '/daily'

M.get_project_root = function()
    local found = vim.fs.find('.git', { upward = true, path = vim.fn.getcwd() })[1]
    local root = found and vim.fs.dirname(found) or vim.fn.getcwd()
    return vim.fn.fnamemodify(root, ':t')
end

local function open_or_close(path)
    vim.notify('LOCAL VERSION')
    local bufnr = vim.fn.bufnr(path)
    if bufnr ~= -1 then
        vim.api.nvim_buf_call(bufnr, function()
            vim.cmd('silent! write')
        end)

        if vim.bo[bufnr].modified then
            vim.notify('vault.nvim: could not save ' .. vim.fn.fnamemodify(path, ':t'), vim.log.levels.WARN)
            return
        end

        for _, win in ipairs(vim.fn.win_findbuf(bufnr)) do
            pcall(vim.api.nvim_win_close, win, false)
        end

        vim.api.nvim_buf_delete(bufnr, {})
        return
    end
    vim.fn.mkdir(vim.fn.fnamemodify(path, ':h'), 'p')
    vim.cmd(split_cmd .. ' ' .. vim.fn.fnameescape(path))
end

M.toggle_todo = function()
    open_or_close(todos_root .. '/' .. M.get_project_root() .. '/todos.md')
end

M.toggle_diary = function(date_str)
    local t = os.time()
    if date_str and date_str ~= '' then
        local y, m, d = date_str:match('^(%d%d%d%d)-(%d%d)-(%d%d)$')
        if y then
            t = os.time({ year = tonumber(y), month = tonumber(m), day = tonumber(d) })
        end
    end
    open_or_close(
        daily_root .. '/' .. os.date('%Y', t) .. '/' .. os.date('%m', t) .. '/' .. os.date('%d-%m-%Y', t) .. '.md'
    )
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
        vim.api.nvim_set_current_line(line:match('^(%s*)') .. '- [ ] ' .. line:gsub('^%s*', ''))
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
    if opts.todos_path then
        todos_root = vim.fn.expand(opts.todos_path)
    end
    if opts.daily_path then
        daily_root = vim.fn.expand(opts.daily_path)
    end

    vim.api.nvim_create_user_command('VaultToggleTodo', M.toggle_todo, { force = true })
    vim.api.nvim_create_user_command('VaultToggleCheckbox', M.toggle_checkbox, { force = true })
    vim.api.nvim_create_user_command('VaultToggleDiary', function(o)
        M.toggle_diary(o.args)
    end, { force = true, nargs = '?' })

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

    if keys.toggle_checkbox then
        vim.api.nvim_create_autocmd('BufEnter', {
            pattern = vault .. '/*/todos.md',
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
