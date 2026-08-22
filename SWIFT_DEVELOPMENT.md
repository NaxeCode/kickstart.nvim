# Swift and Apple Platform Development

This configuration supports Swift development on macOS for iOS, iPadOS, and watchOS projects. The implementation uses Neovim 0.12 native `vim.pack`; it does not use `lazy.nvim`.

## Language support

- SourceKit-LSP is launched with `xcrun sourcekit-lsp` and restricted to Swift buffers so it does not compete with `clangd` for C-family files.
- `DEVELOPER_DIR` defaults to `/Applications/Xcode.app/Contents/Developer` when Xcode is installed and no explicit toolchain was selected.
- SourceKit project discovery follows `nvim-lspconfig` and prefers `buildServer.json`, then Xcode workspaces/projects, Swift packages, and Git roots.
- TreeSitter provides Swift highlighting, indentation, folds, locals, and injections.
- Conform runs `swiftformat` for Swift buffers. The normal `<leader>f` mapping formats the current buffer, and format-on-save uses the same formatter.
- `nvim-lint` runs `swiftlint` on buffer entry, write, and insert leave.

## Diagnostics and build errors

SourceKit diagnostics use the shared wrapped diagnostic presentation:

- `gl` opens the complete diagnostic for the current line.
- `<leader>ae` lists Swift errors and warnings for the current buffer.
- Standard LSP navigation, rename, code actions, references, symbols, signature help, and inlay hints use the mappings configured in `lua/plugins/lsp.lua`.

Apple verification runs through Overseer. Swift/Xcode diagnostics in `file:line:column: severity: message` form are parsed into the quickfix list and attached to their source buffers. The task dock opens when verification starts, remains unfocused while work succeeds, and is focused on failures. Restarting a task clears its previous build diagnostics.

## Aura Gainz workflow

Aura Gainz keeps Apple sources under `apple/`:

- `apple/project.yml` is the source of truth for the generated Xcode project. Neovim must not edit project membership directly.
- `buildServer.json` connects SourceKit-LSP to the `AuraGainz` scheme through `xcode-build-server`.
- `bin/apple-verify` is the source of truth for build and test orchestration.

Apple mappings use the `<leader>a` group:

| Mapping | Action |
| --- | --- |
| `<leader>aa` | Run `apple-verify auto` for targets inferred from changed files |
| `<leader>af` | Run Swift package tests and build the iOS/watchOS simulator app |
| `<leader>au` | Run core, simulator build, and iOS UI verification |
| `<leader>aw` | Run core and watchOS verification |
| `<leader>aF` | Run every core, iOS, UI, and watchOS profile |
| `<leader>as` | Stop running Apple verification tasks |
| `<leader>ad` | Toggle the Overseer build/test dock |
| `<leader>ae` | Show current-buffer Swift diagnostics |
| `<leader>ao` | Open `AuraGainz.xcodeproj` in Xcode |

Every verification mapping saves modified buffers before starting. If a save fails or the current buffer is outside Aura Gainz, no task starts and Neovim reports an actionable error.

## Tutor

Projects opt into the tutor by keeping `.tutor/state.json` at the repository root. Swift buffers then use the shared tutor mappings:

| Mapping | Action |
| --- | --- |
| `<leader>mt` | Toggle tutor coaching |
| `<leader>me` | Explain the current diagnostic |
| `<leader>mq` | Answer the question in the selected or latest tutor response |
| `<leader>mm` | Request one deeper explanation or hint |
| `<leader>mu` | Reroll the response without using its cache entry |
| `<leader>mx` | Cancel active work or dismiss a non-marker response |

Language support is declared once in `lua/custom/tutor_languages.lua`. Each profile supplies its filetypes, extensions, Tree-sitter parser, protocol metadata, and concept namespace; tutor eligibility, prompts, rendering, autocmds, and parser installation derive from that registry.

## Required tools

The managed macOS dotfiles install:

- Xcode command-line tools selected through `DEVELOPER_DIR`
- `xcode-build-server`
- `swiftformat`
- `swiftlint`
- `xcbeautify`
- `xcp`
- `coreutils`
- `pipx` and `pymobiledevice3`

`rg`, `fd`, `jq`, and the standard Neovim development tools are installed by the same dotfiles bootstrap.

## Verification

From the Aura Gainz root:

```bash
./bin/apple-verify fast
```

Inside Neovim, verify the Swift toolchain with:

```vim
:checkhealth vim.lsp nvim-treesitter conform vim.pack
:LspInfo
:ConformInfo
```

Expected SourceKit properties:

```text
command: xcrun sourcekit-lsp
filetype: swift
root: <repo>/aura-gainz
```

## Troubleshooting

- If `xcodebuild` reports that the active developer directory is CommandLineTools, confirm `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` in the launching shell.
- If SourceKit cannot resolve Xcode targets, regenerate `buildServer.json` with the repository's existing `xcode-build-server` workflow and reopen Neovim from the repository root.
- If highlighting is missing, ensure `swift` appears in the installed parsers reported by `:checkhealth nvim-treesitter`.
- If formatting or linting is unavailable, confirm `swiftformat` and `swiftlint` are on `PATH`.
- For project generation or scheme changes, update `apple/project.yml` and run the repository verifier; do not hand-edit generated project membership from Neovim.
