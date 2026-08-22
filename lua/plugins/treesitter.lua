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

local parser_set = {}
for _, parser in ipairs(parsers) do
    parser_set[parser] = true
end
for _, parser in ipairs(require('custom.tutor_languages').parsers()) do
    if not parser_set[parser] then parsers[#parsers + 1] = parser end
end

local M = {}

function M.register_haxe_parser()
    require('nvim-treesitter.parsers').haxe = {
        install_info = {
            url = 'https://github.com/vantreeseba/tree-sitter-haxe',
            branch = 'main',
            queries = 'queries',
        },
        filetype = 'haxe',
    }
end

function M.setup()
    M.register_haxe_parser()
    vim.api.nvim_create_autocmd('User', {
        pattern = 'TSUpdate',
        callback = M.register_haxe_parser,
    })

    -- nvim-treesitter no longer ships a separate jsonc parser ("skipping
    -- unsupported language: jsonc" on install). Highlight jsonc buffers with
    -- the json parser instead.
    vim.treesitter.language.register('json', { 'jsonc' })

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

                -- Haxe Tree-sitter highlighting works, but its indentation support is
                -- incomplete and makes <Enter> drop block indentation in `.hx` files.
                -- Use Vim's built-in C-like smart indent fallback for Haxe instead.
                if ft == 'haxe' then
                    vim.bo[ev.buf].indentexpr = ''
                    vim.bo[ev.buf].smartindent = true
                    return
                end

                -- Tree-sitter C indentation loses block depth while the file is
                -- temporarily incomplete during editing. Vim's C indenter is stable
                -- for partial code and handles Allman-style braces correctly.
                if ft == 'c' then
                    vim.bo[ev.buf].indentexpr = ''
                    vim.bo[ev.buf].cindent = true
                    return
                end

                -- Enable treesitter-aware indentation for buffers with reliable indent support.
                vim.bo[ev.buf].indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
            end
        end,
    })
end

return M
