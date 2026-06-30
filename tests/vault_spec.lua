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
        vim.notify = function(msg, level)
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
        assert.is_not_nil(file)
        local content = file:read('*a')
        file:close()
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
        assert.are.equal(expected_path, resolve(vim.api.nvim_buf_get_name(buf)))

        vault.toggle_todo()

        assert.are.equal(-1, vim.fn.bufnr(expected_path))
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
        vim.cmd = function(cmd_str)
            if cmd_str == 'silent! write' then
                return
            else
                original_write(cmd_str)
            end
        end

        vault.toggle_todo()

        vim.cmd = original_write

        assert.is_true(vim.bo[buf].modified)
        assert.is_not_equal(-1, vim.fn.bufnr(expected_path))
        assert.are.equal(1, #notifications)
        assert.is_not_nil(notifications[1].msg:match('could not save'))
    end)

    it('aborts deletion and warns if window close fails', function()
        vault.setup({
            vault_path = test_vault,
            todos_path = test_vault,
        })
        local expected_path = resolve(test_vault) .. '/' .. vault.get_project_root() .. '/todos.md'

        vault.toggle_todo()

        vim.api.nvim_win_close = function(win, force)
            error('simulated window close failure')
        end

        vault.toggle_todo()

        assert.is_not_equal(-1, vim.fn.bufnr(expected_path))
        assert.are.equal(1, #notifications)
        assert.is_not_nil(notifications[1].msg:match('could not close all windows'))
    end)
end)
