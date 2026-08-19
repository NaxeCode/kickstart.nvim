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
