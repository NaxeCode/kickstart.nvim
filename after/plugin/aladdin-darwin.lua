-- Aladdin OS's Mac palette. Keep the Linux theme and local plugin work intact.
if vim.fn.has 'macunix' == 0 then return end

local ok, palette = pcall(require, 'config.palette')
if not ok then return end
local colors = {
    bg_dark = '#080b14', bg_dim = '#0b0e1a', bg = '#0b0e1a',
    bg1 = '#171b28', bg2 = '#1f2538', bg3 = '#2b3247',
    bg4 = '#384155', bg5 = '#4b5670',
    fg = '#f1f3fc', subtext1 = '#bdd3ef', subtext0 = '#8b95ad',
    muted = '#8b95ad', overlay2 = '#8b95ad',
    red = '#ff6592', orange = '#22baf3', orange_soft = '#83d9f9',
    yellow = '#fea334', green = '#9fca9d', blue = '#7c83ff',
    aqua = '#22baf3', purple = '#cb69f3', violet = '#7c83ff',
    selection = '#384155', diff_add = '#183529', diff_change = '#242d4c',
    diff_delete = '#3b2031', diff_text = '#3f3650',
    diagnostic_error = '#ff6592', diagnostic_warn = '#fea334',
    diagnostic_info = '#7c83ff', diagnostic_hint = '#22baf3',
    function_name = '#cb69f3',
}
for key, value in pairs(colors) do palette[key] = value end
local theme_ok, theme = pcall(require, 'plugins.everforest')
if theme_ok and type(theme.setup) == 'function' then theme.setup() end
