local M = {}

local function apple_root()
    local path = vim.api.nvim_buf_get_name(0)
    if path == '' then path = vim.fn.getcwd() end
    return vim.fs.root(path, { 'buildServer.json', 'apple/project.yml' })
end

local function run_verify(profile)
    local root = apple_root()
    if not root or vim.fn.executable(root .. '/bin/apple-verify') ~= 1 then
        vim.notify('No Aura Gainz Apple verifier found. Open a file under the Aura Gainz repository.', vim.log.levels.ERROR)
        return
    end

    local task = require('overseer').new_task {
        name = 'Apple verify: ' .. profile,
        cmd = root .. '/bin/apple-verify',
        args = { profile },
        cwd = root,
        components = {
            { 'unique', replace = false, restart_interrupts = true },
            { 'open_output', on_start = 'always', on_complete = 'failure', direction = 'dock', focus = false },
            'default',
        },
    }
    task:start()
end

function M.setup()
    if vim.fn.has 'macunix' == 0 then return end

    local developer_dir = vim.env.DEVELOPER_DIR
    if not developer_dir or developer_dir == '' then
        local default_developer_dir = '/Applications/Xcode.app/Contents/Developer'
        if vim.fn.isdirectory(default_developer_dir) == 1 then vim.env.DEVELOPER_DIR = default_developer_dir end
    end

    local map = function(lhs, rhs, desc) vim.keymap.set('n', lhs, rhs, { desc = desc }) end
    map('<leader>aa', function() run_verify 'auto' end, '[A]pple verify automatically')
    map('<leader>af', function() run_verify 'fast' end, '[A]pple verify fast')
    map('<leader>au', function() run_verify 'ui' end, '[A]pple verify UI')
    map('<leader>aw', function() run_verify 'watch' end, '[A]pple verify watch')
    map('<leader>aF', function() run_verify 'full' end, '[A]pple verify full')
    map('<leader>ao', function()
        local root = apple_root()
        if root then
            vim.ui.open(root .. '/apple/AuraGainz.xcodeproj')
        else
            vim.notify('No Aura Gainz Apple project found.', vim.log.levels.ERROR)
        end
    end, '[A]pple open Xcode project')
end

return M
