local function close_buffer(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  if vim.bo[bufnr].modified then
    vim.notify('Save changes before closing this file tab', vim.log.levels.WARN)
    return
  end

  vim.api.nvim_buf_delete(bufnr, {})
end

local keys = {
  { '<F13>', '<Cmd>BufferLineCyclePrev<CR>', desc = 'Corne: previous file tab' },
  { '<F14>', '<Cmd>BufferLineCycleNext<CR>', desc = 'Corne: next file tab' },
  { '<F15>', '<Cmd>BufferLineMovePrev<CR>', desc = 'Corne: move file tab left' },
  { '<F16>', '<Cmd>BufferLineMoveNext<CR>', desc = 'Corne: move file tab right' },
  { '<F17>', function() vim.cmd.enew() end, desc = 'Corne: new file tab' },
  { '<F18>', function() close_buffer(vim.api.nvim_get_current_buf()) end, desc = 'Corne: close file tab' },
  { '<M-n>', function() vim.cmd.enew() end, desc = 'New file tab' },
  { '<M-h>', '<Cmd>BufferLineCyclePrev<CR>', desc = 'Previous file tab' },
  { '<M-l>', '<Cmd>BufferLineCycleNext<CR>', desc = 'Next file tab' },
  { '<M-H>', '<Cmd>BufferLineMovePrev<CR>', desc = 'Move file tab left' },
  { '<M-L>', '<Cmd>BufferLineMoveNext<CR>', desc = 'Move file tab right' },
  { '<M-w>', function() close_buffer(vim.api.nvim_get_current_buf()) end, desc = 'Close file tab' },
}

for index = 1, 9 do
  keys[#keys + 1] = {
    '<M-' .. index .. '>',
    function() require('bufferline').go_to(index) end,
    desc = 'Go to file tab ' .. index,
  }
end

return {
  'akinsho/bufferline.nvim',
  version = '*',
  event = 'VeryLazy',
  dependencies = { 'nvim-tree/nvim-web-devicons' },
  keys = keys,
  opts = {
    options = {
      mode = 'buffers',
      numbers = 'ordinal',
      diagnostics = 'nvim_lsp',
      close_command = close_buffer,
      right_mouse_command = close_buffer,
      middle_mouse_command = close_buffer,
      indicator = { style = 'underline' },
      separator_style = 'thin',
      always_show_bufferline = true,
      persist_buffer_sort = true,
      sort_by = 'insert_after_current',
      show_buffer_close_icons = true,
      show_close_icon = false,
    },
  },
}
