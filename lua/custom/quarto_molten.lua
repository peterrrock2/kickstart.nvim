local M = {}
local pending_cells = {}

local function build_cell_call(cell, ignore_cols)
  local range = cell.range
  local arguments = { range.from[1] + 1, range.to[1] }
  if not ignore_cols then
    vim.list_extend(arguments, { range.from[2] + 1, range.to[2] + 1 })
  end
  return ("vim.fn.MoltenEvaluateRange('%%k', %s)"):format(table.concat(arguments, ', '))
end

local function submit_cells(buffer, calls)
  if not vim.api.nvim_buf_is_valid(buffer) or not vim.api.nvim_buf_is_loaded(buffer) then
    return
  end

  local command = ('lua if vim.api.nvim_buf_is_valid(%d) then vim.api.nvim_buf_call(%d, function() %s end) end'):format(
    buffer,
    buffer,
    table.concat(calls, '; ')
  )
  vim.api.nvim_buf_call(buffer, function()
    local running = vim.fn.MoltenRunningKernels(true)
    local prompt = require 'prompt'
    if #running == 1 then
      vim.cmd(command:gsub('%%k', running[1]))
    elseif #running > 1 then
      prompt.select_and_run(running, 'Choose a kernel for these cells:', command)
    else
      local kernels = {}
      for _, name in ipairs(vim.fn.MoltenAvailableKernels()) do
        kernels[#kernels + 1] = { name, false }
      end
      for _, name in ipairs(vim.fn.MoltenRunningKernels(false)) do
        kernels[#kernels + 1] = { name, true }
      end
      prompt.prompt_init_and_run(kernels, 'Choose a kernel for these cells:', command)
    end
  end)
end

function M.run(cell, ignore_cols)
  local buffer = vim.api.nvim_get_current_buf()
  local calls = pending_cells[buffer]
  if calls then
    calls[#calls + 1] = build_cell_call(cell, ignore_cols)
    return
  end

  if #vim.fn.MoltenRunningKernels(true) == 1 then
    require('quarto.runner.molten').run(cell, ignore_cols)
    return
  end

  pending_cells[buffer] = { build_cell_call(cell, ignore_cols) }
  -- Quarto submits cells in one loop; collect them before opening an asynchronous chooser.
  vim.schedule(function()
    local batch = pending_cells[buffer]
    pending_cells[buffer] = nil
    submit_cells(buffer, batch)
  end)
end

return M
