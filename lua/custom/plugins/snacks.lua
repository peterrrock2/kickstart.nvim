return {
  'folke/snacks.nvim',
  priority = 1000,
  lazy = false,
  init = function()
    local group = vim.api.nvim_create_augroup('persistent_bigfile', { clear = true })
    -- Register before parser plugins: sessions can restore an obsolete filetype.
    vim.api.nvim_create_autocmd('FileType', {
      group = group,
      callback = function(event)
        if event.match == 'bigfile' then
          vim.b[event.buf].bigfile = true
        elseif vim.b[event.buf].bigfile then
          vim.bo[event.buf].filetype = 'bigfile'
        end
      end,
    })

    vim.api.nvim_create_autocmd({ 'BufWinEnter', 'SessionLoadPost' }, {
      group = group,
      callback = function()
        for _, window in ipairs(vim.api.nvim_list_wins()) do
          local buffer = vim.api.nvim_win_get_buf(window)
          if vim.b[buffer].bigfile then
            vim.bo[buffer].indentexpr = ''
            vim.wo[window][0].foldmethod = 'manual'
            vim.wo[window][0].wrap = false
          end
        end
      end,
    })
  end,
  opts = { bigfile = { enabled = true } },
}
