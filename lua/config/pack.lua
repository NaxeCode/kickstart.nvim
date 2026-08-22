local function run_build(name, command, cwd)
    local result = vim.system(command, { cwd = cwd }):wait()
    if result.code == 0 then return end

    local output = result.stderr ~= '' and result.stderr or result.stdout
    if not output or output == '' then output = 'No output from build command.' end
    vim.notify(('Build failed for %s:\n%s'):format(name, output), vim.log.levels.ERROR)
end

local function register_build_hooks()
    local group = vim.api.nvim_create_augroup('naxecode-pack-builds', { clear = true })
    vim.api.nvim_create_autocmd('PackChanged', {
        group = group,
        callback = function(event)
            local kind = event.data.kind
            if kind ~= 'install' and kind ~= 'update' then return end

            local name = event.data.spec.name
            if name == 'telescope-fzf-native.nvim' and vim.fn.executable 'make' == 1 then
                run_build(name, { 'make' }, event.data.path)
            elseif name == 'LuaSnip' and vim.fn.has 'win32' ~= 1 and vim.fn.executable 'make' == 1 then
                run_build(name, { 'make', 'install_jsregexp' }, event.data.path)
            elseif name == 'blink.cmp' and vim.fn.executable 'cargo' == 1 then
                run_build(name, { 'cargo', 'build', '--release' }, event.data.path)
            elseif name == 'nvim-treesitter' then
                if not event.data.active then vim.cmd.packadd 'nvim-treesitter' end
                require('plugins.treesitter').register_haxe_parser()
                vim.cmd 'TSUpdate'
            end
        end,
    })
end

register_build_hooks()

local function plugin_name(spec)
    if type(spec) == 'table' and spec.name then return spec.name end
    local src = type(spec) == 'table' and spec.src or spec
    return src:match '([^/]+)$'
end

local startup_specs = {}
local deferred_specs = {}
for _, spec in ipairs(require 'plugins.catalog') do
    local destination = plugin_name(spec) == 'everforest' and startup_specs or deferred_specs
    destination[#destination + 1] = spec
end

-- The colorscheme must be available while init.lua is sourced. Everything
-- else activates before the first file, or just after an empty editor starts.
vim.pack.add(startup_specs, { confirm = false })
require('plugins.everforest').setup()

local setup_modules = {
    'plugins.editor',
    'plugins.guess-indent',
    'plugins.gitsigns',
    'plugins.treesitter',
    'plugins.lsp',
    'plugins.swift',
    'plugins.tailwind-tools',
    'plugins.csharp',
    'plugins.tiny-inline-diagnostic',
    'plugins.markdown',
    'plugins.treesitter-context',
    'kickstart.plugins.autopairs',
    'kickstart.plugins.lint',
    'kickstart.plugins.debug',
    'plugins.telescope',
    'plugins.which-key',
    'plugins.todo-comments',
    'plugins.lualine',
    'plugins.bufferline',
    'plugins.trouble',
    'plugins.yazi',
    'plugins.overseer',
    'plugins.c',
    'plugins.tutor',
    'plugins.codex',
    'plugins.neocord',
    'plugins.wk-sensor',
}

local activated = false
local function activate()
    if activated then return end
    vim.pack.add(deferred_specs, { confirm = false, load = true })
    activated = true

    for _, module in ipairs(setup_modules) do
        local plugin = require(module)
        if type(plugin.setup) == 'function' then plugin.setup() end
    end
end

local group = vim.api.nvim_create_augroup('naxecode-pack-activate', { clear = true })
vim.api.nvim_create_autocmd({ 'BufReadPre', 'BufNewFile' }, {
    group = group,
    once = true,
    callback = activate,
})
vim.api.nvim_create_autocmd('VimEnter', {
    group = group,
    once = true,
    callback = function() vim.schedule(activate) end,
})
