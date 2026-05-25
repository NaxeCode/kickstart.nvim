-- Haxe support is handled by native Neovim filetype detection, Tree-sitter,
-- and haxe-language-server configured in lua/plugins/lsp.lua.
-- The old vaxe plugin is intentionally disabled: it can invoke interactive Lime
-- target prompts in headless/editor startup paths and conflicts with LSP-first setup.
return {}
