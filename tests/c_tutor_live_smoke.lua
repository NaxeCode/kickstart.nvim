local root = vim.fn.tempname()
vim.fn.mkdir(root .. '/.tutor', 'p')
local source_path = root .. '/sample.c'
local source = {
    'int main(void) {',
    '    // tutor: what is the syntax for a mutable C string?',
    '    int values[2] = { 1, 2 };',
    '    return values[2];',
    '}',
}
vim.fn.writefile(source, source_path)

local notifications = {}
vim.notify = function(message, level) notifications[#notifications + 1] = { message = message, level = level } end

vim.cmd('edit ' .. vim.fn.fnameescape(source_path))
vim.bo.filetype = 'c'
vim.api.nvim_win_set_cursor(0, { 2, 0 })

local tutor = require 'custom.c_tutor'
local backend_override = vim.env.C_TUTOR_LIVE_BACKEND
local model_override = vim.env.C_TUTOR_LIVE_MODEL
local backend = backend_override or 'omp'
local model = model_override or (backend == 'gemini' and 'google/gemini-3.5-flash-lite' or 'meta/muse-spark-1.2-contributor')
local render = require 'custom.c_tutor_render'
local setup_options = {
    state_dir = root .. '/.state',
    git_check = false,
    request_timeout_ms = 30000,
}
if backend_override then setup_options.backend = backend_override end
if model_override then setup_options.model = model_override end
local setup_started = vim.uv.hrtime()
tutor.setup(setup_options)
assert(vim.wait(10000, function() return tutor._test.state.client_status == 'ready' end, 20), 'live tutor transport did not become ready')
local prewarm_ms = (vim.uv.hrtime() - setup_started) / 1000000
assert(tutor._test.state.last_response[vim.api.nvim_get_current_buf()] == nil, 'prewarm sent an unrequested model prompt')

assert(tutor.statusline() == 'Tutor:coach', 'live tutor did not default to visible coach mode')
local current = vim.api.nvim_get_current_buf()
local request_started = vim.uv.hrtime()
assert(tutor._test.anticipate_buffer(current), 'live marker request did not start')
local completed = vim.wait(
    35000,
    function()
        return tutor._test.state.last_response[vim.api.nvim_get_current_buf()] ~= nil
            or (#notifications > 0 and notifications[#notifications].level >= vim.log.levels.ERROR)
    end,
    20
)
assert(completed, 'live tutor request did not complete')
local response_ms = (vim.uv.hrtime() - request_started) / 1000000

local bufnr = vim.api.nvim_get_current_buf()
local last = tutor._test.state.last_response[bufnr]
if not last then error(notifications[#notifications] and notifications[#notifications].message or 'live tutor returned no response') end
assert(last.request.interaction == 'ask', 'live marker did not use the explicit ask interaction')
assert(last.request.question == 'what is the syntax for a mutable C string?', 'live marker question changed before submission')
assert(last.response.kind == 'answer' and last.response.help_kind == 'syntax', 'live syntax marker did not receive a direct syntax answer')
assert(last.response.sections == nil, 'live syntax answer unexpectedly expanded into structured concept sections')
assert(last.response.neutral_example ~= nil, 'live syntax answer omitted its minimal neutral example')
assert(render.get(bufnr) and render.get(bufnr).state == 'response', 'live response did not render')
assert(last.elapsed_seconds and last.elapsed_seconds > 0, 'live response omitted total thinking duration')
local response_mark = render.get(bufnr)
local response_extmark = vim.api.nvim_buf_get_extmark_by_id(bufnr, render.namespace, response_mark.id, { details = true })
local duration_chunk = response_extmark[3].virt_lines[1][#response_extmark[3].virt_lines[1]]
assert(duration_chunk[1]:match ' · %d%d%.%d%ds$', 'live response did not retain the completed request time')
assert(duration_chunk[2] == 'CTutorAccent', 'live completed request time lost its orange accent')
assert(last.provenance.model == model, 'live response did not record the selected model')
assert(last.provenance.thinking_level == 'auto', 'live response did not use automatic thinking effort')
assert(last.provenance.source == 'fresh', 'live response did not identify fresh inference')
local code_groups = {}
local ai_badge = false
for _, line in ipairs(response_extmark[3].virt_lines) do
    for _, chunk in ipairs(line) do
        if chunk[1]:find('AI C', 1, true) then ai_badge = true end
        code_groups[chunk[2]] = true
    end
end
assert(ai_badge, 'live neutral example was not labeled as AI-generated C')
assert(code_groups.CTutorCodeType, 'live neutral example omitted semantic C type highlighting')
assert(code_groups.CTutorCodeString, 'live neutral example omitted semantic C string highlighting')
local footer = ''
for _, chunk in ipairs(response_extmark[3].virt_lines[#response_extmark[3].virt_lines]) do
    footer = footer .. chunk[1]
    assert(chunk[2] == 'CTutorAccent', 'live provenance footer lost its orange accent')
end
assert(footer:find(model, 1, true), 'live provenance footer omitted the selected model')
assert(footer:find('thinking low', 1, true), 'live provenance footer omitted thinking metadata')
assert(footer:find('fresh', 1, true), 'live provenance footer omitted source metadata')
assert(vim.deep_equal(vim.fn.readfile(source_path), source), 'live tutor changed the source fixture')

local status = tutor._test.state.client:status()
assert(status == 'ready', 'live transport did not return to ready state: ' .. status)

local client = tutor._test.state.client
local warm_process = client.process
local abort_done = false
local abort_error
assert(
    client:request(require('custom.c_tutor_prompt').build(last.request), last.request, function(err)
        abort_error = err
        abort_done = true
    end),
    'live cancellation fixture did not start'
)
assert(vim.wait(5000, function() return client:status() == 'thinking' end, 20), 'live cancellation fixture did not reach the model')
assert(client:cancel 'Live tutor cancellation', 'live tutor cancellation was rejected')
assert(vim.wait(5000, function() return abort_done end, 20), 'live transport cancellation did not complete')
assert(abort_error == 'Live tutor cancellation', 'live transport returned the wrong cancellation reason')
if backend == 'omp' then assert(client.process == warm_process, 'live OMP cancellation discarded the prewarmed process') end
assert(client:status() == 'ready', 'live cancellation did not return to ready')
tutor._test.state.client:stop()
render.clear(bufnr)
vim.cmd 'bwipeout!'
vim.fn.delete(root, 'rf')
print(('C tutor live %s smoke passed: prewarm=%.0fms response=%.0fms'):format(backend, prewarm_ms, response_ms))
