local M = {}

local namespace = vim.api.nvim_create_namespace 'c_tutor'
local marks = {}
local latest = {}
local sequence = 0
local panel_namespace = vim.api.nvim_create_namespace 'c_tutor_panel'
local panel = {}

local AI_CODE_THEME = {
    CTutorCode = { fg = '#F8F8F2', bg = '#241B2F', ctermfg = 231, ctermbg = 234 },
    CTutorCodeComment = { fg = '#6272A4', bg = '#241B2F', ctermfg = 60, ctermbg = 234, italic = true },
    CTutorCodeFunction = { fg = '#8BE9FD', bg = '#241B2F', ctermfg = 117, ctermbg = 234 },
    CTutorCodeIdentifier = { fg = '#50FA7B', bg = '#241B2F', ctermfg = 84, ctermbg = 234 },
    CTutorCodeKeyword = { fg = '#FF79C6', bg = '#241B2F', ctermfg = 212, ctermbg = 234, bold = true },
    CTutorCodeNumber = { fg = '#FFB86C', bg = '#241B2F', ctermfg = 215, ctermbg = 234 },
    CTutorCodeOperator = { fg = '#FF79C6', bg = '#241B2F', ctermfg = 212, ctermbg = 234 },
    CTutorCodePreProc = { fg = '#FF5555', bg = '#241B2F', ctermfg = 203, ctermbg = 234 },
    CTutorCodePunctuation = { fg = '#B8AEC9', bg = '#241B2F', ctermfg = 146, ctermbg = 234 },
    CTutorCodeString = { fg = '#F1FA8C', bg = '#241B2F', ctermfg = 229, ctermbg = 234 },
    CTutorCodeType = { fg = '#BD93F9', bg = '#241B2F', ctermfg = 141, ctermbg = 234 },
}

local function define_highlights()
    local normal = vim.api.nvim_get_hl(0, { name = 'Normal', link = false })
    local main = {
        fg = normal.fg or 0xF0E4CF,
        ctermfg = normal.ctermfg,
        bold = true,
        italic = false,
    }
    vim.api.nvim_set_hl(0, 'CTutorTitle', vim.deepcopy(main))
    vim.api.nvim_set_hl(0, 'CTutorText', vim.deepcopy(main))
    vim.api.nvim_set_hl(0, 'CTutorQuestion', vim.deepcopy(main))
    vim.api.nvim_set_hl(0, 'CTutorLearner', vim.deepcopy(main))
    for group, highlight in pairs(AI_CODE_THEME) do
        vim.api.nvim_set_hl(0, group, vim.deepcopy(highlight))
    end
    vim.api.nvim_set_hl(0, 'CTutorAccent', { default = true, link = 'DiagnosticWarn' })
    vim.api.nvim_set_hl(0, 'CTutorThinking', { default = true, link = 'DiagnosticWarn' })
    vim.api.nvim_set_hl(0, 'CTutorElapsed', { default = true, link = 'DiagnosticWarn' })
end

local function display_width(text) return vim.fn.strdisplaywidth(text) end

