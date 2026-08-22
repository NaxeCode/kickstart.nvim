local M = {}

function M.setup()
    require('nvim-web-devicons').setup {}
    require('Comment').setup {}
    require('colorizer').setup {
        filetypes = { 'css', 'html', 'tsx', 'jsx' },
        user_default_options = { tailwind = true },
    }
    require('ibl').setup {
        indent = { char = '│' },
        scope = { enabled = true, char = '┃' },
    }
    require('mini.ai').setup { n_lines = 500 }
    require('mini.surround').setup()
end

return M
