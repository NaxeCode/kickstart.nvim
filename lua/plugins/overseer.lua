return {
  'stevearc/overseer.nvim',
  opts = {},
  keys = {
    { '<leader>or', '<cmd>OverseerRun<cr>', desc = 'Overseer: Run task' },
    { '<leader>ot', '<cmd>OverseerToggle<cr>', desc = 'Overseer: Task list' },
    { '<leader>oa', '<cmd>OverseerTaskAction<cr>', desc = 'Overseer: Task action' },
    { '<leader>os', '<cmd>OverseerShell<cr>', desc = 'Overseer: Shell task' },
  },
}
