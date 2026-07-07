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

local DEFAULT_DIARY_DATE_FORMAT = '%d-%m-%Y'

M.state = {
    split_cmd = 'vsplit',
    template_filenames = DEFAULT_TEMPLATE_FILENAMES,
    date_format = DEFAULT_DIARY_DATE_FORMAT,
}

local function set_vault_path(path, source)
    M.state.vault = resolve_vault_path(path, source)
    M.state.todos_root = M.state.vault
    M.state.daily_root = M.state.vault .. '/daily'
end

set_vault_path(vim.env.VAULT_PATH, 'VAULT_PATH')

M.setup = function(opts)
    local state = M.state

    if opts.vault_path then
        set_vault_path(opts.vault_path, 'vault_path')
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
    if opts.date_format then
        state.date_format = opts.date_format
    end
    if opts.templates_path then
        state.templates_path = vim.fn.expand(opts.templates_path)
    end
    if opts.templates then
        state.template_filenames = vim.tbl_extend('force', DEFAULT_TEMPLATE_FILENAMES, opts.templates)
    end
end

return M
