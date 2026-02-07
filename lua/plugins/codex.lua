return {
  'rhart92/codex.nvim',
  opts = {
    split = 'float',
    focus_after_send = true,
    autostart = false,
    log_level = 'warn',
  },
  keys = {
    { '<leader>ca', function() require('codex').toggle() end, mode = 'n', desc = '[C]odex [A]sk (toggle)' },
    { '<leader>ca', function() require('codex').actions.send_selection() end, mode = 'x', desc = '[C]odex [A]sk selection' },
    { '<leader>cb', function() require('codex').actions.send_buffer() end, mode = 'n', desc = '[C]odex send [B]uffer' },
  },
}
