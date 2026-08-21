local failures = {}
local checks = 0

local function check(condition, message)
    checks = checks + 1
    if not condition then failures[#failures + 1] = message end
end

local function equal(actual, expected, message)
    check(vim.deep_equal(actual, expected), ('%s (expected %s, got %s)'):format(message, vim.inspect(expected), vim.inspect(actual)))
end

local root = vim.fn.tempname()
vim.fn.mkdir(root, 'p')
local path = root .. '/events.jsonl'
local logger = require 'custom.c_tutor_log'
logger.setup { path = path, max_bytes = 1024, session = 'test-session' }
logger.event('buffer_event', {
    trigger = 'TextChangedI',
    file = 'sample.c',
    line = 7,
    question_id = 'abc123',
})
logger.event('request_started', { generation = 3, queue_depth = 1 })
logger.stop()

local lines = vim.fn.readfile(path)
check(#lines >= 4, 'logger records session start, events, and session stop')
local decoded = {}
for index, line in ipairs(lines) do
    local ok, value = pcall(vim.json.decode, line)
    check(ok and type(value) == 'table', ('log line %d is valid JSON'):format(index))
    decoded[index] = value
end
local first = decoded[1]
equal(first and first.event, 'session_start', 'first log event starts the session')
equal(first and first.session, 'test-session', 'every log session has a stable identifier')
check(first and first.timestamp:match '^%d%d%d%d%-%d%d%-%d%dT%d%d:%d%d:%d%d%.%d%d%dZ$', 'log timestamp has UTC millisecond precision')
for index, event in ipairs(decoded) do
    equal(event.sequence, index, ('log sequence %d is monotonic'):format(index))
end
local buffer_event = decoded[2]
equal(buffer_event and buffer_event.trigger, 'TextChangedI', 'structured fields retain the triggering editor event')
equal(buffer_event and buffer_event.file, 'sample.c', 'structured fields retain the project-relative file')
equal(buffer_event and buffer_event.line, 7, 'structured fields retain the marker line')
equal(buffer_event and buffer_event.question_id, 'abc123', 'structured fields retain a privacy-safe question identifier')

local stat = vim.uv.fs_stat(path)
check(stat and bit.band(stat.mode, 511) == 384, 'event log permissions are 0600')

vim.fn.writefile({ string.rep('x', 2048) }, path)
logger.setup { path = path, max_bytes = 1024, session = 'rotated-session' }
logger.event('after_rotation', {})
logger.stop()
check(vim.uv.fs_stat(path .. '.1') ~= nil, 'oversized event log rotates to one backup')
local rotated_lines = vim.fn.readfile(path)
check(#rotated_lines >= 3, 'logging continues after rotation')
check(vim.json.decode(rotated_lines[1]).session == 'rotated-session', 'rotated log starts a new session')

local runtime_path = root .. '/runtime.jsonl'
logger.setup { path = runtime_path, max_bytes = 450, session = 'runtime-rotation' }
logger.event('before_runtime_rotation', { payload = string.rep('a', 220) })
logger.event('after_runtime_rotation', { payload = string.rep('b', 220) })
check(vim.uv.fs_stat(runtime_path .. '.1') ~= nil, 'event log rotates while Neovim remains running')
local runtime_lines = vim.fn.readfile(runtime_path)
local latest_runtime_event = runtime_lines[1] and vim.json.decode(runtime_lines[1])
equal(latest_runtime_event and latest_runtime_event.event, 'after_runtime_rotation', 'logging continues in the active file after runtime rotation')
logger.stop()

vim.fn.delete(root, 'rf')
if #failures > 0 then error(('C tutor log tests failed (%d/%d):\n- %s'):format(#failures, checks, table.concat(failures, '\n- '))) end
print(('C tutor log tests passed: %d checks'):format(checks))
