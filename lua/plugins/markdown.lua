local M = {}

function M.setup()
    require('render-markdown').setup {
        heading = { sign = false, icons = { '󰲡 ', '󰲣 ', '󰲥 ', '󰲧 ', '󰲩 ', '󰲫 ' } },
        bullet = { icons = { '●', '○', '◆', '◇' } },
        checkbox = {
            unchecked = { icon = '󰄱 ' },
            checked = { icon = '󰱒 ' },
        },
        code = { sign = false, width = 'block', right_pad = 1 },
        dash = { width = 60 },
        latex = { enabled = false },
    }
end

return M
