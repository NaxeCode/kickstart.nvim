return {
  'akinsho/bufferline.nvim',
  version = '*',
  dependencies = 'nvim-tree/nvim-web-devicons',
  event = 'VeryLazy',
  opts = {
    options = {
      diagnostics = 'nvim_lsp',
      separator_style = 'slant',
      offsets = {
        { filetype = 'neo-tree', text = 'Explorer', separator = true },
      },
    },
  },
}
