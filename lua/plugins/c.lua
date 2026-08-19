-- C / raylib project support.
--
-- LSP (clangd) is configured in lua/plugins/lsp.lua; Tree-sitter already installs
-- the `c` parser in lua/plugins/treesitter.lua. This spec only adds keymaps -
-- the Overseer task definitions live in lua/custom/c_tasks.lua so that
-- lua/plugins/overseer.lua remains the single owner of overseer's `config`.
--
-- Keymaps live under <leader>m ("make"), since <leader>c is the Codex group and
-- <leader>x is already taken by the HaxeFlixel/Garden task set.
--
-- Requires the system raylib package: `sudo pacman -S raylib`

local function run(name, opts)
    return function() require('custom.c_tasks').run(name, opts) end
end

return {
    'stevearc/overseer.nvim',
    optional = true,
    keys = {
        { '<leader>mb', run 'C: build (debug)', desc = 'C: build (debug)' },
        {
            '<leader>mr',
            run('C: run (debug)', { save = true, close_on_success = true }),
            desc = 'C: save + run/restart (debug)',
        },
        { '<leader>mR', run 'C: build (release)', desc = 'C: build (release)' },
        { '<leader>mz', run 'C: size report', desc = 'C: binary size report' },
        { '<leader>mk', run 'C: clean', desc = 'C: clean' },
        { '<leader>mg', run 'C: generate compile_flags.txt', desc = 'C: generate compile_flags.txt' },
        { '<leader>ms', function() require('custom.c_tasks').stop() end, desc = 'C: stop running task' },
        { '<leader>md', '<cmd>OverseerToggle<cr>', desc = 'C: toggle Overseer dock' },
    },
}
