local M = {
    query = '',
    practice_only = false,
    show_details = true,
}

local entries_path = vim.fn.stdpath 'config' .. '/lua/custom/key_bank_entries.lua'
local progress_path = vim.fn.stdpath 'state' .. '/shortcut-atlas.json'
local namespace = vim.api.nvim_create_namespace 'shortcut_atlas'
local tracker_namespace = vim.api.nvim_create_namespace 'shortcut_atlas_usage'
local tracking_overrides = {
    ['split-focus'] = { '<C-h>', '<C-j>', '<C-k>', '<C-l>' },
    ['divider-horizontal'] = { '<M-h>', '<M-l>' },
    ['divider-vertical'] = { '<M-j>', '<M-k>' },
    ['buffer-prev-next'] = { '<M-,>', '<M-.>' },
    ['buffer-move'] = { '<M-<>', '<M->>' },
    ['buffer-number'] = { '<M-1>', '<M-2>', '<M-3>', '<M-4>', '<M-5>', '<M-6>', '<M-7>', '<M-8>', '<M-9>' },
    ['buffer-new-close'] = { '<M-n>', '<M-w>' },
    ['git-next'] = { ']c', '[c' },
    ['quickfix-next'] = { '<leader>qn', '<leader>qp' },
}

local function load_bank()
    local chunk, load_error = loadfile(entries_path)
    if not chunk then error(('Could not load Shortcut Atlas:\n%s'):format(load_error)) end

    local ok, bank = pcall(chunk)
    if not ok then error(('Could not read Shortcut Atlas:\n%s'):format(bank)) end
    return bank
end

local function load_state()
    local ok, lines = pcall(vim.fn.readfile, progress_path)
    if not ok or #lines == 0 then return {}, {} end

    local decoded_ok, decoded = pcall(vim.json.decode, table.concat(lines, '\n'))
    if not decoded_ok or type(decoded) ~= 'table' then return {}, {} end
    local statuses = type(decoded.statuses) == 'table' and decoded.statuses or {}
    local usage = type(decoded.usage) == 'table' and decoded.usage or {}
    return statuses, usage
end

local function ensure_state()
    if M.progress and M.usage then return end
    M.progress, M.usage = load_state()
end

local function save_state()
    ensure_state()
    vim.fn.mkdir(vim.fs.dirname(progress_path), 'p')
    local encoded = vim.json.encode { version = 2, statuses = M.progress, usage = M.usage }
    local ok, error_message = pcall(vim.fn.writefile, { encoded }, progress_path)
    if not ok then vim.notify(('Could not save shortcut data:\n%s'):format(error_message), vim.log.levels.ERROR) end
end

local function active_set(bank)
    local result = {}
    for _, id in ipairs(bank.active or {}) do
        result[id] = true
    end
    return result
end

local function item_status(item, defaults) return M.progress[item.id] or (defaults[item.id] and 'practice' or 'reference') end

local function searchable_text(section, item)
    return table.concat({ section.title or '', section.description or '', item.action or '', item.keys or '', item.vim or '', item.detail or '' }, ' '):lower()
end

local function matches_filter(section, item, status)
    if M.practice_only and status ~= 'practice' then return false end
    local query = vim.trim(M.query):lower()
    return query == '' or searchable_text(section, item):find(query, 1, true) ~= nil
end

local function collect_stats(bank, defaults)
    local stats = { practice = 0, mastered = 0, reference = 0, total = 0, uses = 0 }
    for _, section in ipairs(bank.sections) do
        for _, item in ipairs(section.items) do
            local status = item_status(item, defaults)
            stats[status] = stats[status] + 1
            stats.total = stats.total + 1
            stats.uses = stats.uses + (M.usage[item.id] or 0)
        end
    end
    return stats
end

