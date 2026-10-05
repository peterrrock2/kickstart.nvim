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

local function preview_plot()
  local image_api = require 'image'
  local images = {}
  for _, image in ipairs(image_api.get_images { buffer = vim.api.nvim_get_current_buf() }) do
    if image.id:sub(1, 5) == 'virt-' then
      images[#images + 1] = image
    end
  end
  table.sort(images, function(left, right)
    return left.geometry.y < right.geometry.y
  end)

  local function open_image(image)
    if not image then
      return
    end

    local path = image.original_path
    if vim.fn.filereadable(path) ~= 1 then
      vim.notify('Molten plot is no longer available', vim.log.levels.WARN)
      return
    end

    vim.cmd.vsplit(vim.fn.fnameescape(path))
    if vim.bo.filetype ~= 'image_nvim' then
      image_api.hijack_buffer(path)
    end
    vim.keymap.set('n', 'q', '<cmd>close<CR>', { buffer = true, desc = 'Close plot preview' })
  end

  if #images == 0 then
    vim.notify('No Molten plot available in this buffer; run a plotting cell first', vim.log.levels.INFO)
  elseif #images == 1 then
    open_image(images[1])
  else
    vim.ui.select(images, {
      prompt = 'Choose a Molten plot to zoom:',
      format_item = function(image)
        return 'Plot after line ' .. (image.geometry.y + 1)
      end,
    }, open_image)
  end
end

return {
  'benlubas/molten-nvim',
  version = '^1.0.0',
  lazy = false,
  build = ':UpdateRemotePlugins',
  dependencies = { '3rd/image.nvim' },
  init = function()
    require('custom.molten_kernels').setup()
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
    { '<leader>jz', preview_plot, desc = 'Jupyter: zoom plot' },
    { '<leader>jx', '<cmd>MoltenInterrupt<CR>', desc = 'Jupyter: interrupt kernel' },
    { '<leader>jd', '<cmd>MoltenDelete<CR>', desc = 'Jupyter: delete cell output' },
    { '<leader>jq', '<cmd>MoltenDeinit<CR>', desc = 'Jupyter: stop kernel for buffer' },
  },
}
