local keymap = vim.keymap.set
local opts = { noremap = true, silent = true }

local function save_all_and_quit()
    local ok, err = pcall(function()
        vim.cmd.wall()
        vim.cmd.qa()
    end)
    if not ok then vim.notify(('Could not close Neovim safely:\n%s'):format(err), vim.log.levels.ERROR) end
end

local function toggle_key_bank()
    local module_name = 'custom.key_bank'
    local key_bank = package.loaded[module_name]
    if key_bank and key_bank.win and vim.api.nvim_win_is_valid(key_bank.win) then
        key_bank.close()
        return
    end

    package.loaded[module_name] = nil
    require(module_name).toggle()
end

local function close_current_split()
    if #vim.api.nvim_list_wins() == 1 then
        vim.notify('This is the last split; use Space q q to close Neovim.', vim.log.levels.INFO)
        return
    end

    local ok, err = pcall(vim.api.nvim_win_close, 0, false)
    if not ok then vim.notify(('Could not close this split safely:\n%s'):format(err), vim.log.levels.WARN) end
end

-- .NET specific keymaps
keymap('n', '<leader>bb', '<cmd>make<cr>', { desc = 'Build project' })
keymap('n', '<leader>rr', '<cmd>!dotnet run<cr>', { desc = 'Run project' })
keymap('n', '<leader>qf', '<cmd>copen<cr>', { desc = 'Open quickfix' })
keymap('n', '<leader>qn', '<cmd>cnext<cr>', { desc = 'Next quickfix item' })
keymap('n', '<leader>qp', '<cmd>cprev<cr>', { desc = 'Previous quickfix item' })

-- Default keymaps
keymap('n', '<leader>nh', '<cmd>nohl<cr>', { desc = 'No highlight' })
keymap('n', '<leader>k', toggle_key_bank, { desc = 'Open active key bank' })
keymap('n', '<leader>w', '<cmd>write<cr>', { desc = 'Save current file' })
keymap('n', '<leader>qq', save_all_and_quit, { desc = 'Save all and close Neovim' })
keymap('n', '<leader>qc', close_current_split, { desc = 'Close current split' })
keymap('n', '<leader>p=', '<cmd>wincmd =<cr>', { desc = 'Equalize split sizes' })
keymap('n', '<C-h>', '<cmd>wincmd h<cr>', { desc = 'Focus left split' })
keymap('n', '<C-j>', '<cmd>wincmd j<cr>', { desc = 'Focus lower split' })
keymap('n', '<C-k>', '<cmd>wincmd k<cr>', { desc = 'Focus upper split' })
keymap('n', '<C-l>', '<cmd>wincmd l<cr>', { desc = 'Focus right split' })
keymap('n', '<M-h>', '<cmd>vertical resize -4<cr>', { desc = 'Make split narrower' })
keymap('n', '<M-l>', '<cmd>vertical resize +4<cr>', { desc = 'Make split wider' })
keymap('n', '<M-j>', '<cmd>resize -2<cr>', { desc = 'Make split shorter' })
keymap('n', '<M-k>', '<cmd>resize +2<cr>', { desc = 'Make split taller' })
