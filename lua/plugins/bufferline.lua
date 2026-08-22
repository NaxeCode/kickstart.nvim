local M = {}

local function close_buffer(bufnr)
    if not vim.api.nvim_buf_is_valid(bufnr) then return end
    if vim.bo[bufnr].modified then
        vim.notify('Save changes before closing this file tab', vim.log.levels.WARN)
        return
    end
    vim.api.nvim_buf_delete(bufnr, {})
end

function M.setup()
    require('bufferline').setup {
        options = {
            mode = 'buffers',
            numbers = 'ordinal',
            diagnostics = 'nvim_lsp',
            close_command = close_buffer,
            right_mouse_command = close_buffer,
            middle_mouse_command = close_buffer,
            indicator = { style = 'underline' },
            separator_style = 'thin',
            always_show_bufferline = true,
            persist_buffer_sort = true,
            sort_by = 'insert_after_current',
            show_buffer_close_icons = true,
            show_close_icon = false,
        },
    }

    local keys = {
        { '<F13>', '<Cmd>BufferLineCyclePrev<CR>', 'Corne: previous file tab' },
        { '<F14>', '<Cmd>BufferLineCycleNext<CR>', 'Corne: next file tab' },
        { '<F15>', '<Cmd>BufferLineMovePrev<CR>', 'Corne: move file tab left' },
        { '<F16>', '<Cmd>BufferLineMoveNext<CR>', 'Corne: move file tab right' },
        { '<F17>', function() vim.cmd.enew() end, 'Corne: new file tab' },
        { '<F18>', function() close_buffer(vim.api.nvim_get_current_buf()) end, 'Corne: close file tab' },
        { '<M-n>', function() vim.cmd.enew() end, 'New file tab' },
        { '<M-,>', '<Cmd>BufferLineCyclePrev<CR>', 'Previous file tab' },
        { '<M-.>', '<Cmd>BufferLineCycleNext<CR>', 'Next file tab' },
        { '<M-<>', '<Cmd>BufferLineMovePrev<CR>', 'Move file tab left' },
        { '<M->>', '<Cmd>BufferLineMoveNext<CR>', 'Move file tab right' },
        { '<M-w>', function() close_buffer(vim.api.nvim_get_current_buf()) end, 'Close file tab' },
    }
    for _, key in ipairs(keys) do
        vim.keymap.set('n', key[1], key[2], { desc = key[3] })
    end
    for index = 1, 9 do
        vim.keymap.set('n', '<M-' .. index .. '>', function() require('bufferline').go_to(index) end, { desc = 'Go to file tab ' .. index })
    end
end

return M
