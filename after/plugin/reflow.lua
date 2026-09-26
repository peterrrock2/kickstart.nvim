vim.api.nvim_create_user_command('Reflow', function(opts)
  require('custom.reflow').reflow(opts)
end, { nargs = '?', range = '%', desc = 'Reflow prose to a line width (default: 98)' })

vim.keymap.set('n', '<leader>R', '<cmd>Reflow<CR>', { desc = 'Reflow prose (98 columns)' })
vim.keymap.set('x', '<leader>R', ':Reflow<CR>', { desc = 'Reflow selected prose (98 columns)' })
