local M = {}

local entries_path = vim.fn.stdpath 'config' .. '/lua/custom/key_bank_entries.lua'

local function load_bank()
    local chunk, load_error = loadfile(entries_path)
    if not chunk then error(('Could not load active key bank:\n%s'):format(load_error)) end

    local ok, bank = pcall(chunk)
    if not ok then error(('Could not read active key bank:\n%s'):format(bank)) end
    return bank
end

local function render()
    local bank = load_bank()
    local action_width = 0
    local count = 0

    for _, section in ipairs(bank) do
        for _, item in ipairs(section.items) do
            action_width = math.max(action_width, #item.action)
            count = count + 1
        end
    end

    local lines = { ('  CURRENT · %d BINDINGS'):format(count) }
    local marks = {
        meta = { 1 },
        sections = {},
        dividers = {},
        keys = {},
    }

    for _, section in ipairs(bank) do
        lines[#lines + 1] = ''
        lines[#lines + 1] = '  ' .. section.title
        marks.sections[#marks.sections + 1] = #lines

        lines[#lines + 1] = '  ' .. string.rep('─', vim.fn.strdisplaywidth(section.title))
        marks.dividers[#marks.dividers + 1] = #lines

        for _, item in ipairs(section.items) do
            local hint = item.sends and ('[%s  →  %s]'):format(item.chord, item.sends) or ('[%s]'):format(item.chord)
            local line = ('  %-' .. action_width .. 's    %s'):format(item.action, hint)
            lines[#lines + 1] = line
            marks.keys[#marks.keys + 1] = { line = #lines, start_col = #line - #hint }
        end
    end

    lines[#lines + 1] = ''
    lines[#lines + 1] = '  q / Esc close    r refresh    Space k toggle'
    marks.footer = #lines
    return lines, marks
end

function M.close()
    if M.win and vim.api.nvim_win_is_valid(M.win) then vim.api.nvim_win_close(M.win, true) end
    M.win = nil
end

function M.toggle()
    if M.win and vim.api.nvim_win_is_valid(M.win) then
        M.close()
        return
    end

    local lines, marks = render()
    local max_width = 0
    for _, line in ipairs(lines) do
        max_width = math.max(max_width, vim.fn.strdisplaywidth(line))
    end

    local width = math.min(max_width + 2, math.max(20, vim.o.columns - 6))
    local height = math.min(#lines, math.max(4, vim.o.lines - 6))
    local row = math.max(0, math.floor((vim.o.lines - height) / 2) - 1)
    local col = math.max(0, math.floor((vim.o.columns - width) / 2))

    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
    vim.bo[bufnr].bufhidden = 'wipe'
    vim.bo[bufnr].filetype = 'keybank'
    vim.bo[bufnr].modifiable = false

    M.win = vim.api.nvim_open_win(bufnr, true, {
        relative = 'editor',
        row = row,
        col = col,
        width = width,
        height = height,
        style = 'minimal',
        border = 'rounded',
        title = ' Key Bank · Active ',
        title_pos = 'center',
    })

    vim.wo[M.win].cursorline = false
    vim.wo[M.win].wrap = false
    vim.wo[M.win].winhighlight = 'Normal:NormalFloat,FloatBorder:FloatBorder'

    vim.api.nvim_set_hl(0, 'KeyBankSection', { default = true, link = 'Title' })
    vim.api.nvim_set_hl(0, 'KeyBankDivider', { default = true, link = 'NonText' })
    vim.api.nvim_set_hl(0, 'KeyBankKey', { default = true, link = 'Function' })
    vim.api.nvim_set_hl(0, 'KeyBankMeta', { default = true, link = 'Comment' })
    vim.api.nvim_set_hl(0, 'KeyBankFooter', { default = true, link = 'Comment' })
    for _, line in ipairs(marks.sections) do
        vim.api.nvim_buf_add_highlight(bufnr, -1, 'KeyBankSection', line - 1, 0, -1)
    end
    for _, line in ipairs(marks.dividers) do
        vim.api.nvim_buf_add_highlight(bufnr, -1, 'KeyBankDivider', line - 1, 0, -1)
    end
    for _, mark in ipairs(marks.keys) do
        vim.api.nvim_buf_add_highlight(bufnr, -1, 'KeyBankKey', mark.line - 1, mark.start_col, -1)
    end
    vim.api.nvim_buf_add_highlight(bufnr, -1, 'KeyBankMeta', marks.meta[1] - 1, 0, -1)
    vim.api.nvim_buf_add_highlight(bufnr, -1, 'KeyBankFooter', marks.footer - 1, 0, -1)

    local close_opts = { buffer = bufnr, silent = true, nowait = true }
    vim.keymap.set('n', 'q', M.close, close_opts)
    vim.keymap.set('n', '<Esc>', M.close, close_opts)
    vim.keymap.set('n', '<leader>k', M.close, close_opts)
    vim.keymap.set('n', 'r', function()
        M.close()
        package.loaded['custom.key_bank'] = nil
        vim.schedule(function() require('custom.key_bank').toggle() end)
    end, close_opts)
end

return M