local function render()
    local bank = load_bank()
    local defaults = active_set(bank)
    local stats = collect_stats(bank, defaults)
    local lines = {
        '  BUILD FLUENCY, ONE SHORTCUT AT A TIME',
        '  Practice what matters now. Search the full reference when the work changes.',
        '',
        ('  ● %d PRACTICING    ✓ %d MASTERED    · %d REFERENCE    × %d USES    %d TOTAL'):format(
            stats.practice,
            stats.mastered,
            stats.reference,
            stats.uses,
            stats.total
        ),
        '',
        ('  VIEW  %s    DETAILS  %s    SEARCH  %s'):format(
            M.practice_only and 'PRACTICE ONLY' or 'ALL SHORTCUTS',
            M.show_details and 'ON' or 'OFF',
            M.query == '' and '—' or ('“' .. M.query .. '”')
        ),
        '',
        '  STATUS  ● practice    ✓ mastered    · reference    × usage count',
    }
    local marks = {
        hero = { 1 },
        meta = { 2, 4, 6, 8 },
        sections = {},
        section_descriptions = {},
        dividers = {},
        keys = {},
        usage = {},
        details = {},
        practice = {},
        mastered = {},
        reference = {},
    }
    local line_to_item = {}
    local item_to_line = {}
    local section_lines = {}
    local visible_count = 0
    local action_width = 0

    for _, section in ipairs(bank.sections) do
        for _, item in ipairs(section.items) do
            action_width = math.max(action_width, vim.fn.strdisplaywidth(item.action))
        end
    end
    action_width = math.min(action_width, 38)

    for section_index, section in ipairs(bank.sections) do
        local visible_items = {}
        for _, item in ipairs(section.items) do
            local status = item_status(item, defaults)
            if matches_filter(section, item, status) then visible_items[#visible_items + 1] = { item = item, status = status } end
        end

        if #visible_items > 0 then
            lines[#lines + 1] = ''
            lines[#lines + 1] = ('  %02d  %s  ·  %d'):format(section_index, section.title, #visible_items)
            marks.sections[#marks.sections + 1] = #lines
            section_lines[#section_lines + 1] = #lines

            lines[#lines + 1] = '      ' .. section.description
            marks.section_descriptions[#marks.section_descriptions + 1] = #lines
            lines[#lines + 1] = '  ' .. string.rep('─', math.min(104, vim.fn.strdisplaywidth(section.title) + 28))
            marks.dividers[#marks.dividers + 1] = #lines

            for _, visible in ipairs(visible_items) do
                local item = visible.item
                local status = visible.status
                local marker = status == 'practice' and '●' or status == 'mastered' and '✓' or '·'
                local hint = '[' .. item.keys .. ']'
                local usage = ('× %d'):format(M.usage[item.id] or 0)
                local line = ('  %s  %-' .. action_width .. 's  %-30s  %s'):format(marker, item.action, hint, usage)
                lines[#lines + 1] = line
                visible_count = visible_count + 1
                line_to_item[#lines] = item
                item_to_line[item.id] = #lines

                local marker_mark = { line = #lines, start_col = 2, end_col = 2 + #marker }
                marks[status][#marks[status] + 1] = marker_mark
                marks.usage[#marks.usage + 1] = { line = #lines, start_col = #line - #usage }
                local hint_start = #line - #usage - 2 - 30
                marks.keys[#marks.keys + 1] = { line = #lines, start_col = hint_start, end_col = hint_start + #hint }

                if M.show_details and (item.detail or item.vim) then
                    local pieces = {}
                    if item.detail then pieces[#pieces + 1] = item.detail end
                    if item.vim then pieces[#pieces + 1] = 'Neovim ' .. item.vim end
                    lines[#lines + 1] = '        ' .. table.concat(pieces, '    ·    ')
                    marks.details[#marks.details + 1] = #lines
                    line_to_item[#lines] = item
                    lines[#lines + 1] = ''
                end
            end
        end
    end

    if visible_count == 0 then
        lines[#lines + 1] = ''
        lines[#lines + 1] = '  No shortcuts match this view. Press c to clear filters.'
        marks.meta[#marks.meta + 1] = #lines
    end

    return lines,
        marks,
        {
            line_to_item = line_to_item,
            item_to_line = item_to_line,
            section_lines = section_lines,
            visible_count = visible_count,
        }
end

local function define_highlights()
    vim.api.nvim_set_hl(0, 'ShortcutAtlasHero', { fg = '#f66e0d', bold = true })
    vim.api.nvim_set_hl(0, 'ShortcutAtlasSection', { fg = '#e8a04b', bold = true })
    vim.api.nvim_set_hl(0, 'ShortcutAtlasDivider', { fg = '#6f6579' })
    vim.api.nvim_set_hl(0, 'ShortcutAtlasKey', { fg = '#bfa0dd', bold = true })
    vim.api.nvim_set_hl(0, 'ShortcutAtlasMeta', { fg = '#a79db0' })
    vim.api.nvim_set_hl(0, 'ShortcutAtlasDetail', { fg = '#a79db0' })
    vim.api.nvim_set_hl(0, 'ShortcutAtlasUsage', { fg = '#83b0ad', bold = true })
    vim.api.nvim_set_hl(0, 'ShortcutAtlasPractice', { fg = '#f66e0d', bold = true })
    vim.api.nvim_set_hl(0, 'ShortcutAtlasMastered', { fg = '#9aa87c', bold = true })
    vim.api.nvim_set_hl(0, 'ShortcutAtlasReference', { fg = '#6f6579' })
end

local function add_line_highlight(bufnr, group, line) vim.api.nvim_buf_add_highlight(bufnr, namespace, group, line - 1, 0, -1) end

local function apply_highlights(bufnr, marks)
    vim.api.nvim_buf_clear_namespace(bufnr, namespace, 0, -1)
    define_highlights()

    for _, line in ipairs(marks.hero) do
        add_line_highlight(bufnr, 'ShortcutAtlasHero', line)
    end
    for _, line in ipairs(marks.meta) do
        add_line_highlight(bufnr, 'ShortcutAtlasMeta', line)
    end
    for _, line in ipairs(marks.sections) do
        add_line_highlight(bufnr, 'ShortcutAtlasSection', line)
    end
    for _, line in ipairs(marks.section_descriptions) do
        add_line_highlight(bufnr, 'ShortcutAtlasMeta', line)
    end
    for _, line in ipairs(marks.dividers) do
        add_line_highlight(bufnr, 'ShortcutAtlasDivider', line)
    end
    for _, line in ipairs(marks.details) do
        add_line_highlight(bufnr, 'ShortcutAtlasDetail', line)
    end
    for _, mark in ipairs(marks.keys) do
        vim.api.nvim_buf_add_highlight(bufnr, namespace, 'ShortcutAtlasKey', mark.line - 1, mark.start_col, mark.end_col)
    end
    for _, mark in ipairs(marks.usage) do
        vim.api.nvim_buf_add_highlight(bufnr, namespace, 'ShortcutAtlasUsage', mark.line - 1, mark.start_col, -1)
    end
    for status, group in pairs {
        practice = 'ShortcutAtlasPractice',
        mastered = 'ShortcutAtlasMastered',
        reference = 'ShortcutAtlasReference',
    } do
        for _, mark in ipairs(marks[status]) do
            vim.api.nvim_buf_add_highlight(bufnr, namespace, group, mark.line - 1, mark.start_col, mark.end_col)
        end
    end
end

local function window_dimensions(line_count)
    local available_width = math.max(20, vim.o.columns - 4)
    local desired_width = math.max(68, math.floor(vim.o.columns * 0.92))
    local width = math.min(138, desired_width, available_width)
    local available_height = math.max(4, vim.o.lines - 3)
    local desired_height = math.max(14, math.floor((vim.o.lines - 1) * 0.92))
    local height = math.min(line_count, desired_height, available_height)
    return width, height
end

local function tracking_notations(item)
    if tracking_overrides[item.id] then return tracking_overrides[item.id] end
    if not item.vim or item.vim == '' then return {} end
    return vim.split(item.vim, ' / ', { plain = true, trimempty = true })
end

local function compile_tracking_sequences()
    local sequences = {}
    local bank = load_bank()
    for _, section in ipairs(bank.sections) do
        for _, item in ipairs(section.items) do
            for _, notation in ipairs(tracking_notations(item)) do
                notation = notation:gsub('<leader>', vim.g.mapleader or ' ')
                local ok, sequence = pcall(vim.keycode, notation)
                if ok and sequence ~= '' then sequences[#sequences + 1] = { id = item.id, sequence = sequence } end
            end
        end
    end
    table.sort(sequences, function(a, b) return #a.sequence > #b.sequence end)
    return sequences
end

function M.setup_tracking()
    if M.tracking_started then return end
    M.tracking_started = true
    ensure_state()
    local sequences = compile_tracking_sequences()
    local typed_buffer = ''
    local last_recorded_id = nil
    local last_recorded_at = 0

    vim.on_key(function(_, typed)
        if typed == '' then return end
        typed_buffer = (typed_buffer .. typed):sub(-128)
        for _, tracked in ipairs(sequences) do
            if typed_buffer:sub(-#tracked.sequence) == tracked.sequence then
                local now = vim.uv.hrtime() / 1000000
                local duplicate_event = tracked.id == last_recorded_id and now - last_recorded_at < 100
                typed_buffer = ''
                if duplicate_event then return end

                last_recorded_id = tracked.id
                last_recorded_at = now
                M.usage[tracked.id] = (tonumber(M.usage[tracked.id]) or 0) + 1
                save_state()
                if M.win and vim.api.nvim_win_is_valid(M.win) then vim.schedule(function() M.refresh(tracked.id) end) end
                return
            end
        end
    end, tracker_namespace)
end

local function current_item_id()
    if not M.win or not vim.api.nvim_win_is_valid(M.win) then return nil end
    local line = vim.api.nvim_win_get_cursor(M.win)[1]
    local item = M.line_to_item and M.line_to_item[line]
    return item and item.id or nil
end

function M.refresh(preferred_item_id)
    if not M.win or not vim.api.nvim_win_is_valid(M.win) then return end
    local bufnr = M.buf
    preferred_item_id = preferred_item_id or current_item_id()
    local lines, marks, metadata = render()
    M.line_to_item = metadata.line_to_item
    M.item_to_line = metadata.item_to_line
    M.section_lines = metadata.section_lines

    vim.bo[bufnr].modifiable = true
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
    vim.bo[bufnr].modifiable = false
    apply_highlights(bufnr, marks)

    local width, height = window_dimensions(#lines)
    local row = math.max(0, math.floor((vim.o.lines - height) / 2) - 1)
    local col = math.max(0, math.floor((vim.o.columns - width) / 2))
    vim.api.nvim_win_set_config(M.win, {
        relative = 'editor',
        row = row,
        col = col,
        width = width,
        height = height,
    })

    local target_line = preferred_item_id and M.item_to_line[preferred_item_id]
    if not target_line then
        for line in pairs(M.line_to_item) do
            if not target_line or line < target_line then target_line = line end
        end
    end
    if target_line then vim.api.nvim_win_set_cursor(M.win, { target_line, 0 }) end
end

function M.close()
    if M.win and vim.api.nvim_win_is_valid(M.win) then vim.api.nvim_win_close(M.win, true) end
    M.win = nil
    M.buf = nil
end

local function cycle_status()
    local line = vim.api.nvim_win_get_cursor(M.win)[1]
    local item = M.line_to_item[line]
    if not item then
        vim.notify('Move the cursor onto a shortcut first.', vim.log.levels.INFO)
        return
    end

    local bank = load_bank()
    local status = item_status(item, active_set(bank))
    local next_status = status == 'reference' and 'practice' or status == 'practice' and 'mastered' or 'reference'
    M.progress[item.id] = next_status
    save_state()
    M.refresh(item.id)
    vim.notify(('%s → %s'):format(item.action, next_status), vim.log.levels.INFO)
end

local function search()
    vim.ui.input({ prompt = 'Shortcut search: ', default = M.query }, function(value)
        if value == nil then return end
        M.query = vim.trim(value)
        M.refresh()
    end)
end

local function jump_section(direction)
    if #M.section_lines == 0 then return end
    local current = vim.api.nvim_win_get_cursor(M.win)[1]
    if direction > 0 then
        for _, line in ipairs(M.section_lines) do
            if line > current then
                vim.api.nvim_win_set_cursor(M.win, { line, 0 })
                return
            end
        end
        vim.api.nvim_win_set_cursor(M.win, { M.section_lines[1], 0 })
    else
        for index = #M.section_lines, 1, -1 do
            if M.section_lines[index] < current then
                vim.api.nvim_win_set_cursor(M.win, { M.section_lines[index], 0 })
                return
            end
        end
        vim.api.nvim_win_set_cursor(M.win, { M.section_lines[#M.section_lines], 0 })
    end
end

local function setup_keymaps(bufnr)
    local opts = { buffer = bufnr, silent = true, nowait = true }
    vim.keymap.set('n', 'q', M.close, opts)
    vim.keymap.set('n', '<Esc>', M.close, opts)
    vim.keymap.set('n', '<leader>k', M.close, opts)
    vim.keymap.set('n', '/', search, opts)
    vim.keymap.set('n', 'c', function()
        M.query = ''
        M.practice_only = false
        M.refresh()
    end, opts)
    vim.keymap.set('n', 'a', function()
        M.practice_only = not M.practice_only
        M.refresh()
    end, opts)
    vim.keymap.set('n', 'd', function()
        M.show_details = not M.show_details
        M.refresh()
    end, opts)
    vim.keymap.set('n', 'm', cycle_status, opts)
    vim.keymap.set('n', '<Tab>', function() jump_section(1) end, opts)
    vim.keymap.set('n', '<S-Tab>', function() jump_section(-1) end, opts)
    vim.keymap.set('n', 'r', function()
        M.progress, M.usage = load_state()
        M.refresh()
    end, opts)
end

function M.toggle()
    if M.win and vim.api.nvim_win_is_valid(M.win) then
        M.close()
        return
    end

    M.progress, M.usage = load_state()
    M.buf = vim.api.nvim_create_buf(false, true)
    vim.bo[M.buf].bufhidden = 'wipe'
    vim.bo[M.buf].filetype = 'shortcutatlas'
    vim.bo[M.buf].modifiable = false

    local width, height = window_dimensions(24)
    local row = math.max(0, math.floor((vim.o.lines - height) / 2) - 1)
    local col = math.max(0, math.floor((vim.o.columns - width) / 2))
    M.win = vim.api.nvim_open_win(M.buf, true, {
        relative = 'editor',
        row = row,
        col = col,
        width = width,
        height = height,
        style = 'minimal',
        border = 'rounded',
        title = ' Shortcut Atlas · Space k ',
        title_pos = 'center',
        footer = ' / search · a practice · m status · d details · Tab section · c clear · q close ',
        footer_pos = 'center',
    })

    vim.wo[M.win].cursorline = true
    vim.wo[M.win].wrap = false
    vim.wo[M.win].winhighlight = 'Normal:NormalFloat,FloatBorder:FloatBorder,CursorLine:Visual'
    setup_keymaps(M.buf)
    M.refresh()
end

return M
