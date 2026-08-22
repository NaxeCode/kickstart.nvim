local M = {}

function M.setup()
    require('trouble').setup {
        auto_close = true,
        auto_preview = true,
        multiline = true,
    }
    vim.keymap.set('n', '<leader>xx', '<cmd>Trouble diagnostics toggle focus=true<cr>', { desc = 'Problems (Trouble)' })
    vim.keymap.set('n', '<leader>xX', '<cmd>Trouble diagnostics toggle filter.buf=0 focus=true<cr>', { desc = 'Buffer problems (Trouble)' })
    vim.keymap.set('n', '<leader>xq', '<cmd>Trouble qflist toggle focus=true<cr>', { desc = 'Compiler quickfix (Trouble)' })
end

return M
