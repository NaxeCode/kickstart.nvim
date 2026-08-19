---@type overseer.ComponentFileDefinition
return {
    desc = 'Fold routine raylib startup logs while keeping game traces visible',
    editable = false,
    constructor = function()
        local focused = false
        local handled_startup = false
        local showing_initial = false

        return {
            on_reset = function()
                focused = false
                handled_startup = false
                showing_initial = false
            end,
            on_output_lines = function(_, task)
                local bufnr = task:get_bufnr()
                if not bufnr then return end

                local output_wins = vim.fn.win_findbuf(bufnr)
                if not focused and output_wins[1] then
                    vim.api.nvim_set_current_win(output_wins[1])
                    focused = true
                end
                if handled_startup then
                    if showing_initial then
                        local line_count = vim.api.nvim_buf_line_count(bufnr)
                        for _, winid in ipairs(output_wins) do
                            if vim.api.nvim_win_is_valid(winid) then
                                vim.api.nvim_win_call(winid, function()
                                    vim.api.nvim_win_set_cursor(0, { line_count, 0 })
                                    vim.cmd 'normal! zb'
                                end)
                            end
                        end
                        showing_initial = false
                    end
                    return
                end

                local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
                local first
                local last

                for index, line in ipairs(lines) do
                    if not first and line:find('INFO: Initializing raylib', 1, true) == 1 then first = index end
                    if first and line:find('INFO: TIMER: Target time per frame:', 1, true) == 1 then
                        last = index
                        break
                    end
                end

                if not first or not last then return end
                handled_startup = true

                for index = first, last do
                    local line = lines[index]
                    if line:match '^WARNING:' or line:match '^ERROR:' or line:match '^FATAL:' then return end
                end

                for _, winid in ipairs(output_wins) do
                    if vim.api.nvim_win_is_valid(winid) then
                        vim.api.nvim_win_call(winid, function()
                            vim.wo.foldmethod = 'manual'
                            vim.wo.foldenable = true
                            vim.cmd(('%d,%dfold'):format(first, last))
                            vim.api.nvim_win_set_cursor(0, { 1, 0 })
                            vim.cmd 'normal! zt'
                        end)
                    end
                end
                showing_initial = true
            end,
        }
    end,
}
