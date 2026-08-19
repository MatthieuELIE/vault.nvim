describe('vault', function()
    local vault
    local test_vault
    local original_notify
    local original_win_close
    local notifications

    local function resolve(path)
        return vim.fs.normalize(vim.loop.fs_realpath(path) or path)
    end

    local function reload_vault()
        for name in pairs(package.loaded) do
            if name:match('^vault') then
                package.loaded[name] = nil
            end
        end
        return require('vault')
    end

    before_each(function()
        vault = reload_vault()
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
        for _, lhs in ipairs({
            '<leader>vt',
            '<leader>vi',
            '<leader>vd',
            '<leader>vn',
            '<leader>vp',
            '<leader>vg',
            '<leader>vs',
            '<leader>x',
        }) do
            pcall(vim.keymap.del, 'n', lhs)
        end
    end)

    it('opens todo file when not already open', function()
        vault.setup({
            vault_path = test_vault,
            todos_path = test_vault,
        })
        local expected_path = resolve(test_vault) .. '/' .. vault.get_project_root() .. '/todos.md'
        local initial_buf_name = vim.api.nvim_buf_get_name(0)

        vault.toggle_todo()

        local current_buf = vim.api.nvim_get_current_buf()
        local buf_name = vim.api.nvim_buf_get_name(current_buf)

        assert.is_nil(initial_buf_name:match('todos%.md$'))
        assert.are.equal(expected_path, resolve(buf_name))
    end)

    it('derives todos_root and daily_root from vault_path when they are not set explicitly', function()
        vault.setup({ vault_path = test_vault })

        local expected_todos_path = resolve(test_vault) .. '/' .. vault.get_project_root() .. '/todos.md'
        local expected_diary_path = resolve(test_vault) .. '/daily/2026/05/15-05-2026.md'

        vault.toggle_todo()
        local todos_buf_name = vim.api.nvim_buf_get_name(vim.api.nvim_get_current_buf())

        vault.toggle_diary('2026-05-15')
        local diary_buf_name = vim.api.nvim_buf_get_name(vim.api.nvim_get_current_buf())

        assert.are.equal(expected_todos_path, resolve(todos_buf_name))
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

        local file = io.open(expected_path, 'r')
        local content = file and file:read('*a')
        if file then
            file:close()
        end

        assert.are.equal(-1, vim.fn.bufnr(expected_path))
        assert.truthy(file)
        assert.are.equal('some todo content\n', content)
    end)

    it("closes todo buffer opened via split = 'edit' when it is the only window", function()
        vault.setup({
            vault_path = test_vault,
            todos_path = test_vault,
            split = 'edit',
        })
        vim.cmd('only')
        local expected_path = resolve(test_vault) .. '/' .. vault.get_project_root() .. '/todos.md'

        vault.toggle_todo()

        local buf = vim.api.nvim_get_current_buf()
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, { 'some todo content' })

        vault.toggle_todo()

        local file = io.open(expected_path, 'r')
        local content = file and file:read('*a')
        if file then
            file:close()
        end

        assert.are.equal(-1, vim.fn.bufnr(expected_path))
        assert.are.equal(0, #notifications)
        assert.truthy(file)
        assert.are.equal('some todo content\n', content)
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
        local buf_name = resolve(vim.api.nvim_buf_get_name(buf))

        vault.toggle_todo()

        assert.are.equal(expected_path, buf_name)
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
        local buf_name = resolve(vim.api.nvim_buf_get_name(buf))

        vault.toggle_todo()
        vim.fn.chdir(original_cwd)

        assert.are.equal(expected_path, buf_name)
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

    it('does not write the template to disk until the new todos.md buffer is saved', function()
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

        vault.toggle_todo()

        assert.are.equal(0, vim.fn.filereadable(expected_path))
        assert.is_true(vim.bo.modified)
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
        assert.are.equal(1, #notifications)
        assert.are.equal(vim.log.levels.WARN, notifications[1].level)
        assert.truthy(notifications[1].msg:match('template file not found'))
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

    it('appends a todo line to an already existing todos.md without opening it', function()
        vault.setup({
            vault_path = test_vault,
            todos_path = test_vault,
        })
        local expected_path = resolve(test_vault) .. '/' .. vault.get_project_root() .. '/todos.md'
        vim.fn.mkdir(vim.fn.fnamemodify(expected_path, ':h'), 'p')
        vim.fn.writefile({ '- [x] existing item' }, expected_path)
        local initial_buf_name = vim.api.nvim_buf_get_name(0)
        local original_input = vim.ui.input
        vim.ui.input = function(_, on_confirm) ---@diagnostic disable-line: duplicate-set-field
            on_confirm('new item')
        end

        vault.quick_add_todo()

        vim.ui.input = original_input

        assert.are.equal(initial_buf_name, vim.api.nvim_buf_get_name(0))
        assert.are.same({ '- [x] existing item', '- [ ] new item' }, vim.fn.readfile(expected_path))
    end)

    it('appends into an already-open todos.md buffer instead of the file on disk', function()
        vault.setup({
            vault_path = test_vault,
            todos_path = test_vault,
        })
        local expected_path = resolve(test_vault) .. '/' .. vault.get_project_root() .. '/todos.md'
        vault.toggle_todo()
        local buf = vim.api.nvim_get_current_buf()
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, { '- [ ] unsaved edit' })
        local original_input = vim.ui.input
        vim.ui.input = function(_, on_confirm) ---@diagnostic disable-line: duplicate-set-field
            on_confirm('new item')
        end

        vault.quick_add_todo()

        vim.ui.input = original_input

        assert.are.same({ '- [ ] unsaved edit', '- [ ] new item' }, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
        assert.are.same({ '- [ ] unsaved edit', '- [ ] new item' }, vim.fn.readfile(expected_path))
    end)

    it('warns and aborts quick add when the parent directory cannot be created', function()
        local blocking_file = test_vault .. '/blocked'
        local f = io.open(blocking_file, 'w')
        f:write('x')
        f:close()

        vault.setup({ vault_path = test_vault, todos_path = blocking_file })
        local original_input = vim.ui.input
        vim.ui.input = function(_, on_confirm) ---@diagnostic disable-line: duplicate-set-field
            on_confirm('new item')
        end

        vault.quick_add_todo()

        vim.ui.input = original_input

        assert.are.equal(1, #notifications)
        assert.are.equal(vim.log.levels.ERROR, notifications[1].level)
        assert.truthy(notifications[1].msg:match('could not create directory'))
    end)

    it('warns instead of crashing when quick add cannot write the todo template to disk', function()
        local templates_dir = test_vault .. '/Templates'
        vim.fn.mkdir(templates_dir, 'p')
        local f = io.open(templates_dir .. '/Todo Template.md', 'w')
        f:write('## Tasks')
        f:close()

        vault.setup({
            vault_path = test_vault,
            todos_path = test_vault,
            templates_path = templates_dir,
        })
        local expected_path = resolve(test_vault) .. '/' .. vault.get_project_root() .. '/todos.md'
        local project_dir = vim.fn.fnamemodify(expected_path, ':h')
        vim.fn.mkdir(project_dir, 'p')
        vim.fn.setfperm(project_dir, 'r-xr-xr-x')
        local original_input = vim.ui.input
        vim.ui.input = function(_, on_confirm) ---@diagnostic disable-line: duplicate-set-field
            on_confirm('new item')
        end

        vault.quick_add_todo()

        vim.ui.input = original_input
        vim.fn.setfperm(project_dir, 'rwxr-xr-x')

        assert.are.equal(1, #notifications)
        assert.are.equal(vim.log.levels.ERROR, notifications[1].level)
        assert.truthy(notifications[1].msg:match('could not write'))
    end)

    it('warns instead of crashing when quick add cannot append to an existing todos.md', function()
        vault.setup({
            vault_path = test_vault,
            todos_path = test_vault,
        })
        local expected_path = resolve(test_vault) .. '/' .. vault.get_project_root() .. '/todos.md'
        local project_dir = vim.fn.fnamemodify(expected_path, ':h')
        vim.fn.mkdir(project_dir, 'p')
        vim.fn.setfperm(project_dir, 'r-xr-xr-x')
        local original_input = vim.ui.input
        vim.ui.input = function(_, on_confirm) ---@diagnostic disable-line: duplicate-set-field
            on_confirm('new item')
        end

        vault.quick_add_todo()

        vim.ui.input = original_input
        vim.fn.setfperm(project_dir, 'rwxr-xr-x')

        assert.are.equal(1, #notifications)
        assert.are.equal(vim.log.levels.ERROR, notifications[1].level)
        assert.truthy(notifications[1].msg:match('could not write to'))
    end)

    it('creates todos.md with the todo template before appending when it does not exist yet', function()
        local templates_dir = test_vault .. '/Templates'
        vim.fn.mkdir(templates_dir, 'p')
        local f = io.open(templates_dir .. '/Todo Template.md', 'w')
        f:write('## Tasks')
        f:close()
        vault.setup({
            vault_path = test_vault,
            todos_path = test_vault,
            templates_path = templates_dir,
        })
        local expected_path = resolve(test_vault) .. '/' .. vault.get_project_root() .. '/todos.md'
        local original_input = vim.ui.input
        vim.ui.input = function(_, on_confirm) ---@diagnostic disable-line: duplicate-set-field
            on_confirm('new item')
        end

        vault.quick_add_todo()

        vim.ui.input = original_input

        assert.are.same({ '## Tasks', '- [ ] new item' }, vim.fn.readfile(expected_path))
    end)

    it('creates a plain todos.md when no template is configured', function()
        vault.setup({
            vault_path = test_vault,
            todos_path = test_vault,
        })
        local expected_path = resolve(test_vault) .. '/' .. vault.get_project_root() .. '/todos.md'
        local original_input = vim.ui.input
        vim.ui.input = function(_, on_confirm) ---@diagnostic disable-line: duplicate-set-field
            on_confirm('new item')
        end

        vault.quick_add_todo()

        vim.ui.input = original_input

        assert.are.same({ '- [ ] new item' }, vim.fn.readfile(expected_path))
    end)

    it('does nothing when the quick add todo prompt is cancelled', function()
        vault.setup({
            vault_path = test_vault,
            todos_path = test_vault,
        })
        local expected_path = resolve(test_vault) .. '/' .. vault.get_project_root() .. '/todos.md'
        local original_input = vim.ui.input
        vim.ui.input = function(_, on_confirm) ---@diagnostic disable-line: duplicate-set-field
            on_confirm(nil)
        end

        vault.quick_add_todo()

        vim.ui.input = original_input

        assert.are.equal(0, vim.fn.filereadable(expected_path))
    end)

    it('does not warn when VAULT_PATH env var is unset', function()
        local original_env = vim.env.VAULT_PATH
        vim.env.VAULT_PATH = nil
        reload_vault()
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

    it('rolls a calendar-invalid date over to the next month rather than falling back to today', function()
        vault.setup({
            vault_path = test_vault,
            daily_path = test_vault .. '/daily',
        })

        vault.toggle_diary('2026-02-30')

        local expected_path = resolve(test_vault) .. '/daily/2026/03/02-03-2026.md'
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

        local file = io.open(expected_path, 'r')
        local content = file and file:read('*a')
        if file then
            file:close()
        end

        assert.are.equal(-1, vim.fn.bufnr(expected_path))
        assert.truthy(file)
        assert.are.equal('some diary content\n', content)
    end)

    it('closes a different open diary note before opening a new date via toggle_diary', function()
        vault.setup({
            vault_path = test_vault,
            daily_path = test_vault .. '/daily',
        })
        local previous_path = resolve(test_vault) .. '/daily/2026/05/15-05-2026.md'
        local next_path = resolve(test_vault) .. '/daily/2026/05/16-05-2026.md'

        vault.toggle_diary('2026-05-15')
        local buf = vim.api.nvim_get_current_buf()
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, { 'some diary content' })

        vault.toggle_diary('2026-05-16')

        local current_buf = vim.api.nvim_get_current_buf()
        local file = io.open(previous_path, 'r')
        local content = file and file:read('*a')
        if file then
            file:close()
        end

        assert.are.equal(-1, vim.fn.bufnr(previous_path))
        assert.are.equal(next_path, resolve(vim.api.nvim_buf_get_name(current_buf)))
        assert.are.equal(2, #vim.api.nvim_list_wins())
        assert.truthy(file)
        assert.are.equal('some diary content\n', content)
    end)

    it('closes a different open diary note in a non-focused window before opening a new date', function()
        vault.setup({
            vault_path = test_vault,
            daily_path = test_vault .. '/daily',
        })
        local previous_path = resolve(test_vault) .. '/daily/2026/05/15-05-2026.md'
        local next_path = resolve(test_vault) .. '/daily/2026/05/16-05-2026.md'

        vault.toggle_diary('2026-05-15')
        local previous_buf = vim.api.nvim_get_current_buf()
        vim.api.nvim_buf_set_lines(previous_buf, 0, -1, false, { 'some diary content' })
        vim.cmd('vsplit')
        vim.api.nvim_set_current_buf(vim.api.nvim_create_buf(true, false))

        vault.toggle_diary('2026-05-16')

        local current_buf = vim.api.nvim_get_current_buf()
        local file = io.open(previous_path, 'r')
        local content = file and file:read('*a')
        if file then
            file:close()
        end

        assert.are.equal(-1, vim.fn.bufnr(previous_path))
        assert.are.equal(next_path, resolve(vim.api.nvim_buf_get_name(current_buf)))
        assert.truthy(file)
        assert.are.equal('some diary content\n', content)
    end)

    it('opens diary using a custom date_format', function()
        vault.setup({
            vault_path = test_vault,
            daily_path = test_vault .. '/daily',
            date_format = '%Y-%m-%d',
        })

        vault.toggle_diary('2026-05-15')

        local expected_path = resolve(test_vault) .. '/daily/2026/05/2026-05-15.md'
        local current_buf = vim.api.nvim_get_current_buf()
        assert.are.equal(expected_path, resolve(vim.api.nvim_buf_get_name(current_buf)))
    end)

    it('closes a different open diary note before opening a new date with a custom date_format', function()
        vault.setup({
            vault_path = test_vault,
            daily_path = test_vault .. '/daily',
            date_format = '%Y-%m-%d',
        })
        local previous_path = resolve(test_vault) .. '/daily/2026/05/2026-05-15.md'
        local next_path = resolve(test_vault) .. '/daily/2026/05/2026-05-16.md'

        vault.toggle_diary('2026-05-15')
        vault.toggle_diary('2026-05-16')

        local current_buf = vim.api.nvim_get_current_buf()

        assert.are.equal(-1, vim.fn.bufnr(previous_path))
        assert.are.equal(next_path, resolve(vim.api.nvim_buf_get_name(current_buf)))
        assert.are.equal(2, #vim.api.nvim_list_wins())
    end)

    it('moves to the next day diary from within a diary buffer', function()
        vault.setup({
            vault_path = test_vault,
            daily_path = test_vault .. '/daily',
        })
        local previous_path = resolve(test_vault) .. '/daily/2026/05/15-05-2026.md'
        local next_path = resolve(test_vault) .. '/daily/2026/05/16-05-2026.md'

        vault.toggle_diary('2026-05-15')
        local buf = vim.api.nvim_get_current_buf()
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, { 'some diary content' })

        vault.diary_next_day()

        local current_buf = vim.api.nvim_get_current_buf()
        local file = io.open(previous_path, 'r')
        local content = file and file:read('*a')
        if file then
            file:close()
        end

        assert.are.equal(-1, vim.fn.bufnr(previous_path))
        assert.are.equal(next_path, resolve(vim.api.nvim_buf_get_name(current_buf)))
        assert.truthy(file)
        assert.are.equal('some diary content\n', content)
    end)

    it('moves to the previous day diary from within a diary buffer, across a month/year boundary', function()
        vault.setup({
            vault_path = test_vault,
            daily_path = test_vault .. '/daily',
        })
        local current_path = resolve(test_vault) .. '/daily/2026/01/01-01-2026.md'
        local previous_path = resolve(test_vault) .. '/daily/2025/12/31-12-2025.md'

        vault.toggle_diary('2026-01-01')

        vault.diary_prev_day()

        local current_buf = vim.api.nvim_get_current_buf()

        assert.are.equal(-1, vim.fn.bufnr(current_path))
        assert.are.equal(previous_path, resolve(vim.api.nvim_buf_get_name(current_buf)))
    end)

    it('opens tomorrow diary via next-day navigation when not currently in a diary buffer', function()
        vault.setup({
            vault_path = test_vault,
            daily_path = test_vault .. '/daily',
        })
        local original_os_time = os.time
        local fixed_now = original_os_time({ year = 2025, month = 12, day = 25, hour = 12 })
        os.time = function(t) ---@diagnostic disable-line: duplicate-set-field
            if t == nil then
                return fixed_now
            end
            return original_os_time(t)
        end

        vault.diary_next_day()

        os.time = original_os_time

        local expected_path = resolve(test_vault) .. '/daily/2025/12/26-12-2025.md'
        local current_buf = vim.api.nvim_get_current_buf()
        assert.are.equal(expected_path, resolve(vim.api.nvim_buf_get_name(current_buf)))
    end)

    it('opens yesterday diary via prev-day navigation when not currently in a diary buffer', function()
        vault.setup({
            vault_path = test_vault,
            daily_path = test_vault .. '/daily',
        })
        local original_os_time = os.time
        local fixed_now = original_os_time({ year = 2025, month = 12, day = 25, hour = 12 })
        os.time = function(t) ---@diagnostic disable-line: duplicate-set-field
            if t == nil then
                return fixed_now
            end
            return original_os_time(t)
        end

        vault.diary_prev_day()

        os.time = original_os_time

        local expected_path = resolve(test_vault) .. '/daily/2025/12/24-12-2025.md'
        local current_buf = vim.api.nvim_get_current_buf()
        assert.are.equal(expected_path, resolve(vim.api.nvim_buf_get_name(current_buf)))
    end)

    it('aborts navigation and keeps the current diary open if it cannot be saved', function()
        vault.setup({
            vault_path = test_vault,
            daily_path = test_vault .. '/daily',
        })
        local expected_path = resolve(test_vault) .. '/daily/2026/05/15-05-2026.md'
        local next_path = resolve(test_vault) .. '/daily/2026/05/16-05-2026.md'

        vault.toggle_diary('2026-05-15')

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

        vault.diary_next_day()

        vim.cmd = original_write

        assert.is_true(vim.bo[buf].modified)
        assert.not_equal(-1, vim.fn.bufnr(expected_path))
        assert.are.equal(-1, vim.fn.bufnr(next_path))
        assert.are.equal(1, #notifications)
        assert.truthy(notifications[1].msg:match('could not save'))
    end)

    it('opens the entered date when confirming the diary goto prompt', function()
        vault.setup({
            vault_path = test_vault,
            daily_path = test_vault .. '/daily',
        })
        local expected_path = resolve(test_vault) .. '/daily/2026/05/15-05-2026.md'
        local original_input = vim.ui.input
        vim.ui.input = function(_, on_confirm) ---@diagnostic disable-line: duplicate-set-field
            on_confirm('2026-05-15')
        end

        vault.diary_goto()

        vim.ui.input = original_input

        local current_buf = vim.api.nvim_get_current_buf()
        assert.are.equal(expected_path, resolve(vim.api.nvim_buf_get_name(current_buf)))
    end)

    it('does nothing when the diary goto prompt is cancelled', function()
        vault.setup({
            vault_path = test_vault,
            daily_path = test_vault .. '/daily',
        })
        local original_input = vim.ui.input
        vim.ui.input = function(_, on_confirm) ---@diagnostic disable-line: duplicate-set-field
            on_confirm(nil)
        end
        local buf_count_before = #vim.api.nvim_list_bufs()

        vault.diary_goto()

        vim.ui.input = original_input

        assert.are.equal(buf_count_before, #vim.api.nvim_list_bufs())
    end)

    it('defaults the diary goto prompt to the current diary buffer date', function()
        vault.setup({
            vault_path = test_vault,
            daily_path = test_vault .. '/daily',
        })
        vault.toggle_diary('2026-05-15')
        local captured_default
        local original_input = vim.ui.input
        vim.ui.input = function(input_opts, on_confirm) ---@diagnostic disable-line: duplicate-set-field
            captured_default = input_opts.default
            on_confirm(nil)
        end

        vault.diary_goto()

        vim.ui.input = original_input

        assert.are.equal('2026-05-15', captured_default)
    end)

    it("defaults the diary goto prompt to today's date when not in a diary buffer", function()
        vault.setup({
            vault_path = test_vault,
            daily_path = test_vault .. '/daily',
        })
        local original_os_time = os.time
        local fixed_now = original_os_time({ year = 2025, month = 12, day = 25, hour = 12 })
        os.time = function(t) ---@diagnostic disable-line: duplicate-set-field
            if t == nil then
                return fixed_now
            end
            return original_os_time(t)
        end
        local captured_default
        local original_input = vim.ui.input
        vim.ui.input = function(input_opts, on_confirm) ---@diagnostic disable-line: duplicate-set-field
            captured_default = input_opts.default
            on_confirm(nil)
        end

        vault.diary_goto()

        os.time = original_os_time
        vim.ui.input = original_input

        assert.are.equal('2025-12-25', captured_default)
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

    local function stub_today(date_str)
        local original_os_date = os.date
        os.date = function(fmt, ...) ---@diagnostic disable-line: duplicate-set-field
            if fmt == '%Y-%m-%d' then
                return date_str
            end
            return original_os_date(fmt, ...)
        end
        return original_os_date
    end

    it('archives checked todos in order, saves todos.md, and titles a new archive.md', function()
        vault.setup({
            vault_path = test_vault,
            todos_path = test_vault,
        })
        vault.toggle_todo()
        local buf = vim.api.nvim_get_current_buf()
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
            '- [ ] pending',
            '- [x] done 1',
            '- [x] done 2',
        })
        local archive_path = resolve(test_vault) .. '/' .. vault.get_project_root() .. '/archive.md'
        local original_os_date = stub_today('2026-07-13')

        vault.archive_todos()

        os.date = original_os_date
        local remaining = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
        local archive_lines = vim.fn.readfile(archive_path)

        assert.are.same({ '- [ ] pending' }, remaining)
        assert.is_false(vim.bo[buf].modified)
        assert.are.same({
            '# ' .. vault.get_project_root() .. ' Archive',
            '',
            '### 2026-07-13',
            '',
            '- [x] done 1',
            '- [x] done 2',
        }, archive_lines)
    end)

    it('appends under the existing day section without duplicating the heading', function()
        vault.setup({
            vault_path = test_vault,
            todos_path = test_vault,
        })
        vault.toggle_todo()
        local buf = vim.api.nvim_get_current_buf()
        local archive_path = resolve(test_vault) .. '/' .. vault.get_project_root() .. '/archive.md'
        vim.fn.writefile({
            '# ' .. vault.get_project_root() .. ' Archive',
            '',
            '### 2026-07-13',
            '',
            '- [x] earlier today',
        }, archive_path)
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, { '- [x] later today' })
        local original_os_date = stub_today('2026-07-13')

        vault.archive_todos()

        os.date = original_os_date
        local archive_lines = vim.fn.readfile(archive_path)

        assert.are.same({
            '# ' .. vault.get_project_root() .. ' Archive',
            '',
            '### 2026-07-13',
            '',
            '- [x] earlier today',
            '- [x] later today',
        }, archive_lines)
    end)

    it('opens a new day section when the archive last entry is a different day', function()
        vault.setup({
            vault_path = test_vault,
            todos_path = test_vault,
        })
        vault.toggle_todo()
        local buf = vim.api.nvim_get_current_buf()
        local archive_path = resolve(test_vault) .. '/' .. vault.get_project_root() .. '/archive.md'
        vim.fn.writefile({
            '# ' .. vault.get_project_root() .. ' Archive',
            '',
            '### 2026-07-01',
            '',
            '- [x] old item',
        }, archive_path)
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, { '- [x] new item' })
        local original_os_date = stub_today('2026-07-13')

        vault.archive_todos()

        os.date = original_os_date
        local archive_lines = vim.fn.readfile(archive_path)

        assert.are.same({
            '# ' .. vault.get_project_root() .. ' Archive',
            '',
            '### 2026-07-01',
            '',
            '- [x] old item',
            '',
            '### 2026-07-13',
            '',
            '- [x] new item',
        }, archive_lines)
    end)

    it('warns without moving an unchecked sub-item when its parent is archived', function()
        vault.setup({
            vault_path = test_vault,
            todos_path = test_vault,
        })
        vault.toggle_todo()
        local buf = vim.api.nvim_get_current_buf()
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
            '- [x] parent',
            '  - [ ] child',
        })

        vault.archive_todos()

        local remaining = vim.api.nvim_buf_get_lines(buf, 0, -1, false)

        assert.are.same({ '  - [ ] child' }, remaining)
        assert.are.equal(1, #notifications)
        assert.are.equal(vim.log.levels.WARN, notifications[1].level)
        assert.truthy(notifications[1].msg:match('unfinished sub%-item'))
    end)

    it('does nothing when there are no checked todos', function()
        vault.setup({
            vault_path = test_vault,
            todos_path = test_vault,
        })
        vault.toggle_todo()
        local buf = vim.api.nvim_get_current_buf()
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, { '- [ ] pending' })
        local archive_path = resolve(test_vault) .. '/' .. vault.get_project_root() .. '/archive.md'

        vault.archive_todos()

        local remaining = vim.api.nvim_buf_get_lines(buf, 0, -1, false)

        assert.are.same({ '- [ ] pending' }, remaining)
        assert.are.equal(0, vim.fn.filereadable(archive_path))
        assert.are.equal(1, #notifications)
        assert.are.equal(vim.log.levels.INFO, notifications[1].level)
    end)

    it('does nothing when current buffer is not todos.md', function()
        vault.setup({
            vault_path = test_vault,
            todos_path = test_vault,
        })
        vim.cmd('enew')
        vim.api.nvim_buf_set_lines(0, 0, -1, false, { '- [x] done' })

        vault.archive_todos()

        local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)

        assert.are.same({ '- [x] done' }, lines)
        assert.are.equal(0, #notifications)
    end)

    it('aborts archiving and warns if todos.md cannot be saved', function()
        vault.setup({
            vault_path = test_vault,
            todos_path = test_vault,
        })
        vault.toggle_todo()
        local buf = vim.api.nvim_get_current_buf()
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, { '- [ ] pending', '- [x] done' })
        local archive_path = resolve(test_vault) .. '/' .. vault.get_project_root() .. '/archive.md'
        local original_cmd = vim.cmd
        vim.cmd = function(cmd_str) ---@diagnostic disable-line: duplicate-set-field
            if cmd_str == 'silent! write' then
                return
            else
                original_cmd(cmd_str)
            end
        end

        vault.archive_todos()

        vim.cmd = original_cmd
        local remaining = vim.api.nvim_buf_get_lines(buf, 0, -1, false)

        assert.are.same({ '- [ ] pending' }, remaining)
        assert.is_true(vim.bo[buf].modified)
        assert.are.equal(0, vim.fn.filereadable(archive_path))
        assert.are.equal(1, #notifications)
        assert.truthy(notifications[1].msg:match('could not save'))
    end)

    it('counts unchecked todos in the current project todos.md', function()
        vault.setup({
            vault_path = test_vault,
            todos_path = test_vault,
        })
        vault.toggle_todo()
        local buf = vim.api.nvim_get_current_buf()
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
            '- [ ] pending 1',
            '- [x] done',
            '- [ ] pending 2',
        })
        vim.cmd('silent! write')

        local count = vault.todo_count()

        assert.are.equal(2, count)
    end)

    it('returns 0 when the project todos.md does not exist', function()
        vault.setup({
            vault_path = test_vault,
            todos_path = test_vault,
        })

        local count = vault.todo_count()

        assert.are.equal(0, count)
    end)

    it('returns 0 when all todos are checked', function()
        vault.setup({
            vault_path = test_vault,
            todos_path = test_vault,
        })
        vault.toggle_todo()
        local buf = vim.api.nvim_get_current_buf()
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, { '- [x] done' })
        vim.cmd('silent! write')

        local count = vault.todo_count()

        assert.are.equal(0, count)
    end)

    it('populates the quickfix list with matches across projects todos.md files', function()
        vault.setup({
            vault_path = test_vault,
            todos_path = test_vault,
        })
        vim.fn.mkdir(test_vault .. '/proj-a', 'p')
        local file_a = io.open(test_vault .. '/proj-a/todos.md', 'w')
        file_a:write('- [ ] buy milk\n- [ ] call bob\n')
        file_a:close()
        vim.fn.mkdir(test_vault .. '/proj-b', 'p')
        local file_b = io.open(test_vault .. '/proj-b/todos.md', 'w')
        file_b:write('- [ ] fix bug\n- [ ] Buy bread\n')
        file_b:close()
        local original_input = vim.ui.input
        vim.ui.input = function(_, on_confirm) ---@diagnostic disable-line: duplicate-set-field
            on_confirm('buy')
        end

        vault.search()

        vim.ui.input = original_input
        local qflist = vim.fn.getqflist()

        assert.are.equal(2, #qflist)
        assert.truthy(vim.api.nvim_buf_get_name(qflist[1].bufnr):match('proj%-a/todos%.md$'))
        assert.are.equal(1, qflist[1].lnum)
        assert.are.equal('- [ ] buy milk', qflist[1].text)
        assert.truthy(vim.api.nvim_buf_get_name(qflist[2].bufnr):match('proj%-b/todos%.md$'))
        assert.are.equal(2, qflist[2].lnum)
        assert.are.equal('- [ ] Buy bread', qflist[2].text)
    end)

    it('produces an empty quickfix list when the search query has no matches', function()
        vault.setup({
            vault_path = test_vault,
            todos_path = test_vault,
        })
        vim.fn.mkdir(test_vault .. '/proj-a', 'p')
        local file_a = io.open(test_vault .. '/proj-a/todos.md', 'w')
        file_a:write('- [ ] buy milk\n')
        file_a:close()
        local original_input = vim.ui.input
        vim.ui.input = function(_, on_confirm) ---@diagnostic disable-line: duplicate-set-field
            on_confirm('nonexistent')
        end

        vault.search()

        vim.ui.input = original_input

        assert.are.equal(0, #vim.fn.getqflist())
    end)

    it('does nothing when the search prompt is cancelled', function()
        vault.setup({
            vault_path = test_vault,
            todos_path = test_vault,
        })
        local qflist_count_before = vim.fn.getqflist({ nr = '$' }).nr
        local original_input = vim.ui.input
        vim.ui.input = function(_, on_confirm) ---@diagnostic disable-line: duplicate-set-field
            on_confirm(nil)
        end

        vault.search()

        vim.ui.input = original_input

        assert.are.equal(qflist_count_before, vim.fn.getqflist({ nr = '$' }).nr)
    end)

    it('calls Telescope live_grep with the right options when Telescope is available', function()
        vault.setup({
            vault_path = test_vault,
            todos_path = test_vault,
        })
        local captured_opts
        package.loaded['telescope.builtin'] = {
            live_grep = function(opts)
                captured_opts = opts
            end,
        }

        vault.search('buy')

        package.loaded['telescope.builtin'] = nil

        assert.are.same({ resolve(test_vault) }, { resolve(captured_opts.search_dirs[1]) })
        assert.are.equal('**/*.md', captured_opts.glob_pattern)
        assert.are.equal('buy', captured_opts.default_text)
    end)

    it('scopes the fallback search to todos.md files with a leading "todos" keyword', function()
        vault.setup({
            vault_path = test_vault,
            todos_path = test_vault,
        })
        vim.fn.mkdir(test_vault .. '/proj-a', 'p')
        local todos_file = io.open(test_vault .. '/proj-a/todos.md', 'w')
        todos_file:write('- [ ] buy milk\n')
        todos_file:close()
        local other_file = io.open(test_vault .. '/proj-a/other.md', 'w')
        other_file:write('buy stamps\n')
        other_file:close()

        vault.search('todos buy')

        local qflist = vim.fn.getqflist()

        assert.are.equal(1, #qflist)
        assert.truthy(vim.api.nvim_buf_get_name(qflist[1].bufnr):match('proj%-a/todos%.md$'))
    end)

    it('scopes Telescope live_grep to todos_root with a leading "todos" keyword', function()
        vault.setup({
            vault_path = test_vault,
            todos_path = test_vault,
        })
        local captured_opts
        package.loaded['telescope.builtin'] = {
            live_grep = function(opts)
                captured_opts = opts
            end,
        }

        vault.search('todos buy')

        package.loaded['telescope.builtin'] = nil

        assert.are.same({ resolve(test_vault) }, { resolve(captured_opts.search_dirs[1]) })
        assert.are.equal('*/todos.md', captured_opts.glob_pattern)
        assert.are.equal('buy', captured_opts.default_text)
    end)

    it('prompts with the scope name when given a bare scope keyword and no query', function()
        vault.setup({
            vault_path = test_vault,
            todos_path = test_vault,
        })
        local captured_prompt
        local original_input = vim.ui.input
        vim.ui.input = function(opts, on_confirm) ---@diagnostic disable-line: duplicate-set-field
            captured_prompt = opts.prompt
            on_confirm(nil)
        end

        vault.search('todos')

        vim.ui.input = original_input

        assert.truthy(captured_prompt:match('todos'))
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

    it('does not set global keymaps when opts.keys is omitted', function()
        vault.setup({
            vault_path = test_vault,
            todos_path = test_vault,
        })

        assert.are.equal('', vim.fn.maparg('<leader>vt', 'n'))
    end)

    it('sets the default global keymaps when opts.keys = true', function()
        vault.setup({
            vault_path = test_vault,
            todos_path = test_vault,
            keys = true,
        })

        assert.truthy(vim.fn.maparg('<leader>vt', 'n') ~= '')
    end)

    it('overrides a single global keymap while keeping other defaults when opts.keys is a table', function()
        vault.setup({
            vault_path = test_vault,
            todos_path = test_vault,
            keys = { toggle_todo = '<leader>x' },
        })

        assert.truthy(vim.fn.maparg('<leader>x', 'n') ~= '')
        assert.are.equal('', vim.fn.maparg('<leader>vt', 'n'))
        assert.truthy(vim.fn.maparg('<leader>vs', 'n') ~= '')
    end)

    it('keeps buffer-local keymaps active inside todos.md even when opts.keys is omitted', function()
        vault.setup({
            vault_path = test_vault,
            todos_path = test_vault,
        })

        vault.toggle_todo()

        assert.truthy(vim.fn.maparg('<leader>vc', 'n') ~= '')
    end)

    it('overrides a buffer-local keymap via opts.keys without opting into global keymaps', function()
        vault.setup({
            vault_path = test_vault,
            todos_path = test_vault,
            keys = { toggle_checkbox = false },
        })

        vault.toggle_todo()

        assert.are.equal('', vim.fn.maparg('<leader>vc', 'n'))
        assert.truthy(vim.fn.maparg('<leader>va', 'n') ~= '')
        assert.are.equal('', vim.fn.maparg('<leader>vt', 'n'))
    end)
end)
