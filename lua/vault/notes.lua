local config = require('vault.config')
local buffer = require('vault.buffer')

local M = {}

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

M.toggle_todo = function()
    buffer.open_or_close(config.state.todos_root .. '/' .. M.get_project_root() .. '/todos.md', 'todos')
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
    return config.state.daily_root
        .. string.format('/%04d/%02d/', date_table.year, date_table.month)
        .. os.date(config.state.date_format, os.time(date_table))
        .. '.md'
end

M.toggle_diary = function(date_str)
    local time = os.time()
    if date_str and date_str ~= '' then
        time = parse_date(date_str) or time
    end
    buffer.open_or_close(diary_path(time), 'daily')
end

local function get_current_diary_date_str()
    return buffer.diary_date_str_from_bufname(vim.api.nvim_buf_get_name(0))
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

M.diary_goto = function()
    local default = get_current_diary_date_str() or os.date('%Y-%m-%d', os.time())
    vim.ui.input({ prompt = 'Diary date (YYYY-MM-DD): ', default = default }, function(input)
        if input then
            M.toggle_diary(input)
        end
    end)
end

local SEARCH_SCOPES = {
    todos = {
        dir = function()
            return config.state.todos_root
        end,
        glob = '*/todos.md',
    },
    daily = {
        dir = function()
            return config.state.daily_root
        end,
        glob = '**/*.md',
    },
    all = {
        dir = function()
            return config.state.vault_path
        end,
        glob = '**/*.md',
    },
}

local function scope_files(scope)
    local files = vim.fn.glob(scope.dir() .. '/' .. scope.glob, false, true)
    table.sort(files)
    return files
end

local function search_fallback(query, scope)
    local items = {}
    for _, path in ipairs(scope_files(scope)) do
        local lnum = 0
        for line in io.lines(path) do
            lnum = lnum + 1
            if line:lower():find(query:lower(), 1, true) then
                table.insert(items, { filename = path, lnum = lnum, text = line })
            end
        end
    end

    vim.fn.setqflist({}, ' ', { title = 'Vault search: ' .. query, items = items })
    vim.cmd('copen')
end

M.search = function(input)
    input = input or ''
    local scope_name, rest = input:match('^(%a+)%s*(.*)$')
    local scope = scope_name and SEARCH_SCOPES[scope_name]
    if scope then
        input = rest
    else
        scope_name = 'all'
        scope = SEARCH_SCOPES.all
    end

    local function run(resolved_query)
        if not resolved_query or resolved_query == '' then
            return
        end

        local ok_telescope, telescope_builtin = pcall(require, 'telescope.builtin')
        if ok_telescope then
            telescope_builtin.live_grep({
                search_dirs = { scope.dir() },
                glob_pattern = scope.glob,
                default_text = resolved_query,
            })
            return
        end

        search_fallback(resolved_query, scope)
    end

    if input ~= '' then
        run(input)
    else
        vim.ui.input({ prompt = 'Search vault (' .. scope_name .. '): ' }, run)
    end
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

local function line_indent(line)
    return #line:match('^%s*')
end

local function line_checkbox_state(line)
    return line:match('^%s*%- %[([ x])%]')
end

local function has_unchecked_child(lines, index)
    local indent = line_indent(lines[index])
    for offset = index + 1, #lines do
        local next_line = lines[offset]
        if line_indent(next_line) <= indent then
            return false
        end
        if line_checkbox_state(next_line) == ' ' then
            return true
        end
    end
    return false
end

local function append_to_archive(archive_path, project_name, archived_lines)
    local existing = vim.fn.filereadable(archive_path) == 1 and vim.fn.readfile(archive_path) or nil
    local today = os.date('%Y-%m-%d')
    local chunk = {}
    local need_heading

    if not existing then
        vim.list_extend(chunk, { '# ' .. project_name .. ' Archive', '' })
        need_heading = true
    else
        local last_heading = nil
        for i = #existing, 1, -1 do
            last_heading = existing[i]:match('^### (%d%d%d%d%-%d%d%-%d%d)$')
            if last_heading then
                break
            end
        end
        need_heading = last_heading ~= today
        if need_heading then
            table.insert(chunk, '')
        end
    end

    if need_heading then
        vim.list_extend(chunk, { '### ' .. today, '' })
    end

    vim.list_extend(chunk, archived_lines)
    vim.fn.writefile(chunk, archive_path, 'a')
end

M.archive_todos = function()
    local todos_path = vim.api.nvim_buf_get_name(0)
    if not todos_path:match('todos%.md$') then
        return
    end

    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    local remaining, archived, orphaned = {}, {}, {}

    for index, line in ipairs(lines) do
        if line_checkbox_state(line) == 'x' then
            table.insert(archived, line)
            if has_unchecked_child(lines, index) then
                table.insert(orphaned, line)
            end
        else
            table.insert(remaining, line)
        end
    end

    if #archived == 0 then
        vim.notify('vault.nvim: nothing to archive', vim.log.levels.INFO)
        return
    end

    vim.api.nvim_buf_set_lines(0, 0, -1, false, remaining)
    vim.cmd('silent! write')
    if vim.bo.modified then
        vim.notify('vault.nvim: could not save todos.md, archiving aborted', vim.log.levels.WARN)
        return
    end

    if #orphaned > 0 then
        vim.notify(
            'vault.nvim: archived item(s) left an unfinished sub-item behind:\n' .. table.concat(orphaned, '\n'),
            vim.log.levels.WARN
        )
    end

    local archive_path = vim.fn.fnamemodify(todos_path, ':h') .. '/archive.md'
    local project_name = vim.fn.fnamemodify(todos_path, ':h:t')
    append_to_archive(archive_path, project_name, archived)
end

return M
