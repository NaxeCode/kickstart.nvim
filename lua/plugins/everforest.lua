local naxeforest = {
  bg = '#1e2228',
  bg_dim = '#181c21',
  bg_dark = '#15191e',
  bg1 = '#252b33',
  bg2 = '#2d3440',
  bg3 = '#3b4450',
  bg4 = '#454e5c',
  bg5 = '#58636d',
  fg = '#d8d4bf',
  subtext1 = '#9da8ad',
  subtext0 = '#7f8c95',
  overlay2 = '#6f7b84',
  red = '#e68183',
  orange = '#ff9e64',
  yellow = '#e2bd6b',
  green = '#a9c97a',
  blue = '#7fa6c9',
  aqua = '#86c5d8',
  purple = '#d99ac2',
  none = 'NONE',
}

local function color(hex, cterm)
  return { hex, cterm or 'NONE' }
end

local function apply_terminal_colors()
  local ansi = {
    naxeforest.bg,
    naxeforest.red,
    naxeforest.green,
    naxeforest.orange,
    naxeforest.blue,
    naxeforest.purple,
    naxeforest.aqua,
    naxeforest.fg,
    naxeforest.subtext0,
    naxeforest.red,
    naxeforest.green,
    naxeforest.orange,
    naxeforest.blue,
    naxeforest.purple,
    naxeforest.aqua,
    naxeforest.fg,
  }
  for i, value in ipairs(ansi) do
    vim.g['terminal_color_' .. (i - 1)] = value
  end
end

local function apply_highlights()
  local hl = vim.api.nvim_set_hl

  hl(0, 'Normal', { fg = naxeforest.fg, bg = naxeforest.bg })
  hl(0, 'NormalNC', { fg = naxeforest.fg, bg = naxeforest.bg_dim })
  hl(0, 'SignColumn', { fg = naxeforest.fg, bg = naxeforest.bg })
  hl(0, 'EndOfBuffer', { fg = naxeforest.bg3, bg = naxeforest.bg })
  hl(0, 'Cursor', { fg = naxeforest.bg, bg = naxeforest.orange })
  hl(0, 'CursorLine', { bg = naxeforest.bg1 })
  hl(0, 'CursorLineNr', { fg = naxeforest.orange, bg = naxeforest.bg1, bold = true })
  hl(0, 'LineNr', { fg = naxeforest.overlay2, bg = naxeforest.bg })
  hl(0, 'Visual', { bg = naxeforest.bg3 })
  hl(0, 'Search', { fg = naxeforest.bg, bg = naxeforest.orange })
  hl(0, 'IncSearch', { fg = naxeforest.bg, bg = naxeforest.aqua })
  hl(0, 'Pmenu', { fg = naxeforest.fg, bg = naxeforest.bg1 })
  hl(0, 'PmenuSel', { fg = naxeforest.bg, bg = naxeforest.orange })
  hl(0, 'FloatBorder', { fg = naxeforest.blue, bg = naxeforest.bg1 })
  hl(0, 'NormalFloat', { fg = naxeforest.fg, bg = naxeforest.bg1 })
  hl(0, 'WinSeparator', { fg = naxeforest.bg3, bg = naxeforest.bg })

  hl(0, 'DiagnosticError', { fg = naxeforest.red })
  hl(0, 'DiagnosticWarn', { fg = naxeforest.orange })
  hl(0, 'DiagnosticInfo', { fg = naxeforest.blue })
  hl(0, 'DiagnosticHint', { fg = naxeforest.aqua })
  hl(0, 'DiffAdd', { bg = '#263544' })
  hl(0, 'DiffChange', { bg = naxeforest.bg2 })
  hl(0, 'DiffDelete', { bg = '#443136' })
  hl(0, 'DiffText', { bg = '#453224' })

  hl(0, '@keyword', { fg = naxeforest.purple })
  hl(0, '@function', { fg = naxeforest.blue })
  hl(0, '@function.method', { fg = naxeforest.blue })
  hl(0, '@constructor', { fg = naxeforest.yellow })
  hl(0, '@type', { fg = naxeforest.yellow })
  hl(0, '@string', { fg = naxeforest.green })
  hl(0, '@number', { fg = naxeforest.orange })
  hl(0, '@boolean', { fg = naxeforest.orange })
  hl(0, '@constant', { fg = naxeforest.orange })
  hl(0, '@property', { fg = naxeforest.aqua })
  hl(0, '@variable.parameter', { fg = naxeforest.aqua, italic = true })
  hl(0, '@comment', { fg = naxeforest.subtext0, italic = true })
end

return {
  'sainnhe/everforest',
  lazy = false,
  priority = 1000,
  config = function()
    vim.o.background = 'dark'
    vim.g.everforest_background = 'hard'
    vim.g.everforest_better_performance = 1
    vim.g.everforest_enable_italic = 1
    vim.g.everforest_ui_contrast = 'high'
    vim.g.everforest_colors_override = {
      bg_dim = color(naxeforest.bg_dim, '233'),
      bg0 = color(naxeforest.bg, '235'),
      bg1 = color(naxeforest.bg1, '236'),
      bg2 = color(naxeforest.bg2, '237'),
      bg3 = color(naxeforest.bg3, '238'),
      bg4 = color(naxeforest.bg4, '239'),
      bg5 = color(naxeforest.bg5, '240'),
      bg_visual = color(naxeforest.bg3, '238'),
      bg_red = color('#443136', '52'),
      bg_yellow = color('#453224', '136'),
      bg_green = color('#263544', '22'),
      bg_blue = color(naxeforest.bg2, '17'),
      bg_purple = color(naxeforest.bg2, '54'),
      fg = color(naxeforest.fg, '223'),
      red = color(naxeforest.red, '167'),
      orange = color(naxeforest.orange, '208'),
      yellow = color(naxeforest.yellow, '214'),
      green = color(naxeforest.green, '142'),
      aqua = color(naxeforest.aqua, '108'),
      blue = color(naxeforest.blue, '109'),
      purple = color(naxeforest.purple, '175'),
      grey0 = color(naxeforest.overlay2, '243'),
      grey1 = color(naxeforest.subtext0, '245'),
      grey2 = color(naxeforest.subtext1, '247'),
      statusline1 = color(naxeforest.orange, '208'),
      statusline2 = color(naxeforest.blue, '109'),
      statusline3 = color(naxeforest.red, '167'),
    }

    vim.api.nvim_create_autocmd('ColorScheme', {
      group = vim.api.nvim_create_augroup('naxeforest_everforest_highlights', { clear = true }),
      pattern = 'everforest',
      callback = function()
        apply_highlights()
        apply_terminal_colors()
      end,
    })

    vim.cmd.colorscheme 'everforest'
    apply_terminal_colors()
  end,
}
