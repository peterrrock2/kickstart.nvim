-- Run: NVIM_LOG_FILE=/tmp/nvim-quarto-kernel-prompt.log nvim --headless -n -i NONE -c 'luafile tests/quarto_kernel_prompt.lua'
-- Include execution: add NVIM_TEST_MOLTEN_EXECUTE=1 to the command above.
local path = vim.fn.tempname() .. '.qmd'
local lines = {}
for cell = 1, 5 do
  vim.list_extend(lines, { '```{python}', "print('CELL_" .. cell .. "')", '```', '' })
end
vim.fn.writefile(lines, path)

local function check_prompt()
  vim.g.molten_image_provider = 'none'
  vim.cmd.edit(vim.fn.fnameescape(path))
  require('quarto').activate()
  vim.api.nvim_win_set_cursor(0, { 18, 0 })
  local select, prompts = vim.ui.select, 0
  vim.ui.select = function(...)
    prompts = prompts + 1
    return select(...)
  end
  vim.api.nvim_feedkeys(' ja', 'xt', false)
  assert(
    vim.wait(2000, function()
      return prompts > 0
    end, 10),
    'kernel chooser did not open'
  )
  vim.api.nvim_feedkeys('', 'x', false)
  assert(prompts == 1, 'running five cells opened ' .. prompts .. ' kernel choosers')
  local prompt = vim.api.nvim_get_current_buf()
  assert(vim.bo[prompt].filetype == 'TelescopePrompt', 'kernel chooser did not use Telescope')
  local picker = require('telescope.actions.state').get_current_picker(prompt)
  assert(picker:_get_prompt() == '', 'kernel search contains automatic keystrokes')
  require('telescope.actions').close(prompt)
  vim.ui.select = select

  if vim.env.NVIM_TEST_MOLTEN_EXECUTE == '1' then
    local selections = 0
    vim.ui.select = function(items, _, choose)
      selections = selections + 1
      for _, item in ipairs(items) do
        if item[1] == 'python3' and not item[2] then
          choose(item)
          return
        end
      end
      error 'test Python kernel is unavailable'
    end
    vim.api.nvim_feedkeys(' jA', 'xt', false)
    local executed = vim.wait(15000, function()
      local namespace = vim.api.nvim_get_namespaces()['molten-extmarks']
      if not namespace then
        return false
      end
      local output = vim.inspect(vim.api.nvim_buf_get_extmarks(0, namespace, 0, -1, { details = true }))
      for cell = 1, 5 do
        if not output:find('CELL_' .. cell, 1, true) then
          return false
        end
      end
      return true
    end, 20)
    assert(executed, 'selected kernel did not execute all five queued cells')
    assert(selections == 1, 'kernel selection was repeated during execution')
    vim.ui.select = select
    vim.cmd 'MoltenDeinit'
    print 'PASS: selecting one kernel executes all five queued cells'
  end
end

vim.schedule(function()
  local ok, message = xpcall(check_prompt, debug.traceback)
  vim.fn.delete(path)
  if not ok then
    print(message)
    vim.cmd 'cquit 1'
  end
  print 'PASS: five notebook cells open one kernel chooser with an empty search field'
  vim.cmd 'qa!'
end)
