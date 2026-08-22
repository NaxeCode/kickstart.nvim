local M = {}

local function run(name, opts)
    return function() require('custom.c_tasks').run(name, opts) end
end

function M.setup()
    vim.keymap.set('n', '<leader>mb', run 'C: build (debug)', { desc = 'C: build (debug)' })
    vim.keymap.set('n', '<leader>ma', run 'C: analyze (deep)', { desc = 'C: deep correctness analysis' })
    vim.keymap.set('n', '<leader>mr', run('C: run (debug)', { save = true, close_on_success = true }), { desc = 'C: save + run/restart (debug)' })
    vim.keymap.set('n', '<leader>mR', run 'C: build (release)', { desc = 'C: build (release)' })
    vim.keymap.set('n', '<leader>mz', run 'C: size report', { desc = 'C: binary size report' })
    vim.keymap.set('n', '<leader>mk', run 'C: clean', { desc = 'C: clean' })
    vim.keymap.set('n', '<leader>mg', run 'C: generate compile_flags.txt', { desc = 'C: generate compile_flags.txt' })
    vim.keymap.set('n', '<leader>ms', function() require('custom.c_tasks').stop() end, { desc = 'C: stop running task' })
    vim.keymap.set('n', '<leader>md', '<cmd>OverseerToggle<cr>', { desc = 'C: toggle Overseer dock' })
    vim.keymap.set('n', '<leader>mt', function() require('custom.c_tutor').toggle() end, { desc = 'C tutor: cycle mode' })
    vim.keymap.set('n', '<leader>me', function() require('custom.c_tutor').explain_diagnostic() end, { desc = 'C tutor: explain diagnostic' })
    vim.keymap.set('n', '<leader>mm', function() require('custom.c_tutor').more() end, { desc = 'C tutor: deeper hint' })
    vim.keymap.set('n', '<leader>mu', function() require('custom.c_tutor').reroll() end, { desc = 'C tutor: reroll response, bypass cache' })
    vim.keymap.set('n', '<leader>mx', function() require('custom.c_tutor').dismiss() end, { desc = 'C tutor: dismiss' })
end

return M
