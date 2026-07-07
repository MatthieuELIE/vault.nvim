local config = require('vault.config')

local M = {}

local function apply_template(note_type)
    local state = config.state
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

M.diary_date_str_from_bufname = function(name)
    local year, month = name:match('/(%d%d%d%d)/(%d%d)/[^/]+%.md$')
    if not year then
        return nil
    end

    for day = 1, 31 do
        local candidate = os.date(
            config.state.date_format,
            os.time({ year = tonumber(year), month = tonumber(month), day = day })
        ) .. '.md'
        if name:sub(-#candidate) == candidate then
            return string.format('%s-%s-%02d', year, month, day)
        end
    end

    return nil
end

local function find_other_open_diary_bufnr(date_str)
    for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_loaded(bufnr) then
            local buf_date_str = M.diary_date_str_from_bufname(vim.api.nvim_buf_get_name(bufnr))
            if buf_date_str and buf_date_str ~= date_str then
                return bufnr
            end
        end
    end
    return nil
end

M.open_or_close = function(path, note_type)
    path = vim.fs.normalize(path)
    local bufnr = vim.fn.bufnr(path)
    if bufnr ~= -1 then
        close_buffer(bufnr)
        return
    end

    if note_type == 'daily' then
        local target_date_str = M.diary_date_str_from_bufname(path)
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

    vim.cmd(config.state.split .. ' ' .. vim.fn.fnameescape(path))
    if vim.fn.filereadable(path) == 0 then
        apply_template(note_type)
    end
end

return M
