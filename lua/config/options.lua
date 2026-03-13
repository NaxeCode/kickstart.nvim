local opt = vim.opt

-- Line numbers
opt.number = true
opt.relativenumber = true

-- Tabs & Indents
opt.tabstop = 2
opt.shiftwidth = 2
opt.expandtab = true
opt.autoindent = true

-- Search
opt.ignorecase = true
opt.smartcase = true

-- Split windows
opt.splitright = true
opt.splitbelow = true

-- UI
opt.termguicolors = true
opt.background = 'dark'
opt.cursorline = true

-- Backups
opt.backup = false
opt.writebackup = false
opt.swapfile = false

-- Folding
opt.foldmethod = 'indent'
opt.foldlevel = 99

-- File encoding
opt.fileencoding = 'utf-8'

-- Command line
opt.cmdheight = 1

-- Completion
opt.completeopt = { 'menuone', 'noselect' }

-- Better display for messages
opt.shortmess:append 'c'

-- Enable mouse
opt.mouse = 'a'

-- Set clipboard to use system clipboard
opt.clipboard = 'unnamedplus'
