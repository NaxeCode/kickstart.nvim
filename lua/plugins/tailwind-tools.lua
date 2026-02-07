return {
  'luckasRanarison/tailwind-tools.nvim',
  name = 'tailwind-tools',
  event = 'BufReadPre',
  dependencies = {
    'nvim-treesitter/nvim-treesitter',
    'neovim/nvim-lspconfig',
  },
  opts = {
    document_color = {
      enabled = true,
    },
  },
}
