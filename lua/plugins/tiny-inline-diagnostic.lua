return {
    'rachartier/tiny-inline-diagnostic.nvim',
    ft = 'c',
    config = function()
        local c_filetypes = { c = true }
        local disabled_filetypes = vim.tbl_filter(
            function(filetype) return not c_filetypes[filetype] end,
            vim.fn.getcompletion('', 'filetype')
        )

        require('tiny-inline-diagnostic').setup {
            preset = 'classic',
            transparent_bg = true,
            disabled_ft = disabled_filetypes,
            options = {
                show_source = {
                    enabled = true,
                    if_many = false,
                },
                multilines = {
                    enabled = true,
                    always_show = false,
                    trim_whitespaces = true,
                    tabstop = 4,
                },
                show_all_diags_on_cursorline = true,
                enable_on_insert = false,
                overflow = {
                    mode = 'wrap',
                    padding = 2,
                },
                break_line = {
                    enabled = true,
                    after = 80,
                },
                softwrap = 30,
            },
        }
    end,
}
