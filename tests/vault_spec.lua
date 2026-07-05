describe('vault', function()
    local vault
    local test_vault
    local original_notify
    local original_win_close
    local notifications

    local function resolve(path)
        return vim.fs.normalize(vim.loop.fs_realpath(path) or path)
    end

    before_each(function()
        package.loaded['vault'] = nil
        vault = require('vault')
        test_vault = vim.fn.tempname() .. '_vault'
        vim.fn.mkdir(test_vault, 'p')
        notifications = {}
        original_notify = vim.notify
        vim.notify = function(msg, level) ---@diagnostic disable-line: duplicate-set-field
            table.insert(notifications, { msg = msg, level = level })
        end
        original_win_close = vim.api.nvim_win_close
    end)

    after_each(function()
        vim.notify = original_notify
        vim.api.nvim_win_close = original_win_close
        vim.fn.delete(test_vault, 'rf')
        vim.cmd('silent! %bwipeout!')
    end)

    it('opens todo file when not already open', function()
        vault.setup({
            vault_path = test_vault,
            todos_path = test_vault,
        })
        local expected_path = resolve(test_vault) .. '/' .. vault.get_project_root() .. '/todos.md'
        assert.is_nil(vim.api.nvim_buf_get_name(0):match('todos%.md$'))

        vault.toggle_todo()

        local current_buf = vim.api.nvim_get_current_buf()
        local buf_name = vim.api.nvim_buf_get_name(current_buf)
        assert.are.equal(expected_path, resolve(buf_name))
    end)

    it('derives todos_root and daily_root from vault_path when they are not set explicitly', function()
        vault.setup({ vault_path = test_vault })

        local expected_todos_path = resolve(test_vault) .. '/' .. vault.get_project_root() .. '/todos.md'
        vault.toggle_todo()
        local todos_buf_name = vim.api.nvim_buf_get_name(vim.api.nvim_get_current_buf())
        assert.are.equal(expected_todos_path, resolve(todos_buf_name))

        vault.toggle_diary('2026-05-15')
        local expected_diary_path = resolve(test_vault) .. '/daily/2026/05/15-05-2026.md'
        local diary_buf_name = vim.api.nvim_buf_get_name(vim.api.nvim_get_current_buf())
        assert.are.equal(expected_diary_path, resolve(diary_buf_name))
    end)

    it('closes todo buffer when already open saving its content', function()
        vault.setup({
            vault_path = test_vault,
            todos_path = test_vault,
        })
        local expected_path = resolve(test_vault) .. '/' .. vault.get_project_root() .. '/todos.md'

        vault.toggle_todo()

        local buf = vim.api.nvim_get_current_buf()
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, { 'some todo content' })

        vault.toggle_todo()

        assert.are.equal(-1, vim.fn.bufnr(expected_path))

        local file = io.open(expected_path, 'r')
        assert.truthy(file)
        if file then
            local content = file:read('*a')
            file:close()
            assert.are.equal('some todo content\n', content)
        end
    end)

    it('handles paths with percent and hash characters correctly', function()
        local special_project_vault = test_vault .. '/proj%e#t'
        vim.fn.mkdir(special_project_vault, 'p')
        vault.setup({
            vault_path = special_project_vault,
            todos_path = special_project_vault,
        })
        local expected_path = resolve(special_project_vault) .. '/' .. vault.get_project_root() .. '/todos.md'

        vault.toggle_todo()

        local buf = vim.api.nvim_get_current_buf()
        assert.are.equal(expected_path, resolve(vim.api.nvim_buf_get_name(buf)))

        vault.toggle_todo()

        assert.are.equal(-1, vim.fn.bufnr(expected_path))
    end)

    it('warns and aborts when the parent directory cannot be created', function()
        local blocking_file = test_vault .. '/blocked'
        local f = io.open(blocking_file, 'w')
        f:write('x')
        f:close()

        vault.setup({ vault_path = test_vault, todos_path = blocking_file })

        vault.toggle_todo()

        assert.are.equal(1, #notifications)
        assert.are.equal(vim.log.levels.ERROR, notifications[1].level)
        assert.truthy(notifications[1].msg:match('could not create directory'))
    end)

    it('opens todo file for a project name with spaces and special characters', function()
        local original_cwd = vim.fn.getcwd()
        local special_project = test_vault .. '/code/proj with space #1 %2'
        vim.fn.mkdir(special_project .. '/.git', 'p')
        vim.fn.chdir(special_project)

        vault.setup({
            vault_path = test_vault,
            todos_path = test_vault,
        })
        local expected_path = resolve(test_vault) .. '/' .. vault.get_project_root() .. '/todos.md'

        vault.toggle_todo()

        local buf = vim.api.nvim_get_current_buf()
        assert.are.equal(expected_path, resolve(vim.api.nvim_buf_get_name(buf)))

        vault.toggle_todo()
        vim.fn.chdir(original_cwd)

        assert.are.equal(-1, vim.fn.bufnr(expected_path))
    end)

    it('falls back to a safe project name and warns when project root name is empty', function()
        local original_cwd = vim.fn.getcwd()
        vim.fn.chdir('/')

        local name = vault.get_project_root()

        vim.fn.chdir(original_cwd)

        assert.are.equal('root', name)
        assert.are.equal(1, #notifications)
        assert.are.equal(vim.log.levels.WARN, notifications[1].level)
    end)

    it('copies todo template content into a newly created todos.md', function()
        local templates_dir = test_vault .. '/Templates'
        vim.fn.mkdir(templates_dir, 'p')
        local f = io.open(templates_dir .. '/Todo Template.md', 'w')
        f:write('---\ntype: todo\n---\n\n## Tasks\n')
        f:close()

        vault.setup({
            vault_path = test_vault,
            todos_path = test_vault,
            templates_path = templates_dir,
        })

        vault.toggle_todo()

        local buf = vim.api.nvim_get_current_buf()
        local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)

        assert.are.same({ '---', 'type: todo', '---', '', '## Tasks' }, lines)
    end)

    it('copies daily template content into a newly created diary note', function()
        local templates_dir = test_vault .. '/Templates'
        vim.fn.mkdir(templates_dir, 'p')
        local f = io.open(templates_dir .. '/Daily Note Template.md', 'w')
        f:write('# Daily\n\n![[Daily.base]]\n')
        f:close()

        vault.setup({
            vault_path = test_vault,
            daily_path = test_vault .. '/daily',
            templates_path = templates_dir,
        })

        vault.toggle_diary('2026-05-15')

        local buf = vim.api.nvim_get_current_buf()
        local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)

        assert.are.same({ '# Daily', '', '![[Daily.base]]' }, lines)
    end)

    it('creates an empty todos.md when templates_path is set but the template file is missing', function()
        local templates_dir = test_vault .. '/Templates'
        vim.fn.mkdir(templates_dir, 'p')

        vault.setup({
            vault_path = test_vault,
            todos_path = test_vault,
            templates_path = templates_dir,
        })

        vault.toggle_todo()

        local buf = vim.api.nvim_get_current_buf()
        local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)

        assert.are.same({ '' }, lines)
        assert.are.equal(0, #notifications)
    end)

    it('does not re-apply the template to an already existing todos.md', function()
        local templates_dir = test_vault .. '/Templates'
        vim.fn.mkdir(templates_dir, 'p')
        local f = io.open(templates_dir .. '/Todo Template.md', 'w')
        f:write('## Tasks\n')
        f:close()

        vault.setup({
            vault_path = test_vault,
            todos_path = test_vault,
            templates_path = templates_dir,
        })
        local expected_path = resolve(test_vault) .. '/' .. vault.get_project_root() .. '/todos.md'
        vim.fn.mkdir(vim.fn.fnamemodify(expected_path, ':h'), 'p')
        local existing = io.open(expected_path, 'w')
        existing:write('pre-existing content\n')
        existing:close()

        vault.toggle_todo()

        local buf = vim.api.nvim_get_current_buf()
        local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)

        assert.are.same({ 'pre-existing content' }, lines)
    end)

    it('applies an overridden template filename set via opts.templates', function()
        local templates_dir = test_vault .. '/Templates'
        vim.fn.mkdir(templates_dir, 'p')
        local f = io.open(templates_dir .. '/My Todo.md', 'w')
        f:write('## Custom\n')
        f:close()

        vault.setup({
            vault_path = test_vault,
            todos_path = test_vault,
            templates_path = templates_dir,
            templates = { todos = 'My Todo.md' },
        })

        vault.toggle_todo()

        local buf = vim.api.nvim_get_current_buf()
        local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)

        assert.are.same({ '## Custom' }, lines)
    end)

    it('does not warn when VAULT_PATH env var is unset', function()
        local original_env = vim.env.VAULT_PATH
        vim.env.VAULT_PATH = nil
        package.loaded['vault'] = nil
        require('vault')
        vim.env.VAULT_PATH = original_env

        assert.are.equal(0, #notifications)
    end)

    it('falls back to default vault path and warns when setup is called with an empty vault_path', function()
        vault.setup({ vault_path = '' })

        assert.are.equal(1, #notifications)
        assert.are.equal(vim.log.levels.ERROR, notifications[1].level)
        assert.truthy(notifications[1].msg:match('vault_path'))
    end)

    it('aborts deletion and warns if buffer cannot be saved', function()
        vault.setup({
            vault_path = test_vault,
            todos_path = test_vault,
        })
        local expected_path = resolve(test_vault) .. '/' .. vault.get_project_root() .. '/todos.md'

        vault.toggle_todo()

        local buf = vim.api.nvim_get_current_buf()
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, { 'modified content' })
        vim.bo[buf].modified = true

        local original_write = vim.cmd
        vim.cmd = function(cmd_str) ---@diagnostic disable-line: duplicate-set-field
            if cmd_str == 'silent! write' then
                return
            else
                original_write(cmd_str)
            end
        end

        vault.toggle_todo()

        vim.cmd = original_write

        assert.is_true(vim.bo[buf].modified)
        assert.not_equal(-1, vim.fn.bufnr(expected_path))
        assert.are.equal(1, #notifications)
        assert.truthy(notifications[1].msg:match('could not save'))
    end)

    it('aborts deletion and warns if window close fails', function()
        vault.setup({
            vault_path = test_vault,
            todos_path = test_vault,
        })
        local expected_path = resolve(test_vault) .. '/' .. vault.get_project_root() .. '/todos.md'

        vault.toggle_todo()

        vim.api.nvim_win_close = function(_win, _force) ---@diagnostic disable-line: duplicate-set-field
            error('simulated window close failure')
        end

        vault.toggle_todo()

        assert.not_equal(-1, vim.fn.bufnr(expected_path))
        assert.are.equal(1, #notifications)
        assert.truthy(notifications[1].msg:match('could not close all windows'))
    end)

    it('opens today diary when no argument is provided', function()
        vault.setup({
            vault_path = test_vault,
            daily_path = test_vault .. '/daily',
        })
        local original_os_date = os.date
        os.date = function(fmt, time)
            if fmt == '*t' then
                return { year = 2025, month = 12, day = 25 }
            end
            return original_os_date(fmt, time)
        end

        vault.toggle_diary()

        os.date = original_os_date

        local expected_path = resolve(test_vault) .. '/daily/2025/12/25-12-2025.md'
        local current_buf = vim.api.nvim_get_current_buf()
        local buf_name = vim.api.nvim_buf_get_name(current_buf)
        assert.are.equal(expected_path, resolve(buf_name))
    end)

    it('opens diary for valid date argument', function()
        vault.setup({
            vault_path = test_vault,
            daily_path = test_vault .. '/daily',
        })

        vault.toggle_diary('2026-05-15')

        local expected_path = resolve(test_vault) .. '/daily/2026/05/15-05-2026.md'
        local current_buf = vim.api.nvim_get_current_buf()
        local buf_name = vim.api.nvim_buf_get_name(current_buf)
        assert.are.equal(expected_path, resolve(buf_name))
    end)

    it('does not crash and opens today diary for invalid date argument', function()
        vault.setup({
            vault_path = test_vault,
            daily_path = test_vault .. '/daily',
        })
        local original_os_date = os.date
        os.date = function(fmt, time)
            if fmt == '*t' then
                return { year = 2025, month = 12, day = 25 }
            end
            return original_os_date(fmt, time)
        end

        vault.toggle_diary('invalid-date')

        os.date = original_os_date

        local expected_path = resolve(test_vault) .. '/daily/2025/12/25-12-2025.md'
        local current_buf = vim.api.nvim_get_current_buf()
        local buf_name = vim.api.nvim_buf_get_name(current_buf)
        assert.are.equal(expected_path, resolve(buf_name))
    end)

    it('closes diary buffer when already open saving its content', function()
        vault.setup({
            vault_path = test_vault,
            daily_path = test_vault .. '/daily',
        })
        local expected_path = resolve(test_vault) .. '/daily/2026/05/15-05-2026.md'

        vault.toggle_diary('2026-05-15')

        local buf = vim.api.nvim_get_current_buf()
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, { 'some diary content' })

        vault.toggle_diary('2026-05-15')

        assert.are.equal(-1, vim.fn.bufnr(expected_path))

        local file = io.open(expected_path, 'r')
        assert.truthy(file)
        if file then
            local content = file:read('*a')
            file:close()
            assert.are.equal('some diary content\n', content)
        end
    end)

    it('toggles unchecked checkbox to checked', function()
        vault.setup({
            vault_path = test_vault,
            todos_path = test_vault,
        })
        vault.toggle_todo()
        local buf = vim.api.nvim_get_current_buf()
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, { '- [ ] item 1' })

        vault.toggle_checkbox()

        local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
        assert.are.equal('- [x] item 1', lines[1])
    end)

    it('toggles checked checkbox to unchecked', function()
        vault.setup({
            vault_path = test_vault,
            todos_path = test_vault,
        })
        vault.toggle_todo()
        local buf = vim.api.nvim_get_current_buf()
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, { '- [x] item 1' })

        vault.toggle_checkbox()

        local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
        assert.are.equal('- [ ] item 1', lines[1])
    end)

    it('adds checkbox to a line without checkbox', function()
        vault.setup({
            vault_path = test_vault,
            todos_path = test_vault,
        })
        vault.toggle_todo()
        local buf = vim.api.nvim_get_current_buf()
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, { 'some task' })

        vault.toggle_checkbox()

        local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
        assert.are.equal('- [ ] some task', lines[1])
    end)

    it('does nothing if current buffer is not todos.md', function()
        vault.setup({
            vault_path = test_vault,
            todos_path = test_vault,
        })
        local buf = vim.api.nvim_create_buf(true, false)
        vim.api.nvim_buf_set_name(buf, test_vault .. '/other.md')
        vim.api.nvim_set_current_buf(buf)
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, { 'some line' })

        vault.toggle_checkbox()

        local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
        assert.are.equal('some line', lines[1])
    end)
end)
