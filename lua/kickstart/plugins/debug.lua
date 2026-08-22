-- debug.lua
--
-- Shows how to use the DAP plugin to debug your code.
--
-- Primarily focused on configuring the debugger for Go, but can
-- be extended to other languages as well. That's why it's called
-- kickstart.nvim and not kitchen-sink.nvim ;)

local function save_modified_buffers()
    local ok, err = pcall(function() vim.cmd.wall() end)
    if not ok then
        vim.notify(('Could not save modified buffers; debugger not started:\n%s'):format(err), vim.log.levels.ERROR)
        return false
    end
    return true
end

local debugger_terminating = false
local relaunch_requested = false

local function start_or_continue()
    local dap = require 'dap'
    if debugger_terminating then
        relaunch_requested = true
        vim.notify('Debugger is closing; it will reopen when ready.', vim.log.levels.INFO)
        return
    end

    if not dap.session() and not save_modified_buffers() then return end
    dap.continue()
end

local function terminate_debugger()
    local dap = require 'dap'
    if not dap.session() then
        vim.notify('No active debugger.', vim.log.levels.INFO)
        return
    end

    debugger_terminating = true
    dap.terminate {
        on_done = function()
            debugger_terminating = false
            if not relaunch_requested then return end

            relaunch_requested = false
            vim.schedule(start_or_continue)
        end,
    }
end

local function run_last()
    if not save_modified_buffers() then return end
    require('dap').run_last()
end

local M = {}

