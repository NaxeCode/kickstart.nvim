vim.api.nvim_create_autocmd('FileType', {
  pattern = 'cs',
  callback = function()
    -- Set up .NET specific settings for C# files
    local function find_dotnet_project()
      local cwd = vim.fn.getcwd()
      
      -- Check for solution file first
      local sln_files = vim.fn.glob(cwd .. '/*.sln', false, true)
      if #sln_files > 0 then
        return sln_files[1]
      end
      
      -- Check for project file
      local csproj_files = vim.fn.glob(cwd .. '/*.csproj', false, true)
      if #csproj_files > 0 then
        return csproj_files[1]
      end
      
      -- Fallback to simple dotnet build
      return nil
    end
    
    -- Set makeprg for .NET projects
    local project_file = find_dotnet_project()
    if project_file then
      vim.api.nvim_buf_set_option(0, 'makeprg', 'dotnet build ' .. project_file)
    else
      vim.api.nvim_buf_set_option(0, 'makeprg', 'dotnet build')
    end
    
    -- Set errorformat for .NET errors
    vim.api.nvim_buf_set_option(0, 'errorformat', '%f(%l\\,%c): error %m,%f(%l\\,%c): warning %m,%f:%l:%c: %trror %m,%f:%l:%c: %tarning %m')
  end,
})

-- Check if dotnet is installed
local function check_dotnet()
  local dotnet_available = vim.fn.executable('dotnet') == 1
  if not dotnet_available then
    print("dotnet not found. Installing .NET SDK...")
    -- This would normally be done manually, but we can at least warn the user
    print("Please install .NET SDK manually with: sudo apt-get install -y dotnet-sdk-8.0")
    return false
  else
    local success, result = pcall(vim.fn.system, 'dotnet --info')
    if success then
      print("dotnet installed:")
      print(result)
    end
    return true
  end
end

-- Run check on startup
check_dotnet()
