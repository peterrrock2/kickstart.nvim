-- Run: nvim --clean --headless -n -i NONE -l tests/molten_kernels.lua
vim.opt.runtimepath:prepend(vim.fn.getcwd())
local directory = vim.fn.tempname() .. ' molten projects'
local original_path = vim.env.JUPYTER_PATH
local original_venv = vim.env.VIRTUAL_ENV
local original_conda = vim.env.CONDA_PREFIX
vim.env.JUPYTER_PATH = directory .. '/existing'
vim.env.VIRTUAL_ENV = directory .. '/activated'
vim.env.CONDA_PREFIX = nil

local function make_environment(path)
  vim.fn.mkdir(path .. '/bin', 'p')
  vim.fn.writefile({ '#!/bin/sh' }, path .. '/bin/python')
  vim.fn.setfperm(path .. '/bin/python', 'rwx------')
  vim.fn.mkdir(path .. '/share/jupyter/kernels/python3', 'p')
  local spec = {
    argv = { 'python', '-m', 'ipykernel_launcher', '-f', '{connection_file}' },
    display_name = 'Python 3',
    language = 'python',
    env = { KEEP_ME = 'yes' },
    metadata = { debugger = true },
  }
  vim.fn.writefile({ vim.json.encode(spec) }, path .. '/share/jupyter/kernels/python3/kernel.json')
end

make_environment(directory .. '/first/.venv')
make_environment(directory .. '/second/.venv')
make_environment(vim.env.VIRTUAL_ENV)
vim.fn.mkdir(directory .. '/first/nested', 'p')
vim.api.nvim_buf_set_name(0, directory .. '/first/nested/notebook.ipynb')
require('custom.molten_kernels').setup()

local search_path = vim.split(vim.env.JUPYTER_PATH, ':', { plain = true })
assert(search_path[2] == directory .. '/existing', 'existing Jupyter search path was lost')
local function registered_specs()
  local specs = {}
  for _, path in ipairs(vim.fn.glob(search_path[1] .. '/kernels/*/kernel.json', false, true)) do
    local spec = vim.json.decode(table.concat(vim.fn.readfile(path), '\n'))
    specs[spec.argv[1]] = { name = vim.fs.basename(vim.fs.dirname(path)), spec = spec }
  end
  return specs
end

local specs = registered_specs()
local first_python = directory .. '/first/.venv/bin/python'
local second_python = directory .. '/second/.venv/bin/python'
assert(specs[first_python], 'nearest project environment was not discovered from the buffer')
assert(specs[vim.env.VIRTUAL_ENV .. '/bin/python'], 'activated environment was not discovered')
assert(specs[first_python].spec.env.KEEP_ME == 'yes', 'kernelspec environment was lost')
assert(specs[first_python].spec.metadata.debugger, 'kernelspec metadata was lost')
assert(specs[first_python].spec.argv[5] == '{connection_file}', 'kernel arguments were changed')

vim.cmd.enew()
vim.api.nvim_buf_set_name(0, directory .. '/second/notebook.ipynb')
vim.api.nvim_exec_autocmds('BufEnter', { buffer = 0 })
specs = registered_specs()
assert(specs[second_python], 'switching projects did not discover the new environment')
assert(specs[first_python], 'previously discovered kernels disappeared')
assert(specs[first_python].name ~= specs[second_python].name, 'project .venv names collided')

vim.env.JUPYTER_PATH = original_path
vim.env.VIRTUAL_ENV = original_venv
vim.env.CONDA_PREFIX = original_conda
vim.fn.delete(directory, 'rf')
print 'PASS: local and activated kernels, unique names, pinned interpreters, and preserved specs'
