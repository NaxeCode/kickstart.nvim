local indent_width = require('config.style').indent_width

return {
    {
        'folke/lazydev.nvim',
        ft = 'lua',
        opts = {
            library = {
                { path = '${3rd}/luv/library', words = { 'vim%.uv' } },
            },
        },
    },
    {
        'neovim/nvim-lspconfig',
        version = 'v2.*',
        dependencies = {
            { 'mason-org/mason.nvim', opts = {} },
            'mason-org/mason-lspconfig.nvim',
            'WhoIsSethDaniel/mason-tool-installer.nvim',
            { 'j-hui/fidget.nvim', opts = {} },
            'saghen/blink.cmp',
        },
        config = function()
            -- Diagnostic configuration
            local function format_wrapped_diagnostic(diagnostic)
                local message = diagnostic.source and (diagnostic.source .. ': ' .. diagnostic.message) or diagnostic.message
                local available_width = math.max(20, math.min(80, vim.api.nvim_win_get_width(0) - diagnostic.col - 10))
                local lines = {}

                for paragraph in message:gmatch '[^\n]+' do
                    local line = ''

                    for word in paragraph:gmatch '%S+' do
                        local candidate = line == '' and word or (line .. ' ' .. word)

                        if line ~= '' and vim.fn.strdisplaywidth(candidate) > available_width then
                            lines[#lines + 1] = line
                            line = word
                        else
                            line = candidate
                        end
                    end

                    if line ~= '' then lines[#lines + 1] = line end
                end

                return table.concat(lines, '\n')
            end

            vim.diagnostic.config {
                severity_sort = true,
                float = { border = 'rounded', source = 'if_many' },
                underline = { severity = vim.diagnostic.severity.ERROR },
                signs = vim.g.have_nerd_font and {
                    text = {
                        [vim.diagnostic.severity.ERROR] = '󰅚 ',
                        [vim.diagnostic.severity.WARN] = '󰀪 ',
                        [vim.diagnostic.severity.INFO] = '󰌶 ',
                        [vim.diagnostic.severity.HINT] = '󰌵 ',
                    },
                } or {},
                virtual_text = false,
                virtual_lines = {
                    current_line = true,
                    format = format_wrapped_diagnostic,
                },
            }

            vim.api.nvim_create_autocmd({ 'BufWinEnter', 'WinResized' }, {
                group = vim.api.nvim_create_augroup('kickstart-diagnostic-wrap', { clear = true }),
                callback = function()
                    local bufnr = vim.api.nvim_get_current_buf()
                    if vim.api.nvim_buf_is_loaded(bufnr) then vim.diagnostic.show(nil, bufnr) end
                end,
            })

            -- Set up keymaps on LspAttach
            vim.api.nvim_create_autocmd('LspAttach', {
                group = vim.api.nvim_create_augroup('kickstart-lsp-attach', { clear = true }),
                callback = function(event)
                    local map = function(keys, func, desc, mode)
                        mode = mode or 'n'
                        vim.keymap.set(mode, keys, func, { buffer = event.buf, desc = 'LSP: ' .. desc })
                    end

                    map('grn', vim.lsp.buf.rename, '[R]e[n]ame')
                    map('gra', vim.lsp.buf.code_action, '[G]oto Code [A]ction', { 'n', 'x' })
                    map('K', vim.lsp.buf.hover, 'Hover Documentation')
                    map('<C-k>', vim.lsp.buf.signature_help, 'Signature Help', { 'n', 'i' })
                    map('grr', require('telescope.builtin').lsp_references, '[G]oto [R]eferences')
                    map('gri', require('telescope.builtin').lsp_implementations, '[G]oto [I]mplementation')
                    map('grd', require('telescope.builtin').lsp_definitions, '[G]oto [D]efinition')
                    map('grD', vim.lsp.buf.declaration, '[G]oto [D]eclaration')
                    map('gO', require('telescope.builtin').lsp_document_symbols, 'Open Document Symbols')
                    map('gW', require('telescope.builtin').lsp_dynamic_workspace_symbols, 'Open Workspace Symbols')
                    map('grt', require('telescope.builtin').lsp_type_definitions, '[G]oto [T]ype Definition')

                    local client = vim.lsp.get_client_by_id(event.data.client_id)
                    if client and client:supports_method('textDocument/documentHighlight', event.buf) then
                        local highlight_augroup = vim.api.nvim_create_augroup('kickstart-lsp-highlight', { clear = false })
                        vim.api.nvim_create_autocmd({ 'CursorHold', 'CursorHoldI' }, {
                            buffer = event.buf,
                            group = highlight_augroup,
                            callback = vim.lsp.buf.document_highlight,
                        })

                        vim.api.nvim_create_autocmd({ 'CursorMoved', 'CursorMovedI' }, {
                            buffer = event.buf,
                            group = highlight_augroup,
                            callback = vim.lsp.buf.clear_references,
                        })

                        vim.api.nvim_create_autocmd('LspDetach', {
                            group = vim.api.nvim_create_augroup('kickstart-lsp-detach', { clear = true }),
                            callback = function(event2)
                                vim.lsp.buf.clear_references()
                                vim.api.nvim_clear_autocmds { group = 'kickstart-lsp-highlight', buffer = event2.buf }
                            end,
                        })
                    end

                    if client and client:supports_method('textDocument/inlayHint', event.buf) then
                        map(
                            '<leader>th',
                            function() vim.lsp.inlay_hint.enable(not vim.lsp.inlay_hint.is_enabled { bufnr = event.buf }) end,
                            '[T]oggle Inlay [H]ints'
                        )
                    end
                end,
            })

            -- Modern LSP Configuration (Neovim 0.11+)
            local capabilities = require('blink.cmp').get_lsp_capabilities()

            local servers = {
                -- Odin Language Server (install with `sudo pacman -S ols` or let Mason install it)
                ols = {},
                -- C/C++ (raylib projects). Uses system clangd at /usr/bin/clangd.
                -- clangd finds include paths via compile_commands.json or compile_flags.txt
                -- at the project root; see the C/raylib Overseer tasks in lua/plugins/c.lua.
                clangd = {
                    cmd = {
                        'clangd',
                        '--background-index',
                        '--clang-tidy',
                        '--header-insertion=never',
                        '--completion-style=detailed',
                        '--function-arg-placeholders=true',
                    },
                    filetypes = { 'c', 'cpp', 'objc', 'objcpp' },
                    root_markers = { 'compile_commands.json', 'compile_flags.txt', 'Makefile', '.git' },
                },
                ts_ls = {},
                eslint = {},
                html = {},
                cssls = {},
                jsonls = {
                    settings = {
                        json = {
                            schemas = require('schemastore').json.schemas(),
                            validate = { enable = true },
                        },
                    },
                },
                tailwindcss = {
                    filetypes = { 'html', 'css', 'scss', 'javascript', 'javascriptreact', 'typescript', 'typescriptreact', 'vue', 'svelte' },
                    settings = {
                        tailwindCSS = {
                            includeLanguages = {
                                typescript = 'javascript',
                                typescriptreact = 'javascriptreact',
                            },
                        },
                    },
                },
                nushell = {
                    cmd = { 'nu', '--lsp' },
                    filetypes = { 'nu' },
                    root_dir = function() return vim.fs.root(0, { '.git' }) or vim.uv.cwd() end,
                },
                lua_ls = {
                    settings = {
                        Lua = {
                            completion = { callSnippet = 'Replace' },
                        },
                    },
                },
            }

            -- Configure Mason and use the modern API for each server
            require('mason-lspconfig').setup {
                -- nushell and clangd are provided by the system, not Mason.
                ensure_installed = vim.tbl_filter(function(name) return name ~= 'nushell' and name ~= 'clangd' end, vim.tbl_keys(servers)),
                handlers = {
                    function(server_name)
                        local config = servers[server_name] or {}
                        config.capabilities = vim.tbl_deep_extend('force', {}, capabilities, config.capabilities or {})

                        -- Use the new native config API if available, fallback to old for stability
                        if vim.lsp.config then
                            vim.lsp.config(server_name, config)
                            vim.lsp.enable(server_name)
                        else
                            require('lspconfig')[server_name].setup(config)
                        end
                    end,
                },
            }

            -- Manually setup nushell since it's not in Mason (as per GEMINI.md)
            local nushell_config = servers.nushell or {}
            nushell_config.capabilities = vim.tbl_deep_extend('force', {}, capabilities, nushell_config.capabilities or {})
            require('lspconfig').nushell.setup(nushell_config)

            -- Manually setup clangd against the system binary (/usr/bin/clangd) rather
            -- than letting Mason install a second copy.
            if vim.fn.executable 'clangd' == 1 then
                local clangd_config = servers.clangd or {}
                clangd_config.capabilities = vim.tbl_deep_extend('force', {}, capabilities, clangd_config.capabilities or {})
                if vim.lsp.config then
                    vim.lsp.config('clangd', clangd_config)
                    vim.lsp.enable 'clangd'
                else
                    require('lspconfig').clangd.setup(clangd_config)
                end
            else
                vim.notify('clangd not found: install with `sudo pacman -S clang`', vim.log.levels.WARN)
            end

            local function find_haxe_root(fname)
                return vim.fs.root(fname, function(name) return name:match '%.hxml$' ~= nil end)
                    or vim.fs.root(fname, { 'Project.xml', 'project.xml', 'haxelib.json', '.git' })
            end

            local function find_haxe_display_args(root)
                if not root then return { 'build.hxml' } end
                local preferred = {
                    'display.hxml',
                    'display-hl.hxml',
                    'build.hxml',
                    'compile.hxml',
                    'test_hl.hxml',
                    'test.hxml',
                }
                for _, name in ipairs(preferred) do
                    if vim.uv.fs_stat(root .. '/' .. name) then return { name } end
                end
                local hxml = vim.fs.find(function(name) return name:match '%.hxml$' ~= nil end, { path = root, limit = 1 })[1]
                return hxml and { vim.fs.basename(hxml) } or { 'build.hxml' }
            end

            local haxe_language_server = vim.fn.exepath 'haxe-language-server'
            local haxe_config = {
                cmd = { haxe_language_server },
                filetypes = { 'haxe' },
                capabilities = capabilities,
                root_dir = function(bufnr, on_dir)
                    local fname = vim.api.nvim_buf_get_name(bufnr)
                    local root = find_haxe_root(fname)
                    if root then on_dir(root) end
                end,
                before_init = function(params, config)
                    config.init_options = config.init_options or {}
                    config.init_options.displayArguments = find_haxe_display_args(config.root_dir)
                    params.initializationOptions = config.init_options
                end,
                settings = {
                    haxe = {
                        executable = 'haxe',
                    },
                },
            }

            if haxe_language_server ~= '' then
                if vim.lsp.config then
                    vim.lsp.config('haxe_language_server', haxe_config)
                    vim.lsp.enable 'haxe_language_server'
                else
                    require('lspconfig').haxe_language_server.setup(haxe_config)
                end
            else
                vim.notify('haxe-language-server not found: ' .. haxe_language_server, vim.log.levels.WARN)
            end

            -- Install non-LSP tools
            require('mason-tool-installer').setup {
                ensure_installed = { 'stylua', 'prettier', 'markdownlint-cli2' },
            }
        end,
    },
    {
        'stevearc/conform.nvim',
        event = { 'BufWritePre' },
        cmd = { 'ConformInfo' },
        keys = {
            {
                '<leader>f',
                function() require('conform').format { async = true, lsp_format = 'fallback' } end,
                mode = '',
                desc = '[F]ormat buffer',
            },
        },
        opts = {
            notify_on_error = false,
            format_on_save = function(bufnr)
                local disable_filetypes = { c = true, cpp = true }
                if disable_filetypes[vim.bo[bufnr].filetype] then return nil end
                return {
                    timeout_ms = 500,
                    lsp_format = 'fallback',
                }
            end,
            formatters = {
                prettier = {
                    prepend_args = { '--tab-width', tostring(indent_width) },
                },
                stylua = {
                    prepend_args = { '--indent-width', tostring(indent_width) },
                },
            },
            formatters_by_ft = {
                lua = { 'stylua' },
                javascript = { 'prettier' },
                javascriptreact = { 'prettier' },
                typescript = { 'prettier' },
                typescriptreact = { 'prettier' },
                json = { 'prettier' },
                jsonc = { 'prettier' },
                yaml = { 'prettier' },
                markdown = { 'prettier' },
                html = { 'prettier' },
                css = { 'prettier' },
            },
        },
    },
    {
        'saghen/blink.cmp',
        event = 'VimEnter',
        version = '1.*',
        build = 'cargo build --release',
        dependencies = {
            {
                'L3MON4D3/LuaSnip',
                version = '2.*',
                build = (function()
                    if vim.fn.has 'win32' == 1 or vim.fn.executable 'make' == 0 then return end
                    return 'make install_jsregexp'
                end)(),
                opts = {},
            },
            'folke/lazydev.nvim',
        },
        opts = {
            keymap = {
                preset = 'super-tab',
                ['<CR>'] = {
                    function(cmp)
                        if cmp.snippet_active() then
                            return cmp.accept()
                        else
                            return cmp.select_and_accept()
                        end
                    end,
                    'snippet_forward',
                    'fallback',
                },
            },
            appearance = { nerd_font_variant = 'mono' },
            completion = {
                documentation = { auto_show = false, auto_show_delay_ms = 500 },
            },
            sources = {
                default = { 'lsp', 'path', 'snippets', 'lazydev' },
                providers = {
                    lazydev = { module = 'lazydev.integrations.blink', score_offset = 100 },
                },
            },
            snippets = { preset = 'luasnip' },
            fuzzy = { implementation = 'lua' },
            signature = { enabled = true },
        },
    },
    {
        'pmizio/typescript-tools.nvim',
        ft = { 'javascript', 'javascriptreact', 'typescript', 'typescriptreact', 'vue' },
        dependencies = 'nvim-lua/plenary.nvim',
        opts = {
            settings = {
                tsserver_file_preferences = {
                    includeCompletionsForModuleExports = true,
                    includeInlayParameterNameHints = 'all',
                },
            },
        },
    },
    { 'b0o/schemastore.nvim', lazy = true },
}