function M.setup()
    vim.keymap.set('n', '<F5>', start_or_continue, { desc = 'Debug: Start/Continue' })
    vim.keymap.set('n', '<F8>', terminate_debugger, { desc = 'Debug: Terminate' })
    vim.keymap.set('n', '<F9>', function() require('dap').toggle_breakpoint() end, { desc = 'Debug: Toggle Breakpoint' })
    vim.keymap.set('n', '<F10>', function() require('dap').step_over() end, { desc = 'Debug: Step Over' })
    vim.keymap.set('n', '<F11>', function() require('dap').step_into() end, { desc = 'Debug: Step Into' })
    vim.keymap.set('n', '<S-F11>', function() require('dap').step_out() end, { desc = 'Debug: Step Out' })
    vim.keymap.set('n', '<leader>dc', start_or_continue, { desc = '[D]ebug: Start/[C]ontinue' })
    vim.keymap.set('n', '<leader>db', function() require('dap').toggle_breakpoint() end, { desc = '[D]ebug: Toggle [B]reakpoint' })
    vim.keymap.set('n', '<leader>dB', function()
        local condition = vim.fn.input 'Breakpoint condition: '
        if condition ~= '' then require('dap').set_breakpoint(condition) end
    end, { desc = '[D]ebug: Conditional [B]reakpoint' })
    vim.keymap.set('n', '<leader>dl', function()
        local message = vim.fn.input 'Log point message: '
        if message ~= '' then require('dap').set_breakpoint(nil, nil, message) end
    end, { desc = '[D]ebug: [L]og Point' })
    vim.keymap.set('n', '<leader>dg', function() require('dap').run_to_cursor() end, { desc = '[D]ebug: Run to Cursor' })
    vim.keymap.set('n', '<leader>dn', function() require('dap').step_over() end, { desc = '[D]ebug: Step Over/[N]ext' })
    vim.keymap.set('n', '<leader>di', function() require('dap').step_into() end, { desc = '[D]ebug: Step [I]nto' })
    vim.keymap.set('n', '<leader>do', function() require('dap').step_out() end, { desc = '[D]ebug: Step [O]ut' })
    vim.keymap.set('n', '<leader>dr', run_last, { desc = '[D]ebug: [R]un Last' })
    vim.keymap.set('n', '<leader>dt', terminate_debugger, { desc = '[D]ebug: [T]erminate' })
    vim.keymap.set('n', '<leader>du', function() require('dapui').toggle() end, { desc = '[D]ebug: Toggle [U]I' })
    vim.keymap.set({ 'n', 'v' }, '<leader>de', function() require('dapui').eval() end, { desc = '[D]ebug: [E]valuate' })

    local dap = require 'dap'
    local dapui = require 'dapui'

    require('mason-nvim-dap').setup {
        -- Makes a best effort to setup the various debuggers with
        -- reasonable debug configurations
        automatic_installation = true,

        -- You can provide additional configuration to the handlers,
        -- see mason-nvim-dap README for more information
        handlers = {},

        -- You'll need to check that you have the required things installed
        -- online, please don't ask me how to install them :)
        ensure_installed = {
            -- Update this to ensure that you have the debuggers for the langs you want
            'delve',
            -- C/C++ (raylib projects)
            'codelldb',
        },
    }

    -- Dap UI setup
    -- For more information, see |:help nvim-dap-ui|
    ---@diagnostic disable-next-line: missing-fields
    dapui.setup {
        -- Set icons to characters that are more likely to work in every terminal.
        --    Feel free to remove or use ones that you like more! :)
        --    Don't feel like these are good choices.
        icons = { expanded = '▾', collapsed = '▸', current_frame = '*' },
        ---@diagnostic disable-next-line: missing-fields
        controls = {
            icons = {
                pause = '⏸',
                play = '▶',
                step_into = '⏎',
                step_over = '⏭',
                step_out = '⏮',
                step_back = 'b',
                run_last = '▶▶',
                terminate = '⏹',
                disconnect = '⏏',
            },
        },
    }

    local breakpoint_icons = vim.g.have_nerd_font
            and { Breakpoint = '', BreakpointCondition = '', BreakpointRejected = '', LogPoint = '', Stopped = '' }
        or { Breakpoint = '●', BreakpointCondition = '◆', BreakpointRejected = '×', LogPoint = '◆', Stopped = '▶' }
    vim.api.nvim_set_hl(0, 'DapBreakpoint', { fg = '#e51400' })
    vim.api.nvim_set_hl(0, 'DapStopped', { fg = '#ffcc00' })
    for type, icon in pairs(breakpoint_icons) do
        local name = 'Dap' .. type
        local highlight = type == 'Stopped' and 'DapStopped' or 'DapBreakpoint'
        vim.fn.sign_define(name, { text = icon, texthl = highlight, numhl = highlight })
    end

    dap.listeners.after.event_initialized['dapui_config'] = function()
        pcall(function() require('overseer.window').close() end)
        dapui.open()
    end
    dap.listeners.before.event_terminated['dapui_config'] = dapui.close
    dap.listeners.before.event_exited['dapui_config'] = dapui.close
    dap.listeners.before.terminate['dapui_config'] = dapui.close
    dap.listeners.before.disconnect['dapui_config'] = dapui.close

    local codelldb = vim.fn.exepath 'codelldb'
    if codelldb == '' then codelldb = vim.fn.stdpath 'data' .. '/mason/bin/codelldb' end
    dap.adapters.codelldb = {
        type = 'server',
        port = '${port}',
        executable = {
            command = codelldb,
            args = { '--port', '${port}' },
        },
    }

    local c_tasks = require 'custom.c_tasks'
    c_tasks.register()

    local function c_root() return c_tasks.root() or vim.fn.getcwd() end

    dap.configurations.c = {
        {
            name = 'Launch game (build + codelldb)',
            type = 'codelldb',
            request = 'launch',
            program = function()
                if not save_modified_buffers() then error 'Could not save source before debugging' end
                return c_root() .. '/game'
            end,
            cwd = c_root,
            stopOnEntry = false,
            terminal = 'console',
            preLaunchTask = 'C: build (debug)',
        },
    }
    dap.configurations.cpp = vim.deepcopy(dap.configurations.c)

    -- Install golang specific config
    require('dap-go').setup {
        delve = {
            -- On Windows delve must be run attached or it crashes.
            -- See https://github.com/leoluz/nvim-dap-go/blob/main/README.md#configuring
            detached = vim.fn.has 'win32' == 0,
        },
    }
end

return M
