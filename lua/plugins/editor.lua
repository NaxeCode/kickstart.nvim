return {
  {
    'numToStr/Comment.nvim',
    opts = {},
    keys = {
      { 'gcc', mode = 'n', desc = 'Comment line' },
      { 'gc', mode = { 'n', 'x' }, desc = 'Comment selection' },
    },
  },
  {
    'NvChad/nvim-colorizer.lua',
    event = 'BufReadPre',
    opts = {
      filetypes = { 'css', 'html', 'tsx', 'jsx' },
      user_default_options = {
        tailwind = true,
      },
    },
  },
  {
    'lukas-reineke/indent-blankline.nvim',
    main = 'ibl',
    event = 'BufReadPre',
    opts = {
      indent = { char = '|' },
      scope = { enabled = true },
    },
  },
  {
    'echasnovski/mini.nvim',
    config = function()
      require('mini.ai').setup { n_lines = 500 }
      require('mini.surround').setup()
      require('mini.pairs').setup()
    end,
  },
}
