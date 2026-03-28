return {
  'sainnhe/everforest',
  lazy = false,
  priority = 1000,
  config = function()
    vim.g.everforest_background = 'medium'
    vim.g.everforest_better_performance = 1

    -- Read theme state file set by switch-theme.sh
    local state_file = vim.fn.expand '~/.config/theme'
    local f = io.open(state_file, 'r')
    if f then
      local theme = f:read '*l'
      f:close()
      vim.o.background = (theme == 'light') and 'light' or 'dark'
    end

    vim.cmd.colorscheme 'everforest'
  end,
}
