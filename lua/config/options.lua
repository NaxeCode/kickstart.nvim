vim.g.mapleader = ' '
vim.g.maplocalleader = ' '
vim.g.have_nerd_font = true

local opt = vim.opt

-- Line numbers
opt.number = true
opt.relativenumber = true

-- Tabs & Indents
opt.tabstop = 2
opt.shiftwidth = 2
opt.softtabstop = 2
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

-- Providers
vim.g.python3_host_prog = vim.fn.expand '~/.local/share/nvim/python-provider/bin/python'
vim.g.loaded_ruby_provider = 0
vim.g.loaded_perl_provider = 0

-- Fix treesitter parser path
vim.opt.rtp:prepend(vim.fn.stdpath 'data' .. '/site')

-- Register filetypes early so treesitter/LSP health checks resolve cleanly.
-- Some LSP configs advertise framework-specific filetypes whose names do not
-- match normal filename extensions; mapping them to themselves keeps
-- `:checkhealth vim.lsp` quiet without changing editor behavior.
vim.filetype.add {
  extension = {
    hx = 'haxe',
    hxml = 'hxml',
    nu = 'nu',
    aspnetcorerazor = 'aspnetcorerazor',
    ['astro-markdown'] = 'astro-markdown',
    ['django-html'] = 'django-html',
    edge = 'edge',
    ejs = 'ejs',
    erb = 'erb',
    gohtml = 'gohtml',
    gohtmltmpl = 'gohtmltmpl',
    hbs = 'hbs',
    ['html-eex'] = 'html-eex',
    jade = 'jade',
    leaf = 'leaf',
    mdx = 'mdx',
    njk = 'njk',
    nunjucks = 'nunjucks',
    slim = 'slim',
    postcss = 'postcss',
    sugarss = 'sugarss',
    reason = 'reason',
  },
}

-- Set clipboard to use system clipboard
opt.clipboard = 'unnamedplus'

-- Silence the deprecated lspconfig warning (Neovim 0.11+ noise)
if vim.fn.has 'nvim-0.11' == 1 then
  local deprecate = vim.deprecate
  vim.deprecate = function(name, alternative, version, plugin, backtrace)
    if name and (name:find 'require%("lspconfig"%)' or name:find "require%('lspconfig'%)") then return end
    return deprecate(name, alternative, version, plugin, backtrace)
  end
end
