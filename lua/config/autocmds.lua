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
