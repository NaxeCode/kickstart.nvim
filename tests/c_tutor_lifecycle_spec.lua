local failures = {}
local checks = 0

local function check(condition, message)
    checks = checks + 1
    if not condition then failures[#failures + 1] = message end
end

local function equal(actual, expected, message)
    check(vim.deep_equal(actual, expected), ('%s (expected %s, got %s)'):format(message, vim.inspect(expected), vim.inspect(actual)))
end

local function wait_for(predicate, message, timeout)
    local ok = vim.wait(timeout or 3000, predicate, 10)
    check(ok, message)
    return ok
end

local root = vim.fn.tempname()
vim.fn.mkdir(root .. '/.tutor', 'p')
vim.fn.mkdir(root .. '/.state', 'p')
local source_path = root .. '/lifecycle.c'
vim.fn.writefile({
    'int main(void) {',
    '    // tutor: slow first request?',
    '    // t: second queued request?',
    '    return 0;',
    '}',
}, source_path)

vim.cmd('edit ' .. vim.fn.fnameescape(source_path))
vim.bo.filetype = 'c'
local bufnr = vim.api.nvim_get_current_buf()
local tutor = require 'custom.c_tutor'
local render = require 'custom.c_tutor_render'
local fake_omp = vim.fn.getcwd() .. '/tests/fake_omp.py'
vim.notify = function() end

tutor.setup {
    command = { 'python3', fake_omp, '--mode', 'normal' },
    rpc_cwd = root,
    state_dir = root .. '/.state',
    git_check = false,
    ask_debounce_ms = 10,
    insert_debounce_ms = 10,
    request_timeout_ms = 1000,
}
wait_for(function() return tutor._test.state.client_status == 'ready' end, 'RPC prewarms for lifecycle tests')

vim.api.nvim_win_set_cursor(0, { 2, 0 })
check(tutor.ask_current(), 'first marker request starts')
vim.api.nvim_win_set_cursor(0, { 3, 0 })
check(tutor.ask_current(), 'second marker queues behind the active first request')
equal(tutor._test.state.queue[1] and tutor._test.state.queue[1].request.question, 'second queued request?', 'second marker is the pending request')
equal(render.get(bufnr) and render.get(bufnr).state, 'thinking', 'pending tracker does not replace the visible active thinking state')

vim.api.nvim_buf_set_lines(bufnr, 0, 0, false, { '// inserted while cancellation settles' })
tutor._test.invalidate(bufnr)
wait_for(function()
    local last = tutor._test.state.last_response[bufnr]
    return last and last.request.question == 'second queued request?'
end, 'queued marker follows line movement and still receives its response')
local last = tutor._test.state.last_response[bufnr]
check(last and render.position(bufnr, last.mark_id) == 4, 'queued marker response renders at its moved line')
vim.api.nvim_win_set_cursor(0, { 3, 0 })
check(tutor.more(), 'deeper request starts from a selected older marker response')
equal(
    tutor._test.state.active and tutor._test.state.active.request.anchor_line,
    3,
    'deeper request targets the response under the cursor instead of the globally latest response'
)
wait_for(function()
    local response = tutor._test.state.last_response[bufnr]
    return response and response.request.interaction == 'more'
end, 'cursor-selected deeper request completes')
tutor._test.invalidate(bufnr)

local moved_mark_id = last.mark_id
vim.api.nvim_buf_set_lines(bufnr, 3, 4, false, {})
tutor._test.invalidate(bufnr)
local fallback_response = tutor._test.state.last_response[bufnr]
check(
    fallback_response and fallback_response.request.interaction == 'more' and fallback_response.request.marker_question == 'slow first request?',
    'removing the latest response falls back to the permanent deeper decoration on another marker'
)
check(not render.exists(bufnr, moved_mark_id), 'deleting a marker removes its completed annotation')
vim.api.nvim_win_set_cursor(0, { 1, 0 })
vim.cmd 'undo'
tutor._test.invalidate(bufnr)
local restored_mark_id
wait_for(function()
    for mark_id, annotation in pairs(tutor._test.state.annotations[bufnr] or {}) do
        if annotation.request.question == 'second queued request?' then
            restored_mark_id = mark_id
            return true
        end
    end
    return false
end, 'undoing marker deletion restores its cached response even when the cursor is elsewhere')
if restored_mark_id then
    local restored_line = render.position(bufnr, restored_mark_id)
    equal(
        tutor._test.marker_question(vim.api.nvim_buf_get_lines(bufnr, restored_line - 1, restored_line, false)[1]),
        'second queued request?',
        'undo-restored annotation is attached to its marker'
    )
end

local line_count = vim.api.nvim_buf_line_count(bufnr)
vim.api.nvim_buf_set_lines(bufnr, line_count - 1, line_count - 1, false, {
    '    // tutor: slow active marker to delete?',
    '    // coach: queued marker must survive?',
})
local active_line = line_count
local queued_line = line_count + 1
vim.api.nvim_win_set_cursor(0, { active_line, 0 })
check(tutor.ask_current(), 'new active marker request starts')
vim.api.nvim_win_set_cursor(0, { queued_line, 0 })
check(tutor.ask_current(), 'second new marker waits behind the active request')
equal(#tutor._test.state.queue, 1, 'one request is pending while another is active')

vim.api.nvim_buf_set_lines(bufnr, active_line - 1, active_line, false, {})
tutor._test.invalidate(bufnr)
wait_for(function()
    local response = tutor._test.state.last_response[bufnr]
    return response and response.request.question == 'queued marker must survive?'
end, 'deleting the active marker starts the still-valid pending marker')
local surviving = tutor._test.state.last_response[bufnr]
check(surviving and render.position(bufnr, surviving.mark_id) == active_line, 'pending marker follows the deleted active line')
equal(#tutor._test.state.queue, 0, 'pending queue drains after cancellation')

line_count = vim.api.nvim_buf_line_count(bufnr)
vim.api.nvim_buf_set_lines(bufnr, line_count - 1, line_count - 1, false, {
    '    // tutor: slow active marker remains?',
    '    // c: pending marker will be deleted?',
})
active_line = line_count
queued_line = line_count + 1
vim.api.nvim_win_set_cursor(0, { active_line, 0 })
check(tutor.ask_current(), 'active request starts before pending-deletion case')
vim.api.nvim_win_set_cursor(0, { queued_line, 0 })
check(tutor.ask_current(), 'deletable marker enters the pending queue')
vim.api.nvim_buf_set_lines(bufnr, queued_line - 1, queued_line, false, {})
tutor._test.invalidate(bufnr)
equal(#tutor._test.state.queue, 0, 'deleting a pending marker removes its queued request')
wait_for(function()
    local response = tutor._test.state.last_response[bufnr]
    return response and response.request.question == 'slow active marker remains?'
end, 'deleting a pending marker does not cancel the active marker')
local deleted_pending_found = false
for _, annotation in pairs(tutor._test.state.annotations[bufnr] or {}) do
    if annotation.request.question == 'pending marker will be deleted?' then deleted_pending_found = true end
end
check(not deleted_pending_found, 'deleted pending marker leaves no orphan annotation')

line_count = vim.api.nvim_buf_line_count(bufnr)
vim.api.nvim_buf_set_lines(bufnr, line_count - 1, line_count - 1, false, {
    '    // tutor: slow request to dismiss?',
})
local dismiss_line = line_count
vim.api.nvim_win_set_cursor(0, { dismiss_line, 0 })
check(tutor.ask_current(), 'dismissal fixture starts an active marker request')
local dismissed_mark_id = tutor._test.state.active and tutor._test.state.active.mark_id
check(tutor.dismiss(), 'dismiss removes the current active marker')
check(tutor._test.state.active == nil, 'dismissing active thinking cancels lifecycle state immediately')
wait_for(function() return tutor._test.state.client:status() == 'ready' end, 'dismiss abort returns RPC to ready')
check(not render.exists(bufnr, dismissed_mark_id), 'dismissed thinking mark cannot render a late response')

line_count = vim.api.nvim_buf_line_count(bufnr)
vim.api.nvim_buf_set_lines(bufnr, line_count - 1, line_count - 1, false, {
    '    // tutor: insert mode waits for InsertLeave?',
})
local insert_wait_line = line_count
vim.api.nvim_win_set_cursor(0, { insert_wait_line, 0 })
vim.api.nvim_exec_autocmds('TextChangedI', { buffer = bufnr })
vim.wait(50, function() return false end, 10)
local insert_started = false
for _, annotation in pairs(tutor._test.state.annotations[bufnr] or {}) do
    if annotation.request.question == 'insert mode waits for InsertLeave?' then insert_started = true end
end
check(not insert_started, 'TextChangedI never starts a tutor request while Insert mode is active')
check(tutor._test.state.schedules[bufnr] == nil, 'TextChangedI leaves no delayed request that can fire during Insert mode')
vim.api.nvim_exec_autocmds('InsertLeave', { buffer = bufnr })
wait_for(function()
    local response = tutor._test.state.last_response[bufnr]
    return response and response.request.question == 'insert mode waits for InsertLeave?'
end, 'InsertLeave dispatches the stable marker after editing finishes')

line_count = vim.api.nvim_buf_line_count(bufnr)
vim.api.nvim_buf_set_lines(bufnr, line_count - 1, line_count - 1, false, {
    '    // tutor: slow request cancelled by InsertEnter?',
})
local insert_cancel_line = line_count
vim.api.nvim_win_set_cursor(0, { insert_cancel_line, 0 })
check(tutor.ask_current(), 'InsertEnter cancellation fixture starts active work')
local insert_cancel_mark_id = tutor._test.state.active and tutor._test.state.active.mark_id
vim.api.nvim_exec_autocmds('InsertEnter', { buffer = bufnr })
check(tutor._test.state.active == nil, 'InsertEnter cancels an active tutor request immediately')
check(not render.exists(bufnr, insert_cancel_mark_id), 'InsertEnter removes the cancelled thinking decoration')
wait_for(function() return tutor._test.state.client:status() == 'ready' end, 'InsertEnter cancellation returns RPC to ready')
local cancelled_insert_found = false
for _, annotation in pairs(tutor._test.state.annotations[bufnr] or {}) do
    if annotation.request.question == 'slow request cancelled by InsertEnter?' then cancelled_insert_found = true end
end
check(not cancelled_insert_found, 'cancelled InsertEnter request cannot render a late response')

line_count = vim.api.nvim_buf_line_count(bufnr)
vim.api.nvim_buf_set_lines(bufnr, line_count - 1, line_count - 1, false, {
    '    // tutor: debounce survives unrelated edit?',
})
local debounce_marker_line = line_count
vim.api.nvim_win_set_cursor(0, { debounce_marker_line, 0 })
vim.api.nvim_exec_autocmds('TextChanged', { buffer = bufnr })
vim.api.nvim_win_set_cursor(0, { 1, 0 })
vim.api.nvim_buf_set_lines(bufnr, 0, 1, false, { '// unrelated edit before marker debounce fires' })
vim.api.nvim_exec_autocmds('TextChanged', { buffer = bufnr })
wait_for(function()
    local response = tutor._test.state.last_response[bufnr]
    return response and response.request.question == 'debounce survives unrelated edit?'
end, 'unrelated edits do not cancel a stable marker debounce')

line_count = vim.api.nvim_buf_line_count(bufnr)
vim.api.nvim_buf_set_lines(bufnr, line_count - 1, line_count - 1, false, {
    '    // tutor: deleted before debounce?',
})
local deleted_debounce_line = line_count
vim.api.nvim_win_set_cursor(0, { deleted_debounce_line, 0 })
vim.api.nvim_exec_autocmds('TextChanged', { buffer = bufnr })
vim.api.nvim_buf_set_lines(bufnr, deleted_debounce_line - 1, deleted_debounce_line, false, {})
vim.api.nvim_exec_autocmds('TextChanged', { buffer = bufnr })
vim.wait(50, function() return false end, 10)
local deleted_debounce_found = false
for _, annotation in pairs(tutor._test.state.annotations[bufnr] or {}) do
    if annotation.request.question == 'deleted before debounce?' then deleted_debounce_found = true end
end
check(not deleted_debounce_found, 'deleting a marker before its debounce prevents a request')
check(tutor._test.state.schedules[bufnr] == nil, 'deleted marker leaves no scheduled debounce')

line_count = vim.api.nvim_buf_line_count(bufnr)
vim.api.nvim_buf_set_lines(bufnr, line_count - 1, line_count - 1, false, {
    '    // tutor: slow independent debounce one?',
    '    // tutor: independent debounce two?',
})
local first_debounce_line = line_count
local second_debounce_line = line_count + 1
vim.api.nvim_win_set_cursor(0, { first_debounce_line, 0 })
vim.api.nvim_exec_autocmds('TextChanged', { buffer = bufnr })
vim.api.nvim_win_set_cursor(0, { second_debounce_line, 0 })
vim.api.nvim_exec_autocmds('TextChanged', { buffer = bufnr })
wait_for(
    function()
        return tutor._test.state.active
            and tutor._test.state.active.request.question == 'slow independent debounce one?'
            and tutor._test.state.queue[1]
            and tutor._test.state.queue[1].request.question == 'independent debounce two?'
    end,
    'independent marker debounces both fire and the second queues'
)
wait_for(function()
    local found = {}
    for _, annotation in pairs(tutor._test.state.annotations[bufnr] or {}) do
        if annotation.response then found[annotation.request.question] = true end
    end
    return found['slow independent debounce one?'] and found['independent debounce two?']
end, 'independently scheduled markers both receive responses')

line_count = vim.api.nvim_buf_line_count(bufnr)
vim.api.nvim_buf_set_lines(bufnr, line_count - 1, line_count - 1, false, {
    '    // tutor: stale debounce question?',
})
local edited_debounce_line = line_count
vim.api.nvim_win_set_cursor(0, { edited_debounce_line, 0 })
vim.api.nvim_exec_autocmds('TextChanged', { buffer = bufnr })
vim.api.nvim_buf_set_lines(bufnr, edited_debounce_line - 1, edited_debounce_line, false, {
    '    // tutor: final debounce question?',
})
vim.api.nvim_exec_autocmds('TextChanged', { buffer = bufnr })
local scheduled_questions = {}
for _, entry in pairs(tutor._test.state.schedules[bufnr] or {}) do
    scheduled_questions[#scheduled_questions + 1] = entry.question
end
equal(scheduled_questions, { 'final debounce question?' }, 'editing one marker coalesces its debounce to the final question')
wait_for(function()
    local response = tutor._test.state.last_response[bufnr]
    return response and response.request.question == 'final debounce question?'
end, 'coalesced marker debounce answers only the final question')
for _, annotation in pairs(tutor._test.state.annotations[bufnr] or {}) do
    check(annotation.request.question ~= 'stale debounce question?', 'stale coalesced question leaves no annotation')
end

line_count = vim.api.nvim_buf_line_count(bufnr)
vim.api.nvim_buf_set_lines(bufnr, line_count - 1, line_count - 1, false, {
    '    // t: split window marker?',
})
local split_marker_line = line_count
vim.cmd 'vsplit'
local windows = vim.fn.win_findbuf(bufnr)
check(#windows == 2, 'split-window fixture shows the tutor buffer twice')
local lookup_window = vim.fn.bufwinid(bufnr)
local marker_window = windows[1] == lookup_window and windows[2] or windows[1]
vim.api.nvim_win_set_cursor(lookup_window, { 1, 0 })
vim.api.nvim_win_set_cursor(marker_window, { split_marker_line, 0 })
vim.api.nvim_set_current_win(marker_window)
check(tutor._test.anticipate_buffer(bufnr), 'marker detection uses the active split cursor')
wait_for(function()
    local response = tutor._test.state.last_response[bufnr]
    return response and response.request.question == 'split window marker?'
end, 'active split marker receives a response')

local unload_path = root .. '/unload.c'
vim.fn.writefile({
    'int unload_fixture(void) {',
    '    // tutor: slow request cancelled by buffer unload?',
    '    return 2;',
    '}',
}, unload_path)
vim.cmd('edit ' .. vim.fn.fnameescape(unload_path))
vim.bo.filetype = 'c'
local unload_bufnr = vim.api.nvim_get_current_buf()
vim.api.nvim_win_set_cursor(0, { 2, 0 })
check(tutor.ask_current(), 'buffer-unload fixture starts an active request')
local unload_mark_id = tutor._test.state.active and tutor._test.state.active.mark_id
vim.api.nvim_set_current_buf(bufnr)
vim.cmd(('bunload! %d'):format(unload_bufnr))
check(not vim.api.nvim_buf_is_loaded(unload_bufnr), 'buffer-unload fixture is actually unloaded')
check(tutor._test.state.active == nil, 'unloading a buffer cancels its active request immediately')
check(tutor._test.state.schedules[unload_bufnr] == nil, 'unloading a buffer clears its scheduled marker work')
check(not render.get(unload_bufnr, unload_mark_id), 'unloading a buffer clears renderer bookkeeping')
wait_for(function() return tutor._test.state.client:status() == 'ready' end, 'buffer unload returns RPC to ready')

local filetype_path = root .. '/filetype.c'
vim.fn.writefile({
    'int filetype_fixture(void) {',
    '    // tutor: slow request cancelled when C eligibility is lost?',
    '    return 3;',
    '}',
}, filetype_path)
vim.cmd('edit ' .. vim.fn.fnameescape(filetype_path))
vim.bo.filetype = 'c'
local filetype_bufnr = vim.api.nvim_get_current_buf()
vim.api.nvim_win_set_cursor(0, { 2, 0 })
check(tutor.ask_current(), 'filetype-change fixture starts an active request')
local filetype_mark_id = tutor._test.state.active and tutor._test.state.active.mark_id
vim.bo.filetype = 'cpp'
check(tutor._test.state.active == nil, 'leaving the C filetype cancels active tutor work immediately')
check(not render.get(filetype_bufnr, filetype_mark_id), 'leaving the C filetype clears tutor annotations')
equal(vim.b[filetype_bufnr].c_tutor_mode, nil, 'ineligible filetype clears the tutor buffer mode')
wait_for(function() return tutor._test.state.client:status() == 'ready' end, 'filetype change returns RPC to ready')
vim.bo.filetype = 'c'
vim.api.nvim_win_set_cursor(0, { 2, 0 })
check(tutor.ask_current(), 'restored C eligibility accepts a new request')
wait_for(function()
    local response = tutor._test.state.last_response[filetype_bufnr]
    return response and response.request.question == 'slow request cancelled when C eligibility is lost?'
end, 'restored C eligibility completes normally')
local renamed_mark_id = tutor._test.state.last_response[filetype_bufnr].mark_id
vim.cmd('file ' .. vim.fn.fnameescape(root .. '/filetype.txt'))
equal(vim.b[filetype_bufnr].c_tutor_mode, nil, 'renaming a C buffer to a non-C path clears tutor mode')
check(not render.get(filetype_bufnr, renamed_mark_id), 'renaming a C buffer to a non-C path clears annotations')
vim.api.nvim_set_current_buf(bufnr)
vim.cmd 'only'

local other_path = root .. '/other.c'
vim.fn.writefile({
    'int helper(void) {',
    '    // tutor: response in second buffer?',
    '    return 1;',
    '}',
}, other_path)
vim.cmd('edit ' .. vim.fn.fnameescape(other_path))
vim.bo.filetype = 'c'
local other_bufnr = vim.api.nvim_get_current_buf()
vim.api.nvim_win_set_cursor(0, { 2, 0 })
check(tutor.ask_current(), 'second buffer marker request starts')
wait_for(function()
    local response = tutor._test.state.last_response[other_bufnr]
    return response and response.request.question == 'response in second buffer?'
end, 'second buffer receives a marker response')
local other_mark_id = tutor._test.state.last_response[other_bufnr].mark_id
vim.api.nvim_buf_set_lines(other_bufnr, 1, 2, false, { '    // tutor: slow active response in second buffer?' })
tutor._test.invalidate(other_bufnr)
vim.api.nvim_win_set_cursor(0, { 2, 0 })
check(tutor.ask_current(), 'second buffer starts an active request before root shutdown')
local other_active_mark_id = tutor._test.state.active and tutor._test.state.active.mark_id
check(other_active_mark_id ~= nil, 'second buffer owns the active request')

vim.api.nvim_set_current_buf(bufnr)
check(tutor.mode 'off' == 'off', 'root tutor mode turns off')
check(not render.exists(bufnr, surviving.mark_id), 'mode off clears current buffer annotations')
check(not render.exists(other_bufnr, other_mark_id), 'mode off clears annotations in every loaded buffer for the root')
check(not render.exists(other_bufnr, other_active_mark_id), 'mode off removes the active annotation in another buffer')
wait_for(function() return tutor._test.state.client:status() == 'ready' end, 'mode off cancels the cross-buffer request cleanly')
check(tutor._test.state.active == nil and #tutor._test.state.queue == 0, 'mode off leaves no active or pending work')
equal(vim.b[bufnr].c_tutor_mode, 'off', 'mode off updates current buffer status')
equal(vim.b[other_bufnr].c_tutor_mode, 'off', 'mode off updates second buffer status')

local log_path = root .. '/.state/events.jsonl'
check(vim.uv.fs_stat(log_path) ~= nil, 'integrated tutor writes a structured event log')
local logged_events = {}
local raw_log = ''
if vim.uv.fs_stat(log_path) then
    raw_log = table.concat(vim.fn.readfile(log_path), '\n')
    for line in raw_log:gmatch '[^\n]+' do
        local ok, event = pcall(vim.json.decode, line)
        if ok then logged_events[#logged_events + 1] = event end
    end
end
local event_names = {}
for _, event in ipairs(logged_events) do
    event_names[event.event] = true
end
check(event_names.buffer_activated, 'event log records buffer activation')
check(event_names.request_started, 'event log records request start')
check(event_names.request_queued, 'event log records pending transitions')
check(event_names.request_completed, 'event log records accepted responses')
check(event_names.annotation_removed, 'event log records why annotations disappear')
check(event_names.mode_changed, 'event log records root mode transitions')
check(not raw_log:find('second queued request?', 1, true), 'event log does not persist raw marker questions')

if tutor._test.state.client then tutor._test.state.client:stop() end
render.clear(bufnr)
vim.cmd 'bwipeout!'
vim.fn.delete(root, 'rf')

if #failures > 0 then error(('C tutor lifecycle tests failed (%d/%d):\n- %s'):format(#failures, checks, table.concat(failures, '\n- '))) end
print(('C tutor lifecycle tests passed: %d checks'):format(checks))