local function wrap(text, width)
    local lines = {}
    for source_line in (text .. '\n'):gmatch '(.-)\n' do
        if source_line == '' then
            lines[#lines + 1] = ''
        else
            local current = ''
            for word in source_line:gmatch '%S+' do
                local candidate = current == '' and word or (current .. ' ' .. word)
                if current ~= '' and display_width(candidate) > width then
                    lines[#lines + 1] = current
                    current = word
                else
                    current = candidate
                end
            end
            lines[#lines + 1] = current
        end
    end
    if lines[#lines] == '' then table.remove(lines) end
    return lines
end

local function available_width(bufnr)
    local width = 88
    for _, window in ipairs(vim.fn.win_findbuf(bufnr)) do
        if vim.api.nvim_win_is_valid(window) then width = math.min(width, math.max(36, vim.api.nvim_win_get_width(window) - 8)) end
    end
    return width
end

local function add_panel_text(target, first_prefix, continuation_prefix, text, highlight, width)
    local prefix_width = math.max(display_width(first_prefix), display_width(continuation_prefix))
    for index, line in ipairs(wrap(text, math.max(20, width - prefix_width))) do
        target[#target + 1] = {
            { index == 1 and first_prefix or continuation_prefix, 'CTutorAccent' },
            { line, highlight },
        }
    end
end

local function split_code_lines(code)
    local lines = {}
    for line in (code .. '\n'):gmatch '(.-)\n' do
        lines[#lines + 1] = line
    end
    if #lines == 0 then lines[1] = '' end
    return lines
end

local function capture_group(capture)
    if capture:match '^comment' then return 'CTutorCodeComment' end
    if capture:match '^string' or capture:match '^character' then return 'CTutorCodeString' end
    if capture:match '^keyword' or capture:match '^label' then return 'CTutorCodeKeyword' end
    if capture:match '^type' or capture:match '^constructor' then return 'CTutorCodeType' end
    if capture:match '^function' or capture:match '^method' then return 'CTutorCodeFunction' end
    if capture:match '^number' or capture:match '^float' or capture:match '^boolean' or capture:match '^constant' then return 'CTutorCodeNumber' end
    if capture:match '^operator' then return 'CTutorCodeOperator' end
    if capture:match '^punctuation' then return 'CTutorCodePunctuation' end
    if capture:match '^preproc' or capture:find('directive', 1, true) then return 'CTutorCodePreProc' end
    if capture:match '^variable' or capture:match '^property' or capture:match '^field' then return 'CTutorCodeIdentifier' end
    return 'CTutorCode'
end

local function plain_code_lines(lines)
    local result = {}
    for index, line in ipairs(lines) do
        result[index] = { { line == '' and ' ' or line, 'CTutorCode' } }
    end
    return result
end

local function ai_code_lines(code, language)
    local lines = split_code_lines(code)
    local styles = {}
    for index = 1, #lines do
        styles[index] = {}
    end
    local parsed = pcall(function()
        local parser = vim.treesitter.get_string_parser(code, language or 'c')
        local trees = parser:parse()
        local tree = trees and trees[1]
        assert(tree, 'missing syntax tree')
        local query = vim.treesitter.query.get(language or 'c', 'highlights')
        assert(query, 'missing highlight query')
        for id, node, metadata in query:iter_captures(tree:root(), code, 0, -1) do
            local capture = query.captures[id]
            if capture then
                local group = capture_group(capture)
                local capture_metadata = type(metadata) == 'table' and metadata[id] or nil
                local configured_priority = type(capture_metadata) == 'table' and capture_metadata.priority or (type(metadata) == 'table' and metadata.priority)
                local priority = type(configured_priority) == 'number' and configured_priority or (100 + #capture)
                local start_row, start_column, end_row, end_column = node:range()
                for row = start_row, end_row do
                    local line_index = row + 1
                    local line = lines[line_index]
                    if line then
                        local first = row == start_row and start_column or 0
                        local last = row == end_row and end_column or #line
                        first = math.max(0, math.min(first, #line))
                        last = math.max(first, math.min(last, #line))
                        for column = first + 1, last do
                            local current = styles[line_index][column]
                            if not current or priority >= current.priority then styles[line_index][column] = { group = group, priority = priority } end
                        end
                    end
                end
            end
        end
    end)
    if not parsed then return plain_code_lines(lines), false end

    local result = {}
    for line_index, line in ipairs(lines) do
        if line == '' then
            result[line_index] = { { ' ', 'CTutorCode' } }
        else
            local chunks = {}
            local start_column = 1
            local group = styles[line_index][1] and styles[line_index][1].group or 'CTutorCode'
            for column = 2, #line + 1 do
                local next_group = column <= #line and styles[line_index][column] and styles[line_index][column].group or 'CTutorCode'
                if column > #line or next_group ~= group then
                    chunks[#chunks + 1] = { line:sub(start_column, column - 1), group }
                    start_column = column
                    group = next_group
                end
            end
            result[line_index] = chunks
        end
    end
    return result, true
end

local function format_elapsed(seconds) return ('%05.2fs'):format(math.min(math.max(seconds, 0), 99.99)) end

local function thinking_lines(seconds)
    return { {
        { '╭─ 󰚩 Tutor · thinking… ', 'CTutorAccent' },
        { format_elapsed(seconds), 'CTutorElapsed' },
    } }
end

local function stop_timer(mark)
    if not mark or not mark.timer then return end
    pcall(function()
        mark.timer:stop()
        if not mark.timer:is_closing() then mark.timer:close() end
    end)
end

local function buffer_marks(bufnr)
    local bucket = marks[bufnr]
    if not bucket then
        bucket = {}
        marks[bufnr] = bucket
    end
    return bucket
end

local function next_order()
    sequence = sequence + 1
    return sequence
end

local function choose_latest(bufnr)
    latest[bufnr] = nil
    local newest = -1
    for id, mark in pairs(marks[bufnr] or {}) do
        if mark.state ~= 'pending' and (mark.order or 0) > newest then
            latest[bufnr] = id
            newest = mark.order or 0
        end
    end
end

function M.clear(bufnr, id)
    if not bufnr then return end
    if panel.source_bufnr == bufnr and (not id or panel.mark_id == id) then M.close_panel() end
    local bucket = marks[bufnr]
    if id then
        local mark = bucket and bucket[id]
        stop_timer(mark)
        if vim.api.nvim_buf_is_valid(bufnr) then pcall(vim.api.nvim_buf_del_extmark, bufnr, namespace, id) end
        if bucket then
            bucket[id] = nil
            if latest[bufnr] == id then choose_latest(bufnr) end
            if next(bucket) == nil then
                marks[bufnr] = nil
                latest[bufnr] = nil
            end
        end
        return
    end

    for _, mark in pairs(bucket or {}) do
        stop_timer(mark)
    end
    if vim.api.nvim_buf_is_valid(bufnr) then pcall(vim.api.nvim_buf_clear_namespace, bufnr, namespace, 0, -1) end
    marks[bufnr] = nil
    latest[bufnr] = nil
end

function M.track(bufnr, anchor_line)
    local row = math.max(anchor_line - 1, 0)
    local id = vim.api.nvim_buf_set_extmark(bufnr, namespace, row, 0, {
        right_gravity = false,
        priority = 110,
    })
    buffer_marks(bufnr)[id] = {
        id = id,
        anchor_line = anchor_line,
        state = 'pending',
        order = 0,
    }
    return id
end

function M.show_thinking(bufnr, anchor_line, started_at, id)
    local bucket = buffer_marks(bufnr)
    local mark = id and bucket[id] or nil
    local row = math.max(anchor_line - 1, 0)
    local column = 0
    if mark then
        stop_timer(mark)
        local position = vim.api.nvim_buf_get_extmark_by_id(bufnr, namespace, id, {})
        if #position > 0 then
            row = position[1]
            column = position[2]
        else
            bucket[id] = nil
            if latest[bufnr] == id then choose_latest(bufnr) end
            id = nil
        end
    end

    started_at = started_at or vim.uv.hrtime()
    local options = {
        virt_lines = thinking_lines(0),
        virt_lines_above = false,
        right_gravity = false,
        hl_mode = 'combine',
        priority = 110,
    }
    if id then options.id = id end
    id = vim.api.nvim_buf_set_extmark(bufnr, namespace, row, column, options)
    local timer = assert(vim.uv.new_timer())
    bucket[id] = {
        id = id,
        anchor_line = row + 1,
        state = 'thinking',
        started_at = started_at,
        timer = timer,
        order = next_order(),
    }
    latest[bufnr] = id
    timer:start(
        100,
        100,
        vim.schedule_wrap(function()
            local current_bucket = marks[bufnr]
            local current = current_bucket and current_bucket[id]
            if not current or current.state ~= 'thinking' then return end
            if not vim.api.nvim_buf_is_valid(bufnr) then
                M.clear(bufnr, id)
                return
            end
            local position = vim.api.nvim_buf_get_extmark_by_id(bufnr, namespace, id, {})
            if #position == 0 then
                M.clear(bufnr, id)
                return
            end
            local elapsed = (vim.uv.hrtime() - started_at) / 1000000000
            pcall(vim.api.nvim_buf_set_extmark, bufnr, namespace, position[1], position[2], {
                id = id,
                virt_lines = thinking_lines(elapsed),
                virt_lines_above = false,
                right_gravity = false,
                hl_mode = 'combine',
                priority = 110,
            })
        end)
    )
    return id
end

local function provenance_label(provenance)
    provenance = provenance or {}
    local model = type(provenance.model) == 'string' and provenance.model ~= '' and provenance.model or 'unknown model'
    local thinking = type(provenance.thinking_level) == 'string' and provenance.thinking_level ~= '' and ('thinking ' .. provenance.thinking_level)
        or 'no thinking'
    local source = provenance.source == 'cache' and 'cache hit' or 'fresh'
    return ('╰─ 󰒓 %s · 󰔟 %s · 󰆓 %s · <leader>mv hide'):format(model, thinking, source)
end
local function append_text(lines, text, prefix)
    prefix = prefix or ''
    for line in (text .. '\n'):gmatch '(.-)\n' do
        lines[#lines + 1] = prefix .. line
    end
end

local function panel_markdown(mark)
    local response = mark.response
    local profile = mark.profile or { id = 'c', display = 'C', parser = 'c' }
    local lines = { '# ' .. response.title, '' }
    local code_rows = {}

    if mark.learner_reply then
        append_text(lines, mark.learner_reply, '> **You:** ')
        lines[#lines + 1] = ''
    end
    lines[#lines + 1] = '**' .. response.explanation .. '**'

    for _, section in ipairs(response.sections or {}) do
        lines[#lines + 1] = ''
        lines[#lines + 1] = '## ' .. section.title
        lines[#lines + 1] = ''
        append_text(lines, section.body)
    end

    if response.neutral_example then
        lines[#lines + 1] = ''
        lines[#lines + 1] = ('## AI %s example'):format(profile.display)
        lines[#lines + 1] = ''
        lines[#lines + 1] = '```' .. (profile.id or profile.parser or '')
        local highlighted = ai_code_lines(response.neutral_example, profile.parser or profile.id)
        for _, chunks in ipairs(highlighted) do
            local code_line = ''
            for _, chunk in ipairs(chunks) do
                code_line = code_line .. chunk[1]
            end
            lines[#lines + 1] = code_line
            code_rows[#code_rows + 1] = { row = #lines - 1, chunks = chunks }
        end
        lines[#lines + 1] = '```'
    end

    if response.question then
        lines[#lines + 1] = ''
        lines[#lines + 1] = '> [!TIP]'
        lines[#lines + 1] = '> **Next:** ' .. response.question
    end

    local provenance = mark.provenance or {}
    local model = type(provenance.model) == 'string' and provenance.model ~= '' and provenance.model or 'unknown model'
    local thinking = type(provenance.thinking_level) == 'string' and provenance.thinking_level ~= '' and ('thinking ' .. provenance.thinking_level)
        or 'no thinking'
    local source = provenance.source == 'cache' and 'cache hit' or 'fresh'
    lines[#lines + 1] = ''
    lines[#lines + 1] = '---'
    lines[#lines + 1] = ''
    lines[#lines + 1] = '`<leader>mq` follow up · `<leader>mm` deeper · `<leader>mu` reroll · `q` close'
    lines[#lines + 1] = ''
    lines[#lines + 1] = ('*%s · %s · %s · %s*'):format(format_elapsed(mark.elapsed_seconds or 0), model, thinking, source)
    return lines, code_rows
end

local function panel_source_window()
    for _, winid in ipairs(vim.fn.win_findbuf(panel.source_bufnr or -1)) do
        if vim.api.nvim_win_is_valid(winid) then return winid end
    end
end

local function focus_panel_source()
    local winid = panel_source_window()
    if not winid then return false end
    vim.api.nvim_set_current_win(winid)
    return true
end

local function set_panel_keymaps(bufnr)
    local options = { buffer = bufnr, silent = true }
    vim.keymap.set('n', 'q', function() M.close_panel() end, vim.tbl_extend('force', options, { desc = 'Close tutor detail' }))
    for keys, action in pairs {
        ['<leader>mq'] = 'reply',
        ['<leader>mm'] = 'more',
        ['<leader>mu'] = 'reroll',
        ['<leader>mv'] = 'toggle_message',
    } do
        vim.keymap.set('n', keys, function()
            if focus_panel_source() then require('custom.c_tutor')[action]() end
        end, options)
    end
end

local function create_panel_buffer()
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(bufnr, 'Tutor://response')
    vim.bo[bufnr].buftype = 'nofile'
    vim.bo[bufnr].bufhidden = 'wipe'
    vim.bo[bufnr].swapfile = false
    vim.bo[bufnr].undolevels = -1
    set_panel_keymaps(bufnr)
    vim.api.nvim_create_autocmd('BufWipeout', {
        buffer = bufnr,
        once = true,
        callback = function()
            if panel.bufnr == bufnr then panel = {} end
        end,
    })
    return bufnr
end

local function decorate_panel_code(bufnr, code_rows)
    vim.api.nvim_buf_clear_namespace(bufnr, panel_namespace, 0, -1)
    for _, code_row in ipairs(code_rows) do
        local column = 0
        for _, chunk in ipairs(code_row.chunks) do
            local length = #chunk[1]
            if length > 0 then
                vim.api.nvim_buf_set_extmark(bufnr, panel_namespace, code_row.row, column, {
                    end_row = code_row.row,
                    end_col = column + length,
                    hl_group = chunk[2],
                    hl_mode = 'replace',
                    priority = 200,
                })
            end
            column = column + length
        end
    end
end

local function update_panel_buffer(mark)
    local lines, code_rows = panel_markdown(mark)
    vim.bo[panel.bufnr].modifiable = true
    vim.api.nvim_buf_set_lines(panel.bufnr, 0, -1, false, lines)
    vim.bo[panel.bufnr].modifiable = false
    vim.bo[panel.bufnr].filetype = 'markdown'
    decorate_panel_code(panel.bufnr, code_rows)
end

function M.close_panel()
    local winid = panel.winid
    local bufnr = panel.bufnr
    panel = {}
    if winid and vim.api.nvim_win_is_valid(winid) then pcall(vim.api.nvim_win_close, winid, true) end
    if bufnr and vim.api.nvim_buf_is_valid(bufnr) then pcall(vim.api.nvim_buf_delete, bufnr, { force = true }) end
    return winid ~= nil or bufnr ~= nil
end

function M.open_panel(bufnr, id, focus)
    local mark = M.get(bufnr, id)
    if not mark or mark.state ~= 'response' or not mark.response.sections then return false end
    local source_win = nil
    for _, winid in ipairs(vim.fn.win_findbuf(bufnr)) do
        if vim.api.nvim_win_is_valid(winid) then
            source_win = winid
            break
        end
    end
    if not source_win then return false end

    local source_tab = vim.api.nvim_win_get_tabpage(source_win)
    if panel.winid and vim.api.nvim_win_is_valid(panel.winid) and vim.api.nvim_win_get_tabpage(panel.winid) ~= source_tab then M.close_panel() end
    if not panel.bufnr or not vim.api.nvim_buf_is_valid(panel.bufnr) then panel.bufnr = create_panel_buffer() end
    if not panel.winid or not vim.api.nvim_win_is_valid(panel.winid) then
        local source_width = vim.api.nvim_win_get_width(source_win)
        panel.winid = vim.api.nvim_open_win(panel.bufnr, false, { split = 'right', win = source_win })
        vim.api.nvim_win_set_width(panel.winid, math.max(42, math.min(80, math.floor(source_width * 0.48))))
        vim.wo[panel.winid].wrap = true
        vim.wo[panel.winid].linebreak = true
        vim.wo[panel.winid].breakindent = true
        vim.wo[panel.winid].number = false
        vim.wo[panel.winid].relativenumber = false
        vim.wo[panel.winid].signcolumn = 'no'
        vim.wo[panel.winid].foldcolumn = '0'
        vim.wo[panel.winid].winfixwidth = true
        vim.wo[panel.winid].winbar = ' 󰚩 Tutor '
    end

    panel.source_bufnr = bufnr
    panel.mark_id = mark.id
    update_panel_buffer(mark)
    vim.api.nvim_win_set_cursor(panel.winid, { 1, 0 })
    if focus then vim.api.nvim_set_current_win(panel.winid) end
    return true
end

function M.get_panel() return panel end

function M.show(bufnr, anchor_line, response, elapsed_seconds, provenance, id, profile, learner_reply, open_detail)
    local width = available_width(bufnr)
    local lines = {
        {
            { '╭─ 󰚩 Tutor · ', 'CTutorAccent' },
            { response.title, 'CTutorTitle' },
        },
    }
    if elapsed_seconds then lines[1][#lines[1] + 1] = { (' · %s'):format(format_elapsed(elapsed_seconds)), 'CTutorAccent' } end
    if learner_reply then add_panel_text(lines, '│  You · ', '│    ', learner_reply, 'CTutorLearner', width) end
    add_panel_text(lines, '│  ', '│  ', response.explanation, 'CTutorText', width)
    if response.sections then
        lines[#lines + 1] = {
            { '│  󰈙 Detail · ', 'CTutorAccent' },
            { '<leader>mo', 'CTutorQuestion' },
            { (' · %d sections'):format(#response.sections), 'CTutorAccent' },
        }
    end
    if response.question then add_panel_text(lines, '│  󰋗 Next · ', '│    ', response.question, 'CTutorQuestion', width) end
    lines[#lines + 1] = {
        { '│  Follow up · ', 'CTutorAccent' },
        { '<leader>mq', 'CTutorQuestion' },
        { ' (optional)', 'CTutorAccent' },
    }
    if response.neutral_example and not response.sections then
        profile = profile or { id = 'c', display = 'C', parser = 'c' }
        local highlighted_lines = ai_code_lines(response.neutral_example, profile.parser or profile.id)
        local first_prefix = ('│  󰌌 AI %s · '):format(profile.display)
        local continuation_prefix = '│' .. string.rep(' ', math.max(display_width(first_prefix) - 1, 1))
        for index, chunks in ipairs(highlighted_lines) do
            local code_line = {
                { index == 1 and first_prefix or continuation_prefix, 'CTutorAccent' },
            }
            vim.list_extend(code_line, chunks)
            lines[#lines + 1] = code_line
        end
    end
    lines[#lines + 1] = { { provenance_label(provenance), 'CTutorAccent' } }

    local bucket = buffer_marks(bufnr)
    local mark = id and bucket[id] or nil
    local row = math.max(anchor_line - 1, 0)
    local column = 0
    if mark then
        stop_timer(mark)
        local position = vim.api.nvim_buf_get_extmark_by_id(bufnr, namespace, id, {})
        if #position > 0 then
            row = position[1]
            column = position[2]
        else
            bucket[id] = nil
            if latest[bufnr] == id then choose_latest(bufnr) end
            id = nil
        end
    end
    local options = {
        virt_lines = lines,
        virt_lines_above = false,
        right_gravity = false,
        hl_mode = 'combine',
        priority = 110,
    }
    if id then options.id = id end
    id = vim.api.nvim_buf_set_extmark(bufnr, namespace, row, column, options)
    bucket[id] = {
        id = id,
        anchor_line = row + 1,
        state = 'response',
        response = response,
        elapsed_seconds = elapsed_seconds,
        provenance = provenance,
        learner_reply = learner_reply,
        profile = profile,
        order = next_order(),
    }
    latest[bufnr] = id
    if open_detail and response.sections then M.open_panel(bufnr, id, false) end
    return id
end
function M.toggle_visibility(bufnr, id)
    local mark = M.get(bufnr, id)
    if not mark or mark.state ~= 'response' then return false end

    if mark.hidden then
        M.show(bufnr, mark.anchor_line, mark.response, mark.elapsed_seconds, mark.provenance, mark.id, mark.profile, mark.learner_reply)
        return true, true
    end

    if not vim.api.nvim_buf_is_valid(bufnr) then return false end
    local position = vim.api.nvim_buf_get_extmark_by_id(bufnr, namespace, mark.id, {})
    if #position == 0 then return false end
    local ok = pcall(vim.api.nvim_buf_set_extmark, bufnr, namespace, position[1], position[2], {
        id = mark.id,
        right_gravity = false,
        priority = 110,
    })
    if not ok then return false end
    mark.anchor_line = position[1] + 1
    if panel.source_bufnr == bufnr and panel.mark_id == mark.id then M.close_panel() end
    mark.hidden = true
    return true, false
end

function M.exists(bufnr, id)
    if not id or not vim.api.nvim_buf_is_valid(bufnr) then return false end
    return #vim.api.nvim_buf_get_extmark_by_id(bufnr, namespace, id, {}) > 0
end

function M.position(bufnr, id)
    if not id or not vim.api.nvim_buf_is_valid(bufnr) then return nil end
    local position = vim.api.nvim_buf_get_extmark_by_id(bufnr, namespace, id, {})
    return #position > 0 and position[1] + 1 or nil
end

function M.get(bufnr, id)
    local bucket = marks[bufnr]
    return bucket and bucket[id or latest[bufnr]] or nil
end

function M.all(bufnr) return marks[bufnr] or {} end

function M.setup()
    define_highlights()
    vim.api.nvim_create_autocmd('ColorScheme', {
        group = vim.api.nvim_create_augroup('CTutorHighlights', { clear = true }),
        callback = define_highlights,
    })
end

M.namespace = namespace
M.wrap = wrap
M._test = {
    ai_code_lines = ai_code_lines,
    capture_group = capture_group,
    panel_namespace = panel_namespace,
}

return M
