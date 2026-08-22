local M = {}

function M.setup()
    require('roslyn').setup {
        config = {
            capabilities = require('blink.cmp').get_lsp_capabilities(),
            settings = {
                ['csharp|inlay_hints'] = {
                    csharp_enable_inlay_hints_for_implicit_object_creation = true,
                    csharp_enable_inlay_hints_for_implicit_variable_types = true,
                    csharp_enable_inlay_hints_for_lambda_parameter_types = true,
                    csharp_enable_inlay_hints_for_types = true,
                    dotnet_enable_inlay_hints_for_indexer_parameters = true,
                    dotnet_enable_inlay_hints_for_literal_parameters = true,
                    dotnet_enable_inlay_hints_for_object_creation_parameters = true,
                    dotnet_enable_inlay_hints_for_other_parameters = true,
                    dotnet_enable_inlay_hints_for_parameters = true,
                    dotnet_suppress_inlay_hints_for_parameters_that_match_argument_name = true,
                    dotnet_suppress_inlay_hints_for_parameters_that_match_method_intent = true,
                },
                ['csharp|background_analysis'] = {
                    dotnet_analyzer_diagnostics_scope = 'fullSolution',
                    dotnet_compiler_diagnostics_scope = 'fullSolution',
                },
                ['csharp|code_lens'] = { dotnet_enable_references_code_lens = true },
            },
        },
    }

    local dap = require 'dap'
    dap.adapters.coreclr = {
        type = 'executable',
        command = vim.fn.exepath 'netcoredbg',
        args = { '--interpreter=vscode' },
    }
    dap.configurations.cs = {
        {
            type = 'coreclr',
            name = 'Launch',
            request = 'launch',
            program = function() return vim.fn.input('Path to dll: ', vim.fn.getcwd() .. '/bin/Debug/', 'file') end,
        },
    }
end

return M
