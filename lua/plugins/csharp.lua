return {
  -- Add custom mason registry that contains the Roslyn language server
  {
    'mason-org/mason.nvim',
    opts = function(_, opts)
      opts.registries = {
        'github:mason-org/mason-registry',
        'github:Crashdummyy/mason-registry',
      }
    end,
  },

  -- Roslyn language server — same backend as VS Code C# DevKit
  -- Install with :MasonInstall roslyn
  {
    'seblyng/roslyn.nvim',
    ft = 'cs',
    dependencies = {
      'mason-org/mason.nvim',
      'saghen/blink.cmp',
    },
    config = function()
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
            ['csharp|code_lens'] = {
              dotnet_enable_references_code_lens = true,
            },
          },
        },
      }
    end,
  },

  -- Auto-install csharpier (formatter) and netcoredbg (debugger)
  {
    'WhoIsSethDaniel/mason-tool-installer.nvim',
    optional = true,
    opts = function(_, opts)
      opts.ensure_installed = opts.ensure_installed or {}
      vim.list_extend(opts.ensure_installed, { 'csharpier', 'netcoredbg' })
    end,
  },

  -- CSharpier formatter (opinionated, like Prettier for C#)
  {
    'stevearc/conform.nvim',
    optional = true,
    opts = function(_, opts)
      opts.formatters_by_ft = opts.formatters_by_ft or {}
      opts.formatters_by_ft.cs = { 'csharpier' }
    end,
  },

  -- netcoredbg debugger — use existing DAP keymaps (<F5>, <F1>-<F3>, <leader>b)
  {
    'mfussenegger/nvim-dap',
    optional = true,
    config = function()
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
          program = function()
            return vim.fn.input('Path to dll: ', vim.fn.getcwd() .. '/bin/Debug/', 'file')
          end,
        },
      }
    end,
  },
}
