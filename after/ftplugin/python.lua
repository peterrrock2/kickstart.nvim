vim.opt_local.foldmethod = 'indent'
vim.opt_local.foldlevel = 99
vim.keymap.set('n', 'K', require('custom.docstring_hover').hover, { buffer = true, desc = 'Hover with docstring math' })

vim.b.undo_ftplugin = (vim.b.undo_ftplugin and vim.b.undo_ftplugin .. ' | ' or '') .. 'setlocal foldmethod< foldlevel< | silent! nunmap <buffer> K'
