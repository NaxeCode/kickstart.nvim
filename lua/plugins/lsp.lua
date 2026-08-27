local indent_width = require('config.style').indent_width

local M = {}

function M.setup()
    require('lazydev').setup {
        library = {
            { path = '${3rd}/luv/library', words = { 'vim%.uv' } },
        },
    }
    require('fidget').setup {}
    require('mason').setup {
        registries = {
            'github:mason-org/mason-registry',
            'github:Crashdummyy/mason-registry',
        },
    }

    do
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
            virtual_lines = function(_, bufnr)
                if vim.bo[bufnr].filetype == 'c' then return false end

                return {
                    current_line = true,
                    format = format_wrapped_diagnostic,
                }
            end,
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
                map(
                    'gl',
                    function()
                        vim.diagnostic.open_float {
                            scope = 'line',
                            source = 'always',
                            focusable = true,
                            border = 'rounded',
                        }
                    end,
                    'Line Diagnostic Details'
                )
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

        -- Configure project servers with Neovim's native LSP API. Mason installs
        -- and enables the managed servers, while dedicated clients own TypeScript.
        for server_name, config in pairs(servers) do
            if server_name ~= 'nushell' and server_name ~= 'clangd' then
                config.capabilities = vim.tbl_deep_extend('force', {}, capabilities, config.capabilities or {})
                vim.lsp.config(server_name, config)
            end
        end

        require('mason-lspconfig').setup {
            -- nushell and clangd are provided by the system, not Mason.
            ensure_installed = vim.tbl_filter(function(name) return name ~= 'nushell' and name ~= 'clangd' end, vim.tbl_keys(servers)),
            -- typescript-tools.nvim is the sole TypeScript language client.
            automatic_enable = { exclude = { 'ts_ls' } },
        }

        -- Use each JavaScript/TypeScript project's own Oxlint version for diagnostics
        -- and code actions. The nvim-lspconfig definition resolves node_modules/.bin/oxlint.
        vim.lsp.enable 'oxlint'

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

        -- SourceKit-LSP ships with Xcode. Keep it Swift-only so clangd remains
        -- the sole owner of C-family buffers.
        if vim.fn.has 'macunix' == 1 and vim.fn.executable 'xcrun' == 1 then
            local default_developer_dir = '/Applications/Xcode.app/Contents/Developer'
            if (not vim.env.DEVELOPER_DIR or vim.env.DEVELOPER_DIR == '') and vim.fn.isdirectory(default_developer_dir) == 1 then
                vim.env.DEVELOPER_DIR = default_developer_dir
            end

            vim.lsp.config('sourcekit', {
                cmd = { 'xcrun', 'sourcekit-lsp' },
                cmd_env = { DEVELOPER_DIR = vim.env.DEVELOPER_DIR },
                filetypes = { 'swift' },
                capabilities = vim.tbl_deep_extend('force', {}, capabilities),
            })
            vim.lsp.enable 'sourcekit'
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

        require('mason-tool-installer').setup {
            ensure_installed = {
                'stylua',
                'prettier',
                'markdownlint-cli2',
                'roslyn',
                'csharpier',
                'netcoredbg',
            },
        }
    end

    local prettier_filetypes = {
        javascript = true,
        javascriptreact = true,
        typescript = true,
        typescriptreact = true,
        json = true,
        jsonc = true,
        yaml = true,
        markdown = true,
        html = true,
        css = true,
    }
    local formatters_by_ft = {
        lua = { 'stylua' },
        cs = { 'csharpier' },
    }
    if vim.fn.has 'macunix' == 1 then formatters_by_ft.swift = { 'swiftformat' } end

    local function project_prettier(dirname) return vim.fs.find('node_modules/.bin/prettier', { path = dirname, upward = true, limit = 1 })[1] end

    local function buffer_dir(bufnr)
        local filename = vim.api.nvim_buf_get_name(bufnr)
        return filename ~= '' and vim.fs.dirname(filename) or vim.uv.cwd()
    end

    local function format_options(bufnr)
        local is_web = prettier_filetypes[vim.bo[bufnr].filetype]
        return {
            timeout_ms = 500,
            -- Web projects should use the formatter they declare, not a
            -- globally installed formatter or tsserver's different defaults.
            formatters = is_web and { 'prettier' } or nil,
            lsp_format = is_web and 'never' or 'fallback',
        }
    end

    local function has_configured_formatter(bufnr) return not prettier_filetypes[vim.bo[bufnr].filetype] or project_prettier(buffer_dir(bufnr)) ~= nil end

    require('conform').setup {
        notify_on_error = false,
        format_on_save = function(bufnr)
            local disable_filetypes = { c = true, cpp = true }
            if disable_filetypes[vim.bo[bufnr].filetype] or not has_configured_formatter(bufnr) then return nil end
            return format_options(bufnr)
        end,
        formatters = {
            prettier = {
                command = function(_, ctx) return project_prettier(ctx.dirname) or 'prettier' end,
                condition = function(_, ctx) return project_prettier(ctx.dirname) ~= nil end,
                prepend_args = { '--tab-width', tostring(indent_width) },
            },
            stylua = { prepend_args = { '--indent-width', tostring(indent_width) } },
        },
        formatters_by_ft = formatters_by_ft,
    }
    vim.keymap.set({ 'n', 'v' }, '<leader>f', function()
        local bufnr = vim.api.nvim_get_current_buf()
        if not has_configured_formatter(bufnr) then return end
        require('conform').format(vim.tbl_extend('force', format_options(bufnr), { bufnr = bufnr, async = true }))
    end, { desc = '[F]ormat buffer' })

    require('luasnip').setup {}
    require('blink.cmp').setup {
        keymap = {
            preset = 'super-tab',
            ['<CR>'] = {
                function(cmp)
                    if cmp.snippet_active() then return cmp.accept() end
                    return cmp.select_and_accept()
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
    }

    local typescript_filetypes = { 'javascript', 'javascriptreact', 'typescript', 'typescriptreact', 'vue' }
    local typescript_filetype_set = {}
    for _, filetype in ipairs(typescript_filetypes) do
        typescript_filetype_set[filetype] = true
    end

    local function start_typescript(dispatchers)
        local rpc = require 'typescript-tools.rpc'
        local util = require 'typescript-tools.utils'
        local function start() return rpc.start(dispatchers) end
        local function is_typescript_buffer(bufnr)
            return typescript_filetype_set[vim.bo[bufnr].filetype] and util.bufname_valid(vim.api.nvim_buf_get_name(bufnr))
        end

        local current = vim.api.nvim_get_current_buf()
        if is_typescript_buffer(current) then return start() end

        -- The plugin resolves tsserver from the current buffer rather than the
        -- buffer starting the client. Keep delayed launches tied to the project
        -- buffer when another window (for example, :checkhealth) has focus.
        for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
            if vim.api.nvim_buf_is_loaded(bufnr) and is_typescript_buffer(bufnr) then return vim.api.nvim_buf_call(bufnr, start) end
        end

        return start()
    end

    require('typescript-tools').setup {
        cmd = start_typescript,
        filetypes = typescript_filetypes,
        settings = {
            tsserver_file_preferences = {
                includeCompletionsForModuleExports = true,
                includeInlayParameterNameHints = 'all',
            },
        },
    }
end

return M
