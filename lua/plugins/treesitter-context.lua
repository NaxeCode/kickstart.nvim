local M = {}

function M.setup() require('treesitter-context').setup { max_lines = 3, trim_scope = 'outer' } end

return M
