local failures = {}
local checks = 0

local function check(condition, message)
    checks = checks + 1
    if not condition then failures[#failures + 1] = message end
end

local tasks = require 'custom.swift_tasks'
local root = vim.fn.tempname()
vim.fn.mkdir(root .. '/apple', 'p')
vim.fn.writefile({ '{}' }, root .. '/buildServer.json')
root = vim.uv.fs_realpath(root) or root
local source = root .. '/apple/WorkoutView.swift'
vim.fn.writefile({ 'struct WorkoutView {}' }, source)
vim.cmd('edit ' .. vim.fn.fnameescape(source))

check(tasks.root() == root, 'Swift task root resolves buildServer.json projects')
check(vim.tbl_count(tasks._test.profiles) == 5, 'all five Apple verification profiles are registered')

local parsed = vim.fn.getqflist {
    lines = {
        source .. ":7:11: error: value of type 'Workout' has no member 'sets'",
        source .. ':9:5: warning: result of call is unused',
    },
    efm = tasks._test.errorformat,
}
local items = parsed.items or {}
check(#items == 2, 'Swift compiler output creates two quickfix diagnostics')
check(items[1] and items[1].lnum == 7 and items[1].col == 11, 'Swift error preserves line and column')
check(items[1] and items[1].type == 'E', 'Swift error is classified as an error')
check(items[1] and items[1].text:find("value of type 'Workout'", 1, true) ~= nil, 'Swift error keeps the actionable message')
check(items[2] and items[2].type == 'W', 'Swift warning is classified as a warning')

vim.cmd 'bwipeout!'
vim.fn.delete(root, 'rf')
if #failures > 0 then error(('Swift task tests failed (%d/%d):\n- %s'):format(#failures, checks, table.concat(failures, '\n- '))) end
print(('Swift task tests passed: %d checks'):format(checks))
