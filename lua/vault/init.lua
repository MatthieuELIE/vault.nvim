local M = {}

local vault = vim.fn.expand(vim.env.VAULT_PATH or '~/vault')
local split_cmd = 'vsplit'

M.get_project_root = function()
    local path = vim.fn.getcwd()
    local markers = {
        '.git',
    }

    while path and path ~= '' do
        for _, marker in ipairs(markers) do
            local marker_path = path .. '/' .. marker
            if vim.fn.isdirectory(marker_path) == 1 or vim.fn.filereadable(marker_path) == 1 then
                return vim.fn.fnamemodify(path, ':t')
            end
        end

        local parent = vim.fn.fnamemodify(path, ':h')
        if parent == path then
            break
        end
        path = parent
    end

    return vim.fn.fnamemodify(vim.fn.getcwd(), ':t')
end

M.toggle_todo = function()
    local project = M.get_project_root()
    local path = vault .. '/' .. project .. '/todos.md'

    for _, win in ipairs(vim.api.nvim_list_wins()) do
        local buf = vim.api.nvim_win_get_buf(win)
        if vim.api.nvim_buf_get_name(buf) == path then
            vim.api.nvim_buf_call(buf, function()
                vim.cmd('silent! write')
            end)
            pcall(vim.api.nvim_win_close, win, false)
            vim.api.nvim_buf_delete(buf, {})
            return
        end
    end

    vim.fn.mkdir(vault .. '/' .. project, 'p')
    vim.cmd(split_cmd .. ' ' .. vim.fn.fnameescape(path))
end

M.toggle_checkbox = function()
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

    vim.api.nvim_create_user_command('VaultToggleTodo', function()
        M.toggle_todo()
    end, {})

    vim.api.nvim_create_user_command('VaultToggleCheckbox', function()
        M.toggle_checkbox()
    end, {})

    local default_keys = {
        toggle_todo = '<leader>td',
        toggle_checkbox = '<leader>tc',
    }
    local keys = vim.tbl_deep_extend('force', default_keys, opts.keys or {})

    if keys.toggle_todo then
        vim.keymap.set('n', keys.toggle_todo, M.toggle_todo, { desc = 'Toggle project todo' })
    end

    vim.api.nvim_create_autocmd('BufEnter', {
        pattern = vault .. '/*/todos.md',
        callback = function(args)
            if keys.toggle_checkbox then
                vim.keymap.set(
                    'n',
                    keys.toggle_checkbox,
                    M.toggle_checkbox,
                    { buffer = args.buf, desc = 'Toggle markdown checkbox' }
                )
            end
        end,
    })
end

return M
