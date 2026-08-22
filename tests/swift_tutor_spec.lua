local failures = {}
local checks = 0

local function check(condition, message)
    checks = checks + 1
    if not condition then failures[#failures + 1] = message end
end

local function equal(actual, expected, message)
    check(vim.deep_equal(actual, expected), ('%s (expected %s, got %s)'):format(message, vim.inspect(expected), vim.inspect(actual)))
end

local function wait_for(predicate, message) check(vim.wait(3000, predicate, 10), message) end

local root = vim.fn.tempname()
vim.fn.mkdir(root .. '/.tutor', 'p')
vim.fn.mkdir(root .. '/.state', 'p')
vim.fn.writefile({ vim.json.encode { version = 2, kcs = {}, references = {} } }, root .. '/.tutor/state.json')
local source_path = root .. '/Example.swift'
vim.fn.writefile({
    'struct Counter {',
    '    // tutor: how do I create a mutable array?',
    '    var value = 0',
    '}',
}, source_path)

local languages = require 'custom.tutor_languages'
local prompt = require 'custom.c_tutor_prompt'
local render = require 'custom.c_tutor_render'
local tutor = require 'custom.c_tutor'
local fake_omp = vim.fn.getcwd() .. '/tests/fake_omp.py'

vim.cmd('edit ' .. vim.fn.fnameescape(source_path))
vim.bo.filetype = 'swift'
local bufnr = vim.api.nvim_get_current_buf()
vim.api.nvim_win_set_cursor(0, { 2, 0 })

tutor.setup {
    command = { 'python3', fake_omp, '--mode', 'normal' },
    rpc_cwd = root,
    state_dir = root .. '/.state',
    request_timeout_ms = 2000,
    ask_debounce_ms = 1,
}

local info, info_error = tutor._test.project_info(bufnr)
check(info ~= nil, 'Swift buffer inside .tutor root is eligible: ' .. tostring(info_error))
equal(info and info.profile.id, 'swift', 'Swift buffer selects the Swift tutor profile')
equal(info and info.mode, 'coach', 'Swift tutor uses the normal default mode')
equal(tutor.statusline(), 'Tutor:coach', 'Swift tutor appears in the shared statusline')

local request, request_error = tutor._test.request_for(bufnr, 2, 'ask', 'how do I create a mutable array?')
check(request ~= nil, 'Swift request is constructed: ' .. tostring(request_error))
local envelope = request and vim.json.decode(prompt.build(request)) or {}
equal(envelope.protocol, 'swift-tutor/v1', 'Swift request uses the Swift protocol')
equal(envelope.file and envelope.file.language, 'swift', 'Swift request declares its language')
equal(envelope.file and envelope.file.standard, 'swift6', 'Swift request declares its language standard')
check(envelope.constraints and envelope.constraints:find('Swift', 1, true) ~= nil, 'Swift request carries language-specific constraints')

check(vim.tbl_contains(languages.patterns, '*.swift'), 'Swift profile contributes its autocmd pattern')
check(vim.tbl_contains(languages.parsers(), 'swift'), 'Swift profile contributes its Tree-sitter parser')
local highlighted, parsed = render._test.ai_code_lines('var scores = [1, 2]', 'swift')
check(parsed, 'Swift examples parse with the Swift Tree-sitter grammar')
check(#highlighted > 0, 'Swift syntax highlighting produces rendered chunks')

check(tutor._test.anticipate_buffer(bufnr), 'Swift tutor marker starts a request')
wait_for(function()
    local last = tutor._test.state.last_response[bufnr]
    return last and last.response and last.response.concept == 'swift.collections.array'
end, 'Swift tutor response is rendered')
local last = tutor._test.state.last_response[bufnr]
check(last and last.response.neutral_example == 'var scores = [1, 2]', 'Swift backend fixture returns Swift syntax')

local mark = last and render.get(bufnr, last.mark_id)
local badge_found = false
if mark then
    local extmark = vim.api.nvim_buf_get_extmark_by_id(bufnr, render.namespace, last.mark_id, { details = true })
    for _, line in ipairs((extmark[3] or {}).virt_lines or {}) do
        for _, chunk in ipairs(line) do
            if chunk[1]:find('AI Swift', 1, true) then badge_found = true end
        end
    end
end
check(badge_found, 'Rendered example is badged as AI Swift')

tutor._test.state.client:stop()
render.clear(bufnr)
vim.cmd 'bwipeout!'
vim.fn.delete(root, 'rf')

if #failures > 0 then error(('Swift tutor tests failed (%d/%d):\n- %s'):format(#failures, checks, table.concat(failures, '\n- '))) end
print(('Swift tutor tests passed: %d checks'):format(checks))
