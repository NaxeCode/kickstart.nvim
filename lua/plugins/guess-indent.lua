local indent_width = require('config.style').indent_width

return {
    'NMAC427/guess-indent.nvim',
    opts = {
        on_tab_options = {
            expandtab = false,
            tabstop = indent_width,
            softtabstop = indent_width,
            shiftwidth = indent_width,
        },
        on_space_options = {
            expandtab = true,
            tabstop = indent_width,
            softtabstop = indent_width,
            shiftwidth = indent_width,
        },
    },
}
