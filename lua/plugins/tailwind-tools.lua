local M = {}

function M.setup()
    require('tailwind-tools').setup {
        document_color = { enabled = true },
        server = { override = false },
    }
end

return M
