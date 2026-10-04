-- Run: NVIM_LOG_FILE=/tmp/nvim-notebooks.log nvim --headless -n -i NONE -c 'luafile tests/notebooks.lua'
local directory = vim.fn.tempname() .. ' notebooks'
vim.fn.mkdir(directory, 'p')
local environment = directory .. '/.venv'
vim.fn.mkdir(environment .. '/bin', 'p')
vim.fn.writefile({ '#!/bin/sh', 'exec ' .. vim.fn.shellescape(vim.g.python3_host_prog) .. ' "$@"' }, environment .. '/bin/python')
vim.fn.setfperm(environment .. '/bin/python', 'rwx------')
vim.fn.mkdir(environment .. '/share/jupyter/kernels/python3', 'p')
local spec = {
  argv = { 'python', '-m', 'ipykernel_launcher', '-f', '{connection_file}' },
  display_name = 'Notebook test',
  language = 'python',
}
vim.fn.writefile({ vim.json.encode(spec) }, environment .. '/share/jupyter/kernels/python3/kernel.json')
local path = directory .. '/round trip.ipynb'
local original = {
  nbformat = 4,
  nbformat_minor = 5,
  metadata = {
    kernelspec = { name = 'python3', display_name = 'Python 3', language = 'python' },
    language_info = { name = 'python' },
  },
  cells = {
    { id = 'intro', cell_type = 'markdown', metadata = vim.empty_dict(), source = { '# Notebook test' } },
    {
      id = 'calculation',
      cell_type = 'code',
      metadata = { tags = { 'keep-me' } },
      source = { 'print(6 * 7)' },
      execution_count = 1,
      outputs = { { output_type = 'stream', name = 'stdout', text = { 'OLD OUTPUT\n' } } },
    },
  },
}
vim.fn.writefile({ vim.json.encode(original) }, path)

local function output_contains(text)
  local namespace = vim.api.nvim_get_namespaces()['molten-extmarks']
  if not namespace then
    return false
  end

  local marks = vim.api.nvim_buf_get_extmarks(0, namespace, 0, -1, { details = true })
  for _, mark in ipairs(marks) do
    if vim.inspect(mark[4].virt_lines):find(text, 1, true) then
      return true
    end
  end
  return false
end

local function check_notebook()
  vim.cmd.edit(vim.fn.fnameescape(path))
  assert(vim.bo.filetype == 'markdown', 'notebook was not converted to Markdown')
  assert(require('otter.keeper').rafts[vim.api.nvim_get_current_buf()], 'notebook cell runner did not activate')
  assert(vim.fn.has 'python3' == 1, 'Python provider is unavailable')

  local ready = false
  vim.api.nvim_create_autocmd('User', {
    pattern = 'MoltenKernelReady',
    once = true,
    callback = function()
      ready = true
    end,
  })
  local kernel_name
  for _, name in ipairs(vim.fn.MoltenAvailableKernels()) do
    if vim.endswith(name, vim.fn.sha256(environment):sub(1, 12)) then
      kernel_name = name
    end
  end
  assert(kernel_name, 'notebook-local environment was not discovered by Molten')
  vim.cmd('MoltenInit ' .. kernel_name)
  assert(
    vim.wait(15000, function()
      return ready
    end, 50),
    'kernel did not become ready'
  )
  vim.api.nvim_feedkeys(' jI', 'xt', false)
  assert(
    vim.wait(2000, function()
      return output_contains 'OLD OUTPUT'
    end, 50),
    'existing output was not imported'
  )

  local line = vim.fn.search('print(6', 'w')
  assert(line > 0, 'code cell disappeared')
  vim.api.nvim_buf_set_lines(0, line - 1, line, false, { 'print(6 * 8)' })
  vim.cmd 'QuartoSend'
  assert(
    vim.wait(15000, function()
      return output_contains '48'
    end, 50),
    'cell did not execute or show inline output'
  )

  vim.api.nvim_feedkeys(' jw', 'xt', false)
  local saved = vim.json.decode(table.concat(vim.fn.readfile(path), '\n'))
  assert(#saved.cells == 2 and saved.cells[1].cell_type == 'markdown', 'cell structure changed')
  assert(vim.deep_equal(saved.cells[2].source, { 'print(6 * 8)' }), 'edited code was not saved')
  assert(vim.deep_equal(saved.cells[2].metadata.tags, { 'keep-me' }), 'cell metadata was lost')
  local output = saved.cells[2].outputs[1]
  local text = output.text or output.data['text/plain']
  assert(table.concat(text) == '48\n', 'new output was not saved')
  assert(vim.fn.filereadable(directory .. '/round trip.md') == 0, 'conversion left a companion file')

  vim.cmd 'MoltenDeinit'
  vim.cmd 'edit!'
  assert(vim.bo.filetype == 'markdown', 'saved notebook did not reopen as Markdown')
  vim.cmd 'bwipeout!'
  vim.cmd.edit(vim.fn.fnameescape(directory .. '/new.ipynb'))
  vim.cmd 'write'
  local created = vim.json.decode(table.concat(vim.fn.readfile(directory .. '/new.ipynb'), '\n'))
  assert(created.nbformat == 4, 'new notebook is invalid')
end

vim.schedule(function()
  local ok, message = xpcall(check_notebook, debug.traceback)
  pcall(vim.cmd, 'MoltenDeinit')
  vim.cmd 'bwipeout!'
  vim.fn.delete(directory, 'rf')
  if not ok then
    print(message)
    vim.cmd 'cquit 1'
  end

  print 'PASS: notebook conversion, kernel execution, inline output, output export, metadata, and new notebooks'
  vim.cmd 'qa!'
end)
