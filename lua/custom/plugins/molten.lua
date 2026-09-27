local function notebook_outputs(command)
  local path = vim.api.nvim_buf_get_name(0)
  if not path:match '%.ipynb$' then
    error 'Open an .ipynb notebook before importing or exporting outputs'
  end

  local kernels = vim.fn.MoltenRunningKernels(true)
  if #kernels ~= 1 then
    error 'Attach exactly one kernel to this notebook with :MoltenInit first'
  end

  local exporting = command == 'MoltenExportOutput'
  if exporting then
    vim.cmd.write()
    if vim.bo.modified then
      error 'Notebook was not saved; outputs were not exported'
    end
  end

  -- Escape the path through the remote-command bootstrap and bypass kernel redispatch.
  vim.cmd(command .. (exporting and '!' or '') .. ' ' .. vim.fn.fnameescape(path) .. ' ' .. vim.fn.fnameescape(kernels[1]))
  if exporting then
    vim.b.mtime = vim.uv.fs_stat(path).mtime
  end
end

return {
  'benlubas/molten-nvim',
  version = '^1.0.0',
  lazy = false,
  build = ':UpdateRemotePlugins',
  dependencies = { '3rd/image.nvim' },
  init = function()
    vim.g.molten_image_provider = 'image.nvim'
    vim.g.molten_output_win_max_height = 12
    vim.g.molten_virt_text_output = true
    vim.g.molten_auto_open_output = false
  end,
  keys = {
    { '<leader>ji', '<cmd>MoltenInit<CR>', desc = 'Jupyter: choose kernel' },
    {
      '<leader>jI',
      function()
        notebook_outputs 'MoltenImportOutput'
      end,
      desc = 'Jupyter: import notebook outputs',
    },
    {
      '<leader>jw',
      function()
        notebook_outputs 'MoltenExportOutput'
      end,
      desc = 'Jupyter: save notebook and outputs',
    },
    { '<leader>jl', '<cmd>MoltenEvaluateLine<CR>', desc = 'Jupyter: run line' },
    { '<leader>je', '<cmd>MoltenEvaluateOperator<CR>', desc = 'Jupyter: run motion' },
    { '<leader>je', ':<C-u>MoltenEvaluateVisual<CR>gv', mode = 'x', desc = 'Jupyter: run selection' },
    { '<leader>jr', '<cmd>MoltenReevaluateCell<CR>', desc = 'Jupyter: rerun cell' },
    { '<leader>jo', '<cmd>noautocmd MoltenEnterOutput<CR>', desc = 'Jupyter: enter output' },
    { '<leader>jh', '<cmd>MoltenHideOutput<CR>', desc = 'Jupyter: hide output' },
    { '<leader>jx', '<cmd>MoltenInterrupt<CR>', desc = 'Jupyter: interrupt kernel' },
    { '<leader>jd', '<cmd>MoltenDelete<CR>', desc = 'Jupyter: delete cell output' },
    { '<leader>jq', '<cmd>MoltenDeinit<CR>', desc = 'Jupyter: stop kernel for buffer' },
  },
}
