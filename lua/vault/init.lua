local M = {}

local DEFAULT_VAULT_PATH = '~/vault'

local function resolve_vault_path(path, source)
    if path == nil then
        return vim.fn.expand(DEFAULT_VAULT_PATH)
    end

    local expanded = path ~= '' and vim.fn.expand(path) or ''
    if expanded ~= '' then
        return expanded
    end

    vim.notify(
        string.format("vault.nvim: %s is empty or invalid, falling back to '%s'", source, DEFAULT_VAULT_PATH),
        vim.log.levels.ERROR
    )
    return vim.fn.expand(DEFAULT_VAULT_PATH)
end

local DEFAULT_TEMPLATE_FILENAMES = {
    todos = 'Todo Template.md',
    daily = 'Daily Note Template.md',
}

local state = {
    split_cmd = 'vsplit',
    template_filenames = DEFAULT_TEMPLATE_FILENAMES,
}
state.vault = resolve_vault_path(vim.env.VAULT_PATH, 'VAULT_PATH')
state.todos_root = state.vault
state.daily_root = state.vault .. '/daily'

local function apply_template(note_type)
    local filename = note_type and state.template_filenames[note_type]
    if not filename or not state.templates_path then
        return
    end

    local template_path = state.templates_path .. '/' .. filename
    if vim.fn.filereadable(template_path) == 0 then
        return
    end

    vim.api.nvim_buf_set_lines(0, 0, -1, false, vim.fn.readfile(template_path))
end

M.get_project_root = function()
    local found = vim.fs.find('.git', { upward = true, path = vim.fn.getcwd() })[1]
    local root = found and vim.fs.dirname(found) or vim.fn.getcwd()
    local name = vim.fn.fnamemodify(root, ':t')

    if name == '' then
        vim.notify(
            "vault.nvim: could not determine a project name from '" .. root .. "', using 'root'",
            vim.log.levels.WARN
        )
        return 'root'
    end

    return name
end

local function close_buffer(bufnr)
    local name = vim.api.nvim_buf_get_name(bufnr)
    vim.api.nvim_buf_call(bufnr, function()
        vim.cmd('silent! write')
    end)

    if vim.bo[bufnr].modified then
        vim.notify('vault.nvim: could not save ' .. vim.fn.fnamemodify(name, ':t'), vim.log.levels.WARN)
        return false
    end

    local all_closed = true
    for _, win in ipairs(vim.fn.win_findbuf(bufnr)) do
        if #vim.api.nvim_list_wins() == 1 then
            vim.api.nvim_win_call(win, function()
                vim.cmd('silent! buffer #')
                if vim.api.nvim_win_get_buf(win) == bufnr then
                    vim.cmd('enew')
                end
            end)
        else
            local ok = pcall(vim.api.nvim_win_close, win, false)
            if not ok then
                all_closed = false
            end
        end
    end

    if not all_closed then
        vim.notify(
            'vault.nvim: could not close all windows for ' .. vim.fn.fnamemodify(name, ':t'),
            vim.log.levels.WARN
        )
        return false
    end

    vim.api.nvim_buf_delete(bufnr, { force = true })
    return true
end

local function diary_date_str_from_bufname(name)
    local day, month, year = name:match('(%d%d)%-(%d%d)%-(%d%d%d%d)%.md$')
    if not day then
        return nil
    end
    return string.format('%s-%s-%s', year, month, day)
end

local function find_other_open_diary_bufnr(date_str)
    for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_loaded(bufnr) then
            local buf_date_str = diary_date_str_from_bufname(vim.api.nvim_buf_get_name(bufnr))
            if buf_date_str and buf_date_str ~= date_str then
                return bufnr
            end
        end
    end
    return nil
end

local function open_or_close(path, note_type)
    path = vim.fs.normalize(path)
    local bufnr = vim.fn.bufnr(path)
    if bufnr ~= -1 then
        close_buffer(bufnr)
        return
    end

    if note_type == 'daily' then
        local target_date_str = diary_date_str_from_bufname(path)
        local other_bufnr = target_date_str and find_other_open_diary_bufnr(target_date_str)
        if other_bufnr and not close_buffer(other_bufnr) then
            return
        end
    end

    local parent = vim.fn.fnamemodify(path, ':h')
    if vim.fn.isdirectory(parent) == 0 then
        local ok, created = pcall(vim.fn.mkdir, parent, 'p')
        if not ok or created == 0 then
            vim.notify('vault.nvim: could not create directory ' .. parent, vim.log.levels.ERROR)
            return
        end
    end

    vim.cmd(state.split_cmd .. ' ' .. vim.fn.fnameescape(path))
    if vim.fn.filereadable(path) == 0 then
        apply_template(note_type)
    end
