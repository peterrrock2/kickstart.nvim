return {
  'hat0uma/csvview.nvim',
  cmd = { 'CsvViewEnable', 'CsvViewDisable', 'CsvViewToggle' },
  keys = {
    {
      '<leader>mp',
      '<cmd>setlocal nowrap<CR><cmd>CsvViewToggle<CR>',
      ft = 'csv',
      desc = 'CSV Preview (inline)',
    },
  },
  opts = {},
}
