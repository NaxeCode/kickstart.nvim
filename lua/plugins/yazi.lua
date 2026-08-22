local M = {}

local function open_in_right_split(chosen_file)
    if vim.fn.isdirectory(chosen_file) == 1 then return end
    vim.cmd('botright vsplit ' .. vim.fn.fnameescape(chosen_file))
    local width = math.min(64, math.max(44, math.floor(vim.o.columns * 0.34)))
    vim.cmd('vertical resize ' .. width)
    vim.wo.winfixwidth = true
end

local function open_in_bottom_split(chosen_file)
    if vim.fn.isdirectory(chosen_file) == 1 then return end
    vim.cmd('botright split ' .. vim.fn.fnameescape(chosen_file))
    local height = math.min(22, math.max(12, math.floor(vim.o.lines * 0.34)))
    vim.cmd('resize ' .. height)
    vim.wo.winfixheight = true
end

function M.setup()
    vim.g.loaded_netrw = 1
    vim.g.loaded_netrwPlugin = 1
    require('yazi').setup {
        open_for_directories = false,
        keymaps = { show_help = '<f1>' },
        integrations = {
            bufdelete_implementation = 'bundled-snacks',
            pick_window_implementation = false,
        },
    }
    vim.keymap.set({ 'n', 'v' }, '<leader>-', '<cmd>Yazi<cr>', { desc = 'Open yazi at the current file' })
    vim.keymap.set(
        { 'n', 'v' },
        '<leader>_',
        function() require('yazi').yazi { open_file_function = open_in_right_split } end,
        { desc = 'Open yazi; select file into right split' }
    )
    vim.keymap.set(
        { 'n', 'v' },
        '<leader>|',
        function() require('yazi').yazi { open_file_function = open_in_bottom_split } end,
        { desc = 'Open yazi; select file into bottom split' }
    )
    vim.keymap.set('n', '<leader>cw', '<cmd>Yazi cwd<cr>', { desc = "Open the file manager in nvim's working directory" })
    vim.keymap.set('n', '<c-up>', '<cmd>Yazi toggle<cr>', { desc = 'Resume the last yazi session' })
end

return M
