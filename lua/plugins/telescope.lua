local M = {}

function M.setup()
    require('telescope').setup {
        extensions = {
            ['ui-select'] = { require('telescope.themes').get_dropdown() },
        },
    }
    pcall(require('telescope').load_extension, 'fzf')
    pcall(require('telescope').load_extension, 'ui-select')

    local builtin = require 'telescope.builtin'
    local function project_root()
        return vim.fs.root(0, { 'package.json', 'pnpm-workspace.yaml', 'Project.xml', 'Package.swift', 'Makefile', '.git' }) or vim.uv.cwd()
    end

    vim.keymap.set('n', '<leader>sh', builtin.help_tags, { desc = '[S]earch [H]elp' })
    vim.keymap.set('n', '<leader>sk', builtin.keymaps, { desc = '[S]earch [K]eymaps' })
    vim.keymap.set('n', '<leader>sf', function() builtin.find_files { cwd = project_root(), hidden = true } end, { desc = '[S]earch project [F]iles' })
    vim.keymap.set('n', '<leader>ss', builtin.builtin, { desc = '[S]earch [S]elect Telescope' })
    vim.keymap.set(
        'n',
        '<leader>sw',
        function() builtin.grep_string { cwd = project_root(), additional_args = { '--hidden' } } end,
        { desc = '[S]earch project for current [W]ord' }
    )
    vim.keymap.set(
        'n',
        '<leader>sg',
        function() builtin.live_grep { cwd = project_root(), additional_args = { '--hidden' } } end,
        { desc = '[S]earch project by [G]rep' }
    )
    vim.keymap.set('n', '<leader>sd', builtin.diagnostics, { desc = '[S]earch [D]iagnostics' })
    vim.keymap.set('n', '<leader>sr', builtin.resume, { desc = '[S]earch [R]esume' })
    vim.keymap.set('n', '<leader>s.', builtin.oldfiles, { desc = '[S]earch Recent Files ("." for repeat)' })
    vim.keymap.set(
        'n',
        '<leader><leader>',
        function() builtin.buffers { sort_mru = true, ignore_current_buffer = true } end,
        { desc = '[ ] Find existing buffers (MRU)' }
    )
    vim.keymap.set(
        'n',
        '<leader>/',
        function()
            builtin.current_buffer_fuzzy_find(require('telescope.themes').get_dropdown {
                winblend = 10,
                previewer = false,
            })
        end,
        { desc = '[/] Fuzzily search in current buffer' }
    )
    vim.keymap.set(
        'n',
        '<leader>s/',
        function() builtin.live_grep { grep_open_files = true, prompt_title = 'Live Grep in Open Files' } end,
        { desc = '[S]earch [/] in Open Files' }
    )
    vim.keymap.set('n', '<leader>sn', function() builtin.find_files { cwd = vim.fn.stdpath 'config' } end, { desc = '[S]earch [N]eovim files' })
end

return M
