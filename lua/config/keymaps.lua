local keymap = vim.keymap.set
local opts = { noremap = true, silent = true }

-- .NET specific keymaps
keymap('n', '<leader>bb', '<cmd>make<cr>', { desc = 'Build project' })
keymap('n', '<leader>rr', '<cmd>!dotnet run<cr>', { desc = 'Run project' })
keymap('n', '<leader>qf', '<cmd>copen<cr>', { desc = 'Open quickfix' })
keymap('n', '<leader>qn', '<cmd>cnext<cr>', { desc = 'Next quickfix item' })
keymap('n', '<leader>qp', '<cmd>cprev<cr>', { desc = 'Previous quickfix item' })

-- Default keymaps
keymap('n', '<leader>nh', '<cmd>nohl<cr>', { desc = 'No highlight' })
