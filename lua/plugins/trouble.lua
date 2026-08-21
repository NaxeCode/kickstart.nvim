return {
  'folke/trouble.nvim',
  dependencies = { 'nvim-tree/nvim-web-devicons' },
  keys = {
    { '<leader>xx', '<cmd>Trouble diagnostics toggle focus=true<cr>', desc = 'Problems (Trouble)' },
    {
      '<leader>xX',
      '<cmd>Trouble diagnostics toggle filter.buf=0 focus=true<cr>',
      desc = 'Buffer problems (Trouble)',
    },
    { '<leader>xq', '<cmd>Trouble qflist toggle focus=true<cr>', desc = 'Compiler quickfix (Trouble)' },
  },
  opts = {
    auto_close = true,
    auto_preview = true,
    multiline = true,
  },
}
