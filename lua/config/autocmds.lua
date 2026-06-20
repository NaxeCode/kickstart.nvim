-- Global theme switcher — called directly via socket from switch-theme.sh.
-- Naxeforest is dark-only; keep the old function name for script compatibility.
_G.switch_everforest_theme = function(_theme)
  vim.o.background = 'dark'
  vim.cmd.colorscheme 'everforest'
  vim.schedule(function()
    pcall(function() require('lualine').setup() end)
  end)
end

-- Live theme refresh: re-apply Naxeforest when the dark theme state is touched.
local _theme_file = vim.fn.expand '~/.config/theme'
local _last_theme_mtime = nil
vim.api.nvim_create_autocmd('FocusGained', {
  callback = function()
    local stat = vim.uv.fs_stat(_theme_file)
    if not stat or stat.mtime.sec == _last_theme_mtime then return end
    _last_theme_mtime = stat.mtime.sec
    _G.switch_everforest_theme('dark')
  end,
})

vim.api.nvim_create_autocmd('FileType', {
  pattern = 'cs',
  callback = function()
    local function find_dotnet_project()
      local cwd = vim.fn.getcwd()

      local sln_files = vim.fn.glob(cwd .. '/*.sln', false, true)
      if #sln_files > 0 then
        return sln_files[1]
      end

      local csproj_files = vim.fn.glob(cwd .. '/*.csproj', false, true)
      if #csproj_files > 0 then
        return csproj_files[1]
      end

      return nil
    end

    local project_file = find_dotnet_project()
    if project_file then
      vim.bo.makeprg = 'dotnet build ' .. project_file
    else
      vim.bo.makeprg = 'dotnet build'
    end

    vim.bo.errorformat = '%f(%l\\,%c): error %m,%f(%l\\,%c): warning %m,%f:%l:%c: %terror %m,%f:%l:%c: %twarning %m'
  end,
})
