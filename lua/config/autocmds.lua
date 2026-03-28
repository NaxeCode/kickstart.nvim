-- Global theme switcher — called directly via socket from switch-theme.sh
_G.switch_everforest_theme = function(bg)
  vim.o.background = bg
  vim.cmd.colorscheme 'everforest'
  vim.schedule(function()
    pcall(function() require('lualine').setup() end)
  end)
end

-- Live theme switching: re-read ~/.config/theme whenever Neovim regains focus
local _theme_file = vim.fn.expand '~/.config/theme'
local _last_bg = vim.o.background
vim.api.nvim_create_autocmd('FocusGained', {
  callback = function()
    local f = io.open(_theme_file, 'r')
    if not f then return end
    local theme = f:read '*l'
    f:close()
    local bg = (theme == 'light') and 'light' or 'dark'
    if bg ~= _last_bg then
      _last_bg = bg
      _G.switch_everforest_theme(bg)
    end
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
