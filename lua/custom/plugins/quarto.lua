return {
  'quarto-dev/quarto-nvim',
  ft = { 'markdown', 'quarto' },
  dependencies = { 'jmbuhr/otter.nvim', 'nvim-treesitter/nvim-treesitter' },
  opts = {
    lspFeatures = { languages = { 'python', 'julia', 'r', 'rust' }, chunks = 'all' },
    codeRunner = { enabled = true, default_method = 'molten' },
  },
  config = function(_, opts)
    require('quarto').setup(opts)
    vim.api.nvim_create_autocmd('FileType', {
      pattern = 'markdown',
      group = vim.api.nvim_create_augroup('notebook-quarto', { clear = true }),
      callback = function()
        if vim.api.nvim_buf_get_name(0):match '%.ipynb$' then
          require('quarto').activate()
        end
      end,
    })
  end,
  keys = {
    { '<leader>jc', '<cmd>QuartoSend<CR>', desc = 'Jupyter: run code cell' },
    { '<leader>ja', '<cmd>QuartoSendAbove<CR>', desc = 'Jupyter: run cells through cursor' },
    { '<leader>jA', '<cmd>QuartoSendAll<CR>', desc = 'Jupyter: run all cells' },
  },
}
