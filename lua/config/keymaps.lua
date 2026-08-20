local keymap = vim.keymap.set
local opts = { noremap = true, silent = true }

local function save_and_close_current()
    local bufnr = vim.api.nvim_get_current_buf()
    local winid = vim.api.nvim_get_current_win()

    if vim.bo[bufnr].modified then
        local name = vim.api.nvim_buf_get_name(bufnr)
        if vim.bo[bufnr].buftype ~= '' or name == '' then
            vim.notify('This modified buffer has no normal file to save.', vim.log.levels.WARN)
            return
        end

        local saved, save_error = pcall(vim.api.nvim_buf_call, bufnr, function() vim.cmd.write() end)
        if not saved then
            vim.notify(('Could not save this buffer:\n%s'):format(save_error), vim.log.levels.ERROR)
            return
        end
    end

    if #vim.api.nvim_list_wins() > 1 then
        local closed, close_error = pcall(vim.api.nvim_win_close, winid, false)
        if not closed then
            vim.notify(('Could not close this split safely:\n%s'):format(close_error), vim.log.levels.WARN)
            return
        end
        if vim.api.nvim_buf_is_valid(bufnr) and #vim.fn.win_findbuf(bufnr) == 0 then pcall(vim.api.nvim_buf_delete, bufnr, { force = false }) end
        return
    end

    local deleted, delete_error = pcall(vim.api.nvim_buf_delete, bufnr, { force = false })
    if not deleted then vim.notify(('Could not close this buffer safely:\n%s'):format(delete_error), vim.log.levels.WARN) end
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
        vim.notify('This is the last split; use Space q q to save and close its buffer.', vim.log.levels.INFO)
        return
    end

    local ok, err = pcall(vim.api.nvim_win_close, 0, false)
    if not ok then vim.notify(('Could not close this split safely:\n%s'):format(err), vim.log.levels.WARN) end
end

local function move_vertical_divider(direction)
    local current = vim.fn.winnr()
    local opposite = direction == 'h' and 'l' or 'h'
    local has_window_toward = vim.fn.winnr(direction) ~= current
    local has_window_away = vim.fn.winnr(opposite) ~= current
    if not has_window_toward and not has_window_away then
        vim.notify('No vertical split divider to move.', vim.log.levels.INFO)
        return
    end

    local delta = has_window_toward and 4 or -4
    vim.cmd(('vertical resize %+d'):format(delta))
end

local function move_horizontal_divider(direction)
    local current = vim.fn.winnr()
    local opposite = direction == 'k' and 'j' or 'k'
    local has_window_toward = vim.fn.winnr(direction) ~= current
    local has_window_away = vim.fn.winnr(opposite) ~= current
    if not has_window_toward and not has_window_away then
        vim.notify('No horizontal split divider to move.', vim.log.levels.INFO)
        return
    end

    local delta = has_window_toward and 2 or -2
    vim.cmd(('resize %+d'):format(delta))
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
keymap('n', '<leader>qq', save_and_close_current, { desc = 'Save and close current buffer/split' })
keymap('n', '<leader>qc', close_current_split, { desc = 'Close current split' })
keymap('n', '<leader>p=', '<cmd>wincmd =<cr>', { desc = 'Equalize split sizes' })
keymap('n', '<C-h>', '<cmd>wincmd h<cr>', { desc = 'Focus left split' })
keymap('n', '<C-j>', '<cmd>wincmd j<cr>', { desc = 'Focus lower split' })
keymap('n', '<C-k>', '<cmd>wincmd k<cr>', { desc = 'Focus upper split' })
keymap('n', '<C-l>', '<cmd>wincmd l<cr>', { desc = 'Focus right split' })
keymap('n', '<M-h>', function() move_vertical_divider 'h' end, { desc = 'Move vertical divider left' })
keymap('n', '<M-l>', function() move_vertical_divider 'l' end, { desc = 'Move vertical divider right' })
keymap('n', '<M-j>', function() move_horizontal_divider 'j' end, { desc = 'Move horizontal divider down' })
keymap('n', '<M-k>', function() move_horizontal_divider 'k' end, { desc = 'Move horizontal divider up' })
