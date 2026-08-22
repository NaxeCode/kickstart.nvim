local M = {}

local function run(profile)
    return function() require('custom.swift_tasks').run(profile) end
end

function M.setup()
    if vim.fn.has 'macunix' == 0 then return end

    local developer_dir = vim.env.DEVELOPER_DIR
    if not developer_dir or developer_dir == '' then
        local default_developer_dir = '/Applications/Xcode.app/Contents/Developer'
        if vim.fn.isdirectory(default_developer_dir) == 1 then vim.env.DEVELOPER_DIR = default_developer_dir end
    end

    vim.keymap.set('n', '<leader>aa', run 'auto', { desc = 'Apple: verify changed targets' })
    vim.keymap.set('n', '<leader>af', run 'fast', { desc = 'Apple: core tests + simulator build' })
    vim.keymap.set('n', '<leader>au', run 'ui', { desc = 'Apple: iOS UI verification' })
    vim.keymap.set('n', '<leader>aw', run 'watch', { desc = 'Apple: watchOS verification' })
    vim.keymap.set('n', '<leader>aF', run 'full', { desc = 'Apple: full verification' })
    vim.keymap.set('n', '<leader>as', function() require('custom.swift_tasks').stop() end, { desc = 'Apple: stop verification' })
    vim.keymap.set('n', '<leader>ad', '<cmd>OverseerToggle<cr>', { desc = 'Apple: toggle build and test dock' })
    vim.keymap.set('n', '<leader>ae', function() require('telescope.builtin').diagnostics { bufnr = 0 } end, { desc = 'Apple: buffer errors and warnings' })
    vim.keymap.set('n', '<leader>ao', function()
        local root = require('custom.swift_tasks').root()
        if root then
            vim.ui.open(root .. '/apple/AuraGainz.xcodeproj')
        else
            vim.notify('No Aura Gainz Apple project found.', vim.log.levels.ERROR)
        end
    end, { desc = 'Apple: open Xcode project' })
end

return M
