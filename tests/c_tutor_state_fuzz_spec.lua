local failures = {}
local checks = 0

local function check(condition, message)
    checks = checks + 1
    if not condition then failures[#failures + 1] = message end
end

local root = vim.fn.tempname()
vim.fn.mkdir(root .. '/.tutor', 'p')
root = vim.uv.fs_realpath(root) or root
vim.fn.mkdir(root .. '/.state', 'p')
local source_path = root .. '/fuzz.c'
vim.fn.writefile({ 'int main(void) {', '    return 0;', '}' }, source_path)
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
    request_timeout_ms = 1000,
}
check(vim.wait(3000, function() return tutor._test.state.client_status == 'ready' end, 10), 'RPC prewarms for state fuzzer')

local questions = {
    'how do I declare alpha?',
    'how do I declare beta?',
    'how do I declare gamma?',
    'how do I declare delta?',
    'how do I declare epsilon?',
}
local aliases = { 'tutor', 'coach', 't', 'c' }
for index, question in ipairs(questions) do
    local key = tutor._test.marker_cache_key(root, 'fuzz.c', question)
    tutor._test.state.cache[key] = {
        response = {
            version = 1,
            kind = 'answer',
            help_kind = 'syntax',
            anchor_line = 1,
            concept = 'c.fuzz-cache',
            title = 'Cached syntax',
            explanation = ('Use cached syntax pattern %d.'):format(index),
            neutral_example = ('char value%d[] = "ok";'):format(index),
            confidence = 1,
        },
        elapsed_seconds = index / 100,
        updated_at = index,
        interaction = 'ask',
        provenance = {
            model = 'test/fuzz-cache',
            thinking_level = false,
            source = 'fresh',
        },
    }
end

local function marker_line(question, alias) return ('    // %s: %s'):format(alias, question) end

local function assert_invariants(step)
    local expected = {}
    for line_number, line in ipairs(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)) do
        local question = tutor._test.marker_question(line)
        if question then expected[#expected + 1] = { line = line_number, question = question } end
    end

    local annotations = tutor._test.state.annotations[bufnr] or {}
    local seen = {}
    for mark_id, annotation in pairs(annotations) do
        local position = render.position(bufnr, mark_id)
        check(position ~= nil, ('step %d: annotation %d has a live extmark'):format(step, mark_id))
        if position then
            local line = vim.api.nvim_buf_get_lines(bufnr, position - 1, position, false)[1]
            check(
                tutor._test.marker_question(line) == annotation.request.question,
                ('step %d: annotation %d matches its marker question'):format(step, mark_id)
            )
            local identity = ('%d\0%s'):format(position, annotation.request.question)
            check(not seen[identity], ('step %d: marker identity is not duplicated'):format(step))
            seen[identity] = true
        end
        check(annotation.response ~= nil and annotation.phase == nil, ('step %d: cached annotation is a completed response'):format(step))
    end

    check(vim.tbl_count(annotations) == #expected, ('step %d: every marker has exactly one annotation'):format(step))
    check(vim.tbl_count(render.all(bufnr)) == vim.tbl_count(annotations), ('step %d: renderer and lifecycle state agree'):format(step))
    check(tutor._test.state.active == nil, ('step %d: cache-only reconciliation has no active request'):format(step))
    check(#tutor._test.state.queue == 0, ('step %d: cache-only reconciliation has no pending request'):format(step))
    local last = tutor._test.state.last_response[bufnr]
    check(
        (#expected == 0 and last == nil) or (#expected > 0 and last and annotations[last.mark_id]),
        ('step %d: last response points to visible state'):format(step)
    )
end

math.randomseed(20260821)
for step = 1, 300 do
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local operation = math.random(1, 6)
    if operation == 1 then
        local question = questions[math.random(#questions)]
        local alias = aliases[math.random(#aliases)]
        local index = math.random(2, math.max(2, #lines))
        table.insert(lines, index, marker_line(question, alias))
    elseif operation == 2 and #lines > 2 then
        table.remove(lines, math.random(2, #lines - 1))
    elseif operation == 3 then
        local index = math.random(2, math.max(2, #lines))
        table.insert(lines, index, ('    int ordinary_%d = %d;'):format(step, step))
    elseif operation == 4 then
        local marker_indexes = {}
        for index, line in ipairs(lines) do
            if tutor._test.marker_question(line) then marker_indexes[#marker_indexes + 1] = index end
        end
        if #marker_indexes > 0 then
            local index = marker_indexes[math.random(#marker_indexes)]
            local question = tutor._test.marker_question(lines[index])
            lines[index] = marker_line(question, aliases[math.random(#aliases)])
        end
    elseif operation == 5 and #lines > 3 then
        local from = math.random(2, #lines - 1)
        local value = table.remove(lines, from)
        table.insert(lines, math.random(2, #lines), value)
    elseif operation == 6 then
        local marker_indexes = {}
        for index, line in ipairs(lines) do
            if tutor._test.marker_question(line) then marker_indexes[#marker_indexes + 1] = index end
        end
        if #marker_indexes > 0 then
            local index = marker_indexes[math.random(#marker_indexes)]
            lines[index] = marker_line(questions[math.random(#questions)], aliases[math.random(#aliases)])
        end
    end

    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
    tutor._test.invalidate(bufnr)
    assert_invariants(step)
end

if tutor._test.state.client then tutor._test.state.client:stop() end
tutor._test.logger.stop()
render.clear(bufnr)
vim.cmd 'bwipeout!'
vim.fn.delete(root, 'rf')
if #failures > 0 then error(('C tutor state fuzzer failed (%d/%d):\n- %s'):format(#failures, checks, table.concat(failures, '\n- '))) end
print(('C tutor state fuzzer passed: %d checks across 300 transitions'):format(checks))
