local M = {}

function M.restore(window)
  if not vim.api.nvim_win_is_valid(window) then
    return
  end

  local buffer = vim.api.nvim_win_get_buf(window)
  if vim.bo[buffer].buftype ~= '' then
    return
  end

  for _, option in ipairs { 'signcolumn', 'number', 'relativenumber' } do
    vim.api.nvim_set_option_value(option, vim.go[option], { win = window, scope = 'local' })
  end
end

function M.setup()
  vim.api.nvim_create_autocmd({ 'BufWinEnter', 'SessionLoadPost' }, {
    group = vim.api.nvim_create_augroup('source-window-options', { clear = true }),
    callback = function()
      for _, window in ipairs(vim.api.nvim_list_wins()) do
        M.restore(window)
      end
    end,
  })
end

return M