end

M.toggle_todo = function()
    open_or_close(state.todos_root .. '/' .. M.get_project_root() .. '/todos.md', 'todos')
end

local function parse_date(date_str)
    local year, month, day = date_str:match('^(%d%d%d%d)-(%d%d)-(%d%d)$')
    if not year then
        return nil
    end
    return os.time({ year = tonumber(year), month = tonumber(month), day = tonumber(day) })
end

local function diary_path(time)
    local date_table = os.date('*t', time)
    return state.daily_root
        .. string.format(
            '/%04d/%02d/%02d-%02d-%04d.md',
            date_table.year,
            date_table.month,
            date_table.day,
            date_table.month,
            date_table.year
        )
end

M.toggle_diary = function(date_str)
    local time = os.time()
    if date_str and date_str ~= '' then
        time = parse_date(date_str) or time
    end
    open_or_close(diary_path(time), 'daily')
end

local function get_current_diary_date_str()
    return diary_date_str_from_bufname(vim.api.nvim_buf_get_name(0))
end

local function navigate_diary(offset_days)
    local current = get_current_diary_date_str()
    local base_time = current and parse_date(current) or os.time()
    M.toggle_diary(os.date('%Y-%m-%d', base_time + offset_days * 86400))
end

M.diary_next_day = function()
    navigate_diary(1)
end

M.diary_prev_day = function()
    navigate_diary(-1)
end

M.toggle_checkbox = function()
    if not vim.api.nvim_buf_get_name(0):match('todos%.md$') then
        return
    end

    local line = vim.api.nvim_get_current_line()
    local indent, content = line:match('^(%s*)(.*)')
    local checkbox_state, rest = content:match('^%- %[([ x])%](.*)')

    if checkbox_state then
        local new_state = checkbox_state == 'x' and ' ' or 'x'
        local new_line = string.format('%s- [%s]%s', indent, new_state, rest)
        vim.api.nvim_set_current_line(new_line)
    else
        vim.api.nvim_set_current_line(indent .. '- [ ] ' .. content)
    end
end

M.setup = function(opts)
    opts = opts or {}
    if opts.vault_path then
        state.vault = resolve_vault_path(opts.vault_path, 'vault_path')
        state.todos_root = state.vault
        state.daily_root = state.vault .. '/daily'
    end
    if opts.split then
        state.split_cmd = opts.split
    end
    if opts.todos_path then
        state.todos_root = vim.fn.expand(opts.todos_path)
    end
    if opts.daily_path then
        state.daily_root = vim.fn.expand(opts.daily_path)
    end
    if opts.templates_path then
        state.templates_path = vim.fn.expand(opts.templates_path)
    end
    if opts.templates then
        state.template_filenames = vim.tbl_extend('force', DEFAULT_TEMPLATE_FILENAMES, opts.templates)
    end

    vim.api.nvim_create_user_command('VaultToggleTodo', M.toggle_todo, { force = true })
    vim.api.nvim_create_user_command('VaultToggleCheckbox', M.toggle_checkbox, { force = true })
    vim.api.nvim_create_user_command('VaultToggleDiary', function(o)
        M.toggle_diary(o.args)
    end, { force = true, nargs = '?' })
    vim.api.nvim_create_user_command('VaultDiaryNext', M.diary_next_day, { force = true })
    vim.api.nvim_create_user_command('VaultDiaryPrev', M.diary_prev_day, { force = true })

    local keys = vim.tbl_extend('force', {
        toggle_todo = '<leader>vt',
        toggle_checkbox = '<leader>vc',
        toggle_diary = '<leader>vd',
        diary_next = '<leader>vn',
        diary_prev = '<leader>vp',
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

    if keys.toggle_checkbox then
        vim.api.nvim_create_autocmd('BufEnter', {
            pattern = state.vault .. '/*/todos.md',
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
