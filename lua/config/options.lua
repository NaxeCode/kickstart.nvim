vim.g.mapleader = ' '
vim.g.maplocalleader = ' '

-- For NuShell to convert all \\ to /
-- vim.opt.shellslash = true

-- Set to true if you have a Nerd Font installed and selected in the terminal
vim.g.have_nerd_font = true

-- Make line numbers default
vim.o.number = true
vim.o.relativenumber = true

-- Enable mouse mode
vim.o.mouse = 'a'

-- Don't show the mode, since it's already in the status line
vim.o.showmode = false

-- Sync clipboard between OS and Neovim.
vim.schedule(function()
  vim.o.clipboard = 'unnamedplus'
end)

-- Enable break indent
vim.o.breakindent = true

-- Save undo history
vim.o.undofile = true

-- Case-insensitive searching unless capitals are used.
vim.o.ignorecase = true
vim.o.smartcase = true

-- Keep signcolumn on by default
vim.o.signcolumn = 'yes'

-- Decrease update time
vim.o.updatetime = 250

-- Decrease mapped sequence wait time
vim.o.timeoutlen = 300

-- Configure split behavior
vim.o.splitright = true
vim.o.splitbelow = true

-- Display whitespace chars
vim.o.list = true
vim.opt.listchars = { tab = '» ', trail = '·', nbsp = '␣' }

-- Preview substitutions live
vim.o.inccommand = 'split'

-- Show cursor line
vim.o.cursorline = true

-- Keep lines above/below cursor
vim.o.scrolloff = 10

-- Indentation
vim.opt.expandtab = true
vim.opt.shiftwidth = 2
vim.opt.tabstop = 2
vim.opt.softtabstop = 2

-- Confirm unsaved changes on quit
vim.o.confirm = true

-- For Quantum files
vim.filetype.add {
  extension = {
    quantum = 'json',
  },
}
