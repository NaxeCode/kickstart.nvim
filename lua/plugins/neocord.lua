local M = {}

local function start()
    local neocord = require 'neocord'
    neocord.setup {
        logo_tooltip = 'Neovim',
        main_image = 'language',
        show_time = true,
        global_timer = true,
        blacklist = { '.*%.env.*', 'credentials', 'secrets' },
    }
    vim.schedule(function() neocord:update() end)
end

function M.setup()
    if #vim.api.nvim_list_uis() > 0 then
        start()
        return
    end
    vim.api.nvim_create_autocmd('UIEnter', {
        group = vim.api.nvim_create_augroup('naxecode-neocord-start', { clear = true }),
        once = true,
        callback = start,
    })
end

return M
