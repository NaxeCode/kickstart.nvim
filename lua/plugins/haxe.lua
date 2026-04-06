return {
  'jdonaldson/vaxe',
  ft = { 'haxe', 'hxml' },
  init = function()
    -- Register filetypes early so lazy-loading triggers correctly
    vim.filetype.add {
      extension = {
        hx = 'haxe',
        hxml = 'hxml',
      },
    }
    -- Disable vaxe features we don't need (LSP, completion, builds)
    vim.g.vaxe_enable_completions = 0
    vim.g.vaxe_cache_server = 0
  end,
}
