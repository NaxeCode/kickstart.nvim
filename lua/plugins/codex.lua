local M = {}

function M.setup()
    require('codex').setup {
        split = 'float',
        focus_after_send = true,
        autostart = false,
        log_level = 'warn',
    }
    vim.keymap.set('n', '<leader>ca', function() require('codex').toggle() end, { desc = '[C]odex [A]sk (toggle)' })
    vim.keymap.set('x', '<leader>ca', function() require('codex').actions.send_selection() end, { desc = '[C]odex [A]sk selection' })
    vim.keymap.set('n', '<leader>cb', function() require('codex').actions.send_buffer() end, { desc = '[C]odex send [B]uffer' })
end

return M
