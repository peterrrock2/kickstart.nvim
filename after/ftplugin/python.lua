vim.opt_local.foldmethod = 'indent'
vim.opt_local.foldlevel = 99

vim.b.undo_ftplugin = (vim.b.undo_ftplugin and vim.b.undo_ftplugin .. ' | ' or '')
  .. 'setlocal foldmethod< foldlevel<'
