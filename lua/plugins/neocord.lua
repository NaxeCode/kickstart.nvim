return {
    'IogaMaster/neocord',
    event = 'VeryLazy',
    opts = {
        logo_tooltip = 'Neovim',
        main_image = 'language',
        show_time = true,
        global_timer = true,
        blacklist = {
            '.*%.env.*',
            'credentials',
            'secrets',
        },
    },
    config = function(_, opts)
        local neocord = require 'neocord'
        neocord.setup(opts)

        -- VeryLazy runs after the initial UIEnter/BufEnter events. Publish the
        -- already-open buffer now instead of waiting for the next file switch.
        vim.schedule(function() neocord:update() end)
    end,
}
