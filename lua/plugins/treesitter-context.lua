return {
  'nvim-treesitter/nvim-treesitter-context',
  event = 'BufReadPre',
  opts = {
    max_lines = 3,
    trim_scope = 'outer',
  },
}
