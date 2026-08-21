local failures = {}
local checks = 0

local function check(condition, message)
    checks = checks + 1
    if not condition then failures[#failures + 1] = message end
end

local function wait_for(predicate, message, timeout)
    local ok = vim.wait(timeout or 3000, predicate, 10)
    check(ok, message)
    return ok
end

local root = vim.fn.tempname()
vim.fn.mkdir(root .. '/.tutor', 'p')
vim.fn.mkdir(root .. '/.state', 'p')
vim.fn.writefile({ '{broken-state' }, root .. '/.state/state.json')
vim.fn.writefile({ '{broken-cache' }, root .. '/.state/answers.json')
local source_path = root .. '/cache.c'
local question = 'how do I declare a cache test string?'
vim.fn.writefile({
    'int main(void) {',
    '    // tutor: ' .. question,
    '    return 0;',
    '}',
}, source_path)

vim.cmd('edit ' .. vim.fn.fnameescape(source_path))
vim.bo.filetype = 'c'
vim.api.nvim_win_set_cursor(0, { 2, 0 })
local bufnr = vim.api.nvim_get_current_buf()
local tutor = require 'custom.c_tutor'
local render = require 'custom.c_tutor_render'
local fake_omp = vim.fn.getcwd() .. '/tests/fake_omp.py'
vim.notify = function() end

local setup_ok, setup_error = pcall(tutor.setup, {
    command = { 'python3', fake_omp, '--mode', 'normal' },
    rpc_cwd = root,
    state_dir = root .. '/.state',
    git_check = false,
    request_timeout_ms = 1000,
})
check(setup_ok, 'corrupt state and cache files do not break tutor setup: ' .. tostring(setup_error))
wait_for(function() return tutor._test.state.client_status == 'ready' end, 'RPC still prewarms after corrupt persisted files')
check(vim.tbl_count(tutor._test.state.cache) == 0, 'corrupt cache fails closed to an empty cache')

local key = tutor._test.marker_cache_key(root, 'cache.c', question)
tutor._test.state.cache[key] = {
    response = { version = 999, kind = 'answer' },
    elapsed_seconds = 1,
    updated_at = os.time(),
    interaction = 'ask',
}
check(tutor.ask_current(), 'invalid cached response falls through to a model request')
wait_for(function()
    local response = tutor._test.state.last_response[bufnr]
    return response and response.request.question == question and not response.cached
end, 'model replaces invalid cached response')
check(tutor._test.state.cache[key] and tutor._test.state.cache[key].response.version == 1, 'validated model response replaces invalid cache data')

local log_path = root .. '/.state/events.jsonl'
local events = {}
for _, line in ipairs(vim.fn.readfile(log_path)) do
    local ok, event = pcall(vim.json.decode, line)
    if ok then events[event.event] = true end
end
check(events.state_load_failed, 'event log identifies corrupt mode state')
check(events.cache_load_failed, 'event log identifies corrupt answer cache')
check(events.cache_entry_invalid, 'event log identifies invalid cached response data')
check(events.cache_written, 'event log records cache repair write')

for index = 1, 260 do
    tutor._test.state.cache[vim.fn.sha256(('synthetic-%03d'):format(index))] = {
        response = {
            version = 1,
            kind = 'answer',
            help_kind = 'syntax',
            anchor_line = 2,
            concept = 'c.cache-test',
            title = 'Cache test',
            explanation = 'Use a bounded synthetic cache entry.',
            confidence = 1,
        },
        elapsed_seconds = 0.1,
        updated_at = index,
        interaction = 'ask',
    }
end
check(tutor._test.save_cache(), 'cache limit fixture persists successfully')
check(vim.tbl_count(tutor._test.state.cache) == 256, 'in-memory cache prunes to its configured limit')
local persisted_cache = vim.json.decode(table.concat(vim.fn.readfile(tutor._test.cache_path()), '\n'))
check(vim.tbl_count(persisted_cache.entries) == 256, 'persisted cache prunes to its configured limit')
local cache_stat = vim.uv.fs_stat(tutor._test.cache_path())
check(cache_stat and bit.band(cache_stat.mode, 511) == 384, 'persisted cache permissions remain 0600')

if tutor._test.state.client then tutor._test.state.client:stop() end
tutor._test.logger.stop()
render.clear(bufnr)
vim.cmd 'bwipeout!'
vim.fn.delete(root, 'rf')
if #failures > 0 then error(('C tutor cache tests failed (%d/%d):\n- %s'):format(#failures, checks, table.concat(failures, '\n- '))) end
print(('C tutor cache tests passed: %d checks'):format(checks))
