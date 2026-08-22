local M = {}

function M.setup()
    local function tutor() return require 'custom.c_tutor' end

    vim.keymap.set('n', '<leader>mt', function() tutor().toggle() end, { desc = 'Tutor: cycle mode' })
    vim.keymap.set('n', '<leader>me', function() tutor().explain_diagnostic() end, { desc = 'Tutor: explain diagnostic' })
    vim.keymap.set('n', '<leader>mm', function() tutor().more() end, { desc = 'Tutor: deeper hint' })
    vim.keymap.set('n', '<leader>mu', function() tutor().reroll() end, { desc = 'Tutor: reroll response, bypass cache' })
    vim.keymap.set('n', '<leader>mx', function() tutor().dismiss() end, { desc = 'Tutor: dismiss' })
end

return M
