local M = {}

local ROOT_MARKERS = { 'buildServer.json', 'apple/project.yml' }
local SWIFT_ERRORFORMAT = table.concat({
    '%E%f:%l:%c: fatal error: %m',
    '%E%f:%l:%c: error: %m',
    '%W%f:%l:%c: warning: %m',
    '%I%f:%l:%c: note: %m',
    '%E%f:%l: error: %m',
    '%W%f:%l: warning: %m',
    '%I%f:%l: note: %m',
    '%f:%l:%c: %m',
}, ',')

local profiles = {
    auto = 'Select core, iOS, UI, and watch checks from the changed Apple files',
    fast = 'Run Swift package tests and build the iOS/watchOS simulator application',
    ui = 'Run Swift package tests, simulator build, and iOS UI tests',
    watch = 'Run Swift package tests and watchOS tests',
    full = 'Run every core, iOS, UI, and watchOS validation profile',
}

local registered = false

local function apple_root()
    local path = vim.api.nvim_buf_get_name(0)
    if path == '' then path = vim.fn.getcwd() end
    return vim.fs.root(path, ROOT_MARKERS)
end

local function task_components()
    return {
        { 'unique', replace = false, restart_interrupts = true },
        {
            'on_output_quickfix',
            errorformat = SWIFT_ERRORFORMAT,
            items_only = true,
            set_diagnostics = true,
            tail = false,
        },
        { 'on_result_diagnostics', remove_on_restart = true },
        { 'open_output', on_start = 'always', on_complete = 'failure', direction = 'dock', focus = false },
        'default',
    }
end

local function register_templates()
    if registered then return end
    registered = true

    local overseer = require 'overseer'
    for profile, description in pairs(profiles) do
        local task_name = 'Apple verify: ' .. profile
        overseer.register_template {
            name = task_name,
            desc = description,
            tags = { overseer.TAG.BUILD, overseer.TAG.TEST },
            condition = {
                callback = function(search)
                    local dir = search and search.dir or vim.fn.getcwd()
                    local root = vim.fs.root(dir, ROOT_MARKERS)
                    return root ~= nil and vim.fn.executable(root .. '/bin/apple-verify') == 1
                end,
            },
            builder = function(params)
                local root = params.cwd or apple_root() or vim.fn.getcwd()
                return {
                    name = task_name,
                    cmd = root .. '/bin/apple-verify',
                    args = { profile },
                    cwd = root,
                    strategy = { 'jobstart', use_terminal = false },
                    components = task_components(),
                }
            end,
        }
    end
end

local function save_modified_buffers()
    local ok, err = pcall(function() vim.cmd.wall() end)
    if not ok then
        vim.notify(('Could not save modified buffers; Apple verification not started:\n%s'):format(err), vim.log.levels.ERROR)
        return false
    end
    return true
end

function M.root() return apple_root() end

function M.run(profile)
    if not profiles[profile] then
        vim.notify('Unknown Apple verification profile: ' .. tostring(profile), vim.log.levels.ERROR)
        return
    end
    if not save_modified_buffers() then return end

    local root = apple_root()
    if not root or vim.fn.executable(root .. '/bin/apple-verify') ~= 1 then
        vim.notify('No Aura Gainz Apple verifier found. Open a file under the Aura Gainz repository.', vim.log.levels.ERROR)
        return
    end

    register_templates()
    require('overseer').run_task({
        name = 'Apple verify: ' .. profile,
        cwd = root,
        search_params = { dir = root },
        autostart = false,
    }, function(task, err)
        if not task then
            vim.notify(err or ('Could not create Apple verification task: ' .. profile), vim.log.levels.ERROR)
            return
        end
        task:start()
    end)
end

function M.stop()
    local root = apple_root()
    local stopped = 0
    for _, task in ipairs(require('overseer').list_tasks()) do
        if task.name and task.name:match '^Apple verify:' and (not root or not task.cwd or task.cwd == root) and task:is_running() and task:stop() then
            stopped = stopped + 1
        end
    end

    if stopped > 0 then
        vim.notify(('Stopped %d Apple verification task%s.'):format(stopped, stopped == 1 and '' or 's'), vim.log.levels.INFO)
    else
        vim.notify('No running Apple verification task found.', vim.log.levels.INFO)
    end
end

M._test = {
    errorformat = SWIFT_ERRORFORMAT,
    profiles = profiles,
}

return M
