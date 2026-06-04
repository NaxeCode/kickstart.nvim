local parsers = {
  'bash',
  'c',
  'c_sharp',
  'css',
  'diff',
  'dockerfile',
  'haxe',
  'html',
  'javascript',
  'json',
  'jsonc',
  'lua',
  'luadoc',
  'markdown',
  'markdown_inline',
  'nu',
  'odin',
  'query',
  'toml',
  'tsx',
  'typescript',
  'vim',
  'vimdoc',
  'yaml',
}

return {
  'nvim-treesitter/nvim-treesitter',
  build = ':TSUpdate',
  lazy = false,
  config = function()
    local function register_haxe_parser()
      -- Haxe is not bundled by nvim-treesitter yet. Register external parser
      -- before setup/install so `.hx` files get Tree-sitter highlighting.
      require('nvim-treesitter.parsers').haxe = {
        install_info = {
          url = 'https://github.com/vantreeseba/tree-sitter-haxe',
          branch = 'main',
          queries = 'queries',
        },
        filetype = 'haxe',
      }
    end

    register_haxe_parser()
    vim.api.nvim_create_autocmd('User', {
      pattern = 'TSUpdate',
      callback = register_haxe_parser,
    })

    -- New nvim-treesitter API: setup() only accepts install_dir.
    -- Highlighting is handled natively by Neovim for installed parsers.
    require('nvim-treesitter').setup()

    -- Install any missing parsers on startup
    vim.api.nvim_create_autocmd('VimEnter', {
      once = true,
      callback = function()
        local installed = require('nvim-treesitter.config').get_installed 'parsers'
        local installed_set = {}
        for _, p in ipairs(installed) do
          installed_set[p] = true
        end
        local missing = vim.tbl_filter(function(p) return not installed_set[p] end, parsers)
        if #missing > 0 then require('nvim-treesitter.install').install(missing, { summary = true }) end
      end,
    })

    -- The new nvim-treesitter no longer sets up highlight autocmds.
    -- Explicitly start treesitter highlighting for every buffer whose
    -- filetype has an installed parser.
    vim.api.nvim_create_autocmd('FileType', {
      callback = function(ev)
        local ft = vim.bo[ev.buf].filetype
        if ft == '' then return end
        local ok, lang = pcall(vim.treesitter.language.get_lang, ft)
        if ok and lang then
          pcall(vim.treesitter.start, ev.buf, lang)
          -- Enable treesitter-aware indentation for this buffer
          vim.bo[ev.buf].indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
        end
      end,
    })
  end,
}
