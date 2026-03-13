local check_version = function()
  local verstr = tostring(vim.version())
  if not vim.version.ge then
    vim.health.error(string.format("Neovim out of date: '%s'. Upgrade to latest stable or nightly", verstr))
    return
  end

  if vim.version.ge(vim.version(), '0.11') then
    vim.health.ok(string.format("Neovim version is: '%s'", verstr))
  else
    vim.health.warn(string.format("Neovim version is: '%s'. Upgrade to 0.11 or later", verstr))
  end
end

local check_external_reqs = function()
  -- Basic utils: `git`, `make`, `unzip`
  for _, exe in ipairs { 'git', 'make', 'unzip', 'rg' } do
    local is_executable = vim.fn.executable(exe) == 1
    if is_executable then
      vim.health.ok(string.format("Found executable: '%s'", exe))
    else
      vim.health.warn(string.format("Could not find executable: '%s'", exe))
    end
  end

  -- .NET SDK check
  local is_dotnet = vim.fn.executable('dotnet') == 1
  if is_dotnet then
    vim.health.ok("Found executable: 'dotnet'")
    local success, result = pcall(vim.fn.system, 'dotnet --info')
    if success then
      vim.health.info("dotnet info:")
      vim.health.info(result)
    end
  else
    vim.health.warn("Could not find executable: 'dotnet'")
    vim.health.info("Install .NET SDK with: sudo apt-get install -y dotnet-sdk-8.0")
  end
end

return {
  check = function()
    vim.health.start 'kickstart.nvim'

    vim.health.info [[NOTE: Not every warning is a 'must-fix' in `:checkhealth`

  Fix only warnings for plugins and languages you intend to use.
    Mason will give warnings for languages that are not installed.
    You do not need to install, unless you want to use those languages!]]

    local uv = vim.uv or vim.loop
    vim.health.info(string.format('Config file: %s', uv.fs_stat(vim.fn.expand '$MYVIMRC').path))

    check_version()
    check_external_reqs()

    -- Check for required plugins
    local lazy_loaded = require('lazy').plugins()
    if #lazy_loaded > 0 then
      vim.health.ok(string.format("Loaded %d plugins", #lazy_loaded))
    else
      vim.health.warn("No plugins loaded")
    end

    -- Check for colorscheme
    if vim.g.colors_name then
      vim.health.ok(string.format("Colorscheme: '%s'", vim.g.colors_name))
    else
      vim.health.warn("No colorscheme set")
    end
  end,
}
