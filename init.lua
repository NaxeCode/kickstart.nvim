-- Cache compiled Lua modules to reduce startup work.
vim.loader.enable()

require 'config.options'
require 'config.keymaps'
require 'config.autocmds'
require 'config.pack'
