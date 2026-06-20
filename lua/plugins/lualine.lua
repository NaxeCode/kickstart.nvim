local naxeforest = {
  bg = '#1b222b',
  bg1 = '#222c37',
  bg2 = '#2a3745',
  bg3 = '#344456',
  fg = '#d8d5c4',
  muted = '#a2adb4',
  orange = '#ff9e64',
  blue = '#7faad6',
  aqua = '#86c9dc',
  green = '#86c9dc',
  red = '#e68183',
}

local theme = {
  normal = {
    a = { fg = naxeforest.bg, bg = naxeforest.orange, gui = 'bold' },
    b = { fg = naxeforest.fg, bg = naxeforest.bg3 },
    c = { fg = naxeforest.fg, bg = naxeforest.bg1 },
  },
  insert = {
    a = { fg = naxeforest.bg, bg = naxeforest.blue, gui = 'bold' },
    b = { fg = naxeforest.fg, bg = naxeforest.bg3 },
    c = { fg = naxeforest.fg, bg = naxeforest.bg1 },
  },
  visual = {
    a = { fg = naxeforest.bg, bg = naxeforest.aqua, gui = 'bold' },
    b = { fg = naxeforest.fg, bg = naxeforest.bg3 },
    c = { fg = naxeforest.fg, bg = naxeforest.bg1 },
  },
  replace = {
    a = { fg = naxeforest.bg, bg = naxeforest.red, gui = 'bold' },
    b = { fg = naxeforest.fg, bg = naxeforest.bg3 },
    c = { fg = naxeforest.fg, bg = naxeforest.bg1 },
  },
  command = {
    a = { fg = naxeforest.bg, bg = naxeforest.green, gui = 'bold' },
    b = { fg = naxeforest.fg, bg = naxeforest.bg3 },
    c = { fg = naxeforest.fg, bg = naxeforest.bg1 },
  },
  inactive = {
    a = { fg = naxeforest.muted, bg = naxeforest.bg1 },
    b = { fg = naxeforest.muted, bg = naxeforest.bg1 },
    c = { fg = naxeforest.muted, bg = naxeforest.bg },
  },
}

return {
  'nvim-lualine/lualine.nvim',
  event = 'VimEnter',
  dependencies = { 'nvim-tree/nvim-web-devicons' },
  opts = {
    options = {
      theme = theme,
      globalstatus = true,
      section_separators = '',
      component_separators = '',
    },
    sections = {
      lualine_a = { 'mode' },
      lualine_b = { 'branch' },
      lualine_c = { { 'filename', path = 1 } },
      lualine_x = { 'diagnostics' },
      lualine_y = { 'filetype' },
      lualine_z = { 'location' },
    },
  },
}
