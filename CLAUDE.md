# Claude Instructions: Neovim Configuration (Kickstart Fork)

This repository is a highly optimized, modular fork of `kickstart.nvim` tailored for a high-performance Arch Linux development environment (Ryzen 5900XT / Radeon 7900 XTX).

## Core Directives for AI Agents
- **Health Policy:** Treat all `:checkhealth` warnings as **Errors**. Fix them immediately.
- **Modernization:** This config targets **Neovim 0.11+**. Always prioritize native `vim.lsp` APIs over legacy `lspconfig` frameworks.
- **Theme:** The theme is **Everforest Dark Hard**, which MUST stay aligned with the Ghostty terminal configuration.

## Specialized Architecture
- `lua/config/`: System-wide settings (options, keymaps, autocmds).
- `lua/plugins/`: Individual plugin specifications managed by `lazy.nvim`.
- `lua/kickstart/`: Core logic inherited from the base repository.

## Critical Hacks & Silencing
- **LSP Deprecations:** In `lua/config/options.lua`, we aggressively intercept `vim.deprecate` to silence `require('lspconfig')` warnings caused by third-party plugins not yet updated for Neovim 0.11. **Do not remove this until plugins like tailwind-tools are updated.**
- **Language Providers:** Ruby and Perl providers are explicitly disabled (`vim.g.loaded_..._provider = 0`) to prevent health check noise.
- **Tailwind CSS:** Filetypes are strictly filtered in `lua/plugins/lsp.lua` to silence "Unknown filetype" warnings.

## Supported Tech Stack
- **NuShell:** Native integration using system binary (`nu --lsp`). Do NOT attempt to install via Mason.
  - **LSP:** Manually configured in `lua/plugins/lsp.lua` using `lspconfig` to ensure compatibility with system binary.
  - **Highlighting:** Handled by TreeSitter. Requires manual parser installation via `:TSUpdate nu`.
- **.NET/C#:** Full solution support via `roslyn.nvim` and `csharp.nvim`.
- **Rust:** Full `rust-analyzer` integration.
- **Node.js:** Managed by `fnm` (Fast Node Manager).
- **Yazi:** Primary file explorer. `Neo-tree` has been permanently removed.

## Maintenance Protocol
1. After any package removal, run `MasonUpdate` and clean registries.
2. If `blink.cmp` fuzzy search fails, manually trigger `cargo build --release` in the plugin directory.
3. **NuShell Setup:** If highlighting is missing in `.nu` files, run `:TSUpdate nu`. Verify LSP attachment with `:LspInfo`.
4. **Health Checks:** Always run `:checkhealth` after updating configurations. Treat all LSP and TreeSitter warnings as errors.
5. Always sync changes back to `NaxeCode/kickstart.nvim`.
