-- lua/custom/plugins/csharp.lua
return {
  ------------------------------------------------------------
  -- 1) Extended OmniSharp LSP for richer go-to/resolve logic
  ------------------------------------------------------------
  {
    'Hoffs/omnisharp-extended-lsp.nvim',
    lazy = false,
    dependencies = {
      'neovim/nvim-lspconfig',
      'williamboman/mason.nvim',
      'williamboman/mason-lspconfig.nvim',
    },
    config = function()
      local lspconfig = require 'lspconfig'
      -- tell the extended plugin to hook into Omnisharp
      require('omnisharp_extended').setup()

      lspconfig.omnisharp.setup {
        cmd = {
          -- mason installs omnisharp under stdpath('data')/mason/packages/omnisharp
          vim.fn.stdpath 'data' .. '/mason/packages/omnisharp/omnisharp',
          '--languageserver',
          '--hostPID',
          tostring(vim.fn.getpid()),
        },
        enable_editorconfig_support = true,
        handlers = {
          -- use the extended go-to-definition (better resolution in many cases)
          ['textDocument/definition'] = require('omnisharp_extended').handler,
        },
      }
    end,
  },

  ------------------------------------------------------------
  -- 2) DAP + DAP-UI for .NET debugging via netcoredbg
  ------------------------------------------------------------
  {
    'mfussenegger/nvim-dap',
    dependencies = { 'rcarriga/nvim-dap-ui' },
    config = function()
      local dap = require 'dap'
      local dapui = require 'dapui'

      -- adapter for .NET Core
      dap.adapters.coreclr = {
        type = 'executable',
        command = 'netcoredbg', -- ensure this is on your PATH
        args = { '--interpreter=vscode' },
      }

      -- launch configuration
      dap.configurations.cs = {
        {
          type = 'coreclr',
          name = 'Launch .NET Core',
          request = 'launch',
          program = function()
            -- prompt for the path to your DLL
            return vim.fn.input('Path to dll: ', vim.fn.getcwd() .. '/bin/Debug/net6.0/' .. vim.fn.fnamemodify(vim.fn.getcwd(), ':t') .. '.dll', 'file')
          end,
        },
      }

      dapui.setup()

      -- keymaps
      vim.keymap.set('n', '<F5>', dap.continue, { desc = 'Debug: Continue' })
      vim.keymap.set('n', '<F10>', dap.step_over, { desc = 'Debug: Step over' })
      vim.keymap.set('n', '<F11>', dap.step_into, { desc = 'Debug: Step into' })
      vim.keymap.set('n', '<F12>', dap.step_out, { desc = 'Debug: Step out' })
      vim.keymap.set('n', '<leader>db', dap.toggle_breakpoint, { desc = 'Debug: Toggle breakpoint' })
      vim.keymap.set('n', '<leader>dr', dap.repl.open, { desc = 'Debug: Open REPL' })
      vim.keymap.set('n', '<leader>du', dapui.toggle, { desc = 'Debug: Toggle UI' })
    end,
  },

  ------------------------------------------------------------
  -- 3) neotest + neotest-dotnet for running C# tests
  ------------------------------------------------------------
  {
    'nvim-neotest/neotest',
    dependencies = {
      'nvim-lua/plenary.nvim',
      'nvim-treesitter/nvim-treesitter',
      'Issafalcon/neotest-dotnet', -- adapter for dotnet tests
    },
    config = function()
      require('neotest').setup {
        adapters = {
          require 'neotest-dotnet' {
            -- you can pass extra dotnet test args here if needed
            -- e.g. args = { "--no-build", "--logger:trx;LogFileName=test_results.trx" },
          },
        },
      }

      -- test keymaps
      vim.keymap.set('n', '<leader>tn', require('neotest').run.run, { desc = 'Test: nearest' })
      vim.keymap.set('n', '<leader>tf', function()
        require('neotest').run.run(vim.fn.expand '%')
      end, { desc = 'Test: file' })
      vim.keymap.set('n', '<leader>ts', require('neotest').summary.toggle, { desc = 'Test: summary' })
      vim.keymap.set('n', '<leader>to', require('neotest').output_panel.toggle, { desc = 'Test: output' })
    end,
  },
}
