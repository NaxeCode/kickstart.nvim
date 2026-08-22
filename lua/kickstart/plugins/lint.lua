local M = {}

function M.setup()
    local lint = require 'lint'
    lint.linters_by_ft = { markdown = { 'markdownlint-cli2' } }
    if vim.fn.has 'macunix' == 1 and vim.fn.executable 'swiftlint' == 1 then lint.linters_by_ft.swift = { 'swiftlint' } end
    local group = vim.api.nvim_create_augroup('lint', { clear = true })
    vim.api.nvim_create_autocmd({ 'BufEnter', 'BufWritePost', 'InsertLeave' }, {
        group = group,
        callback = function()
            if vim.bo.modifiable then lint.try_lint() end
        end,
    })
end

return M
