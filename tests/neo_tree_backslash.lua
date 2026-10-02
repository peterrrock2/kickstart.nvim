-- Run: nvim --clean --headless -i NONE -l tests/neo_tree_backslash.lua
vim.opt.runtimepath:append(vim.fn.stdpath('config'))
for _, name in ipairs({ 'neo-tree.nvim', 'nui.nvim', 'plenary.nvim', 'nvim-web-devicons' }) do
  vim.opt.runtimepath:append(vim.fn.stdpath('data') .. '/lazy/' .. name)
end

local directory = vim.fn.tempname()
local project = directory .. '/project with spaces'
local nested = project .. '/src'
vim.fn.mkdir(nested, 'p')
vim.fn.writefile({ 'active file' }, nested .. '/example.txt')
vim.fn.system({ 'git', 'init', '--quiet', project })
assert(vim.v.shell_error == 0, 'Could not initialize the temporary Git repository')
vim.cmd.cd(project)
vim.cmd.edit(nested .. '/example.txt')
local file_window = vim.api.nvim_get_current_win()
local file_buffer = vim.api.nvim_get_current_buf()

local config = require('kickstart.plugins.neo-tree')
config.opts.log_to_file = false
require('neo-tree').setup(config.opts)
vim.cmd.runtime('plugin/neo-tree.lua')
for _, mapping in ipairs(config.keys) do
  vim.keymap.set('n', mapping[1], mapping[2], { silent = mapping.silent, desc = mapping.desc })
end

local command = require('neo-tree.command')
local manager = require('neo-tree.sources.manager')
local renderer = require('neo-tree.ui.renderer')
vim.api.nvim_feedkeys('\\', 'xt', false)
local filesystem = manager.get_state('filesystem')
assert(vim.wait(1000, function()
  return filesystem._ready and renderer.window_exists(filesystem)
end, 10), 'Backslash did not reveal the active file')
assert(filesystem.tree:get_node():get_id() == nested .. '/example.txt', 'Reveal lost the active file')
command.execute({ action = 'close' })

for _, source in ipairs({ 'filesystem', 'buffers', 'git_status' }) do
  command.execute({ source = source, dir = project, reveal = false })
  local state = manager.get_state(source)
  assert(vim.wait(1000, function()
    return state._ready and renderer.window_exists(state)
  end, 10), source .. ': tree did not render')
  assert(vim.bo.filetype == 'neo-tree', source .. ': tree did not receive focus')

  vim.api.nvim_feedkeys('\\', 'xt', false)
  vim.wait(300, function()
    return false
  end)
  assert(vim.fn.getcwd() == project, source .. ': backslash changed cwd to ' .. vim.fn.getcwd())
  assert(not renderer.window_exists(state), source .. ': backslash did not close the tree')
  assert(vim.api.nvim_get_current_win() == file_window, source .. ': lost the file window')
  assert(vim.api.nvim_get_current_buf() == file_buffer, source .. ': changed the active file')
  assert(vim.fn.getcwd(-1, -1) == project, source .. ': changed the global directory')
end

-- Revealing an active file outside the tree root must not prompt to change cwd.
local outside_file = directory .. '/outside.txt'
vim.fn.writefile({ 'outside the project' }, outside_file)
vim.cmd.edit(outside_file)
vim.api.nvim_feedkeys('\\', 'xt', false)
local state = manager.get_state('filesystem')
assert(vim.wait(1000, function()
  return state._ready and renderer.window_exists(state)
end, 10), 'Backslash did not open the filesystem tree')
assert(vim.api.nvim_get_current_win() == state.winid, 'Reveal opened a cwd confirmation popup')
assert(state.path == project, 'Reveal changed the tree root to the active file directory')
assert(vim.fn.getcwd() == project, 'Reveal changed the working directory')
command.execute({ action = 'close' })
assert(vim.api.nvim_buf_get_name(0) == outside_file, 'Reveal changed the active file')

vim.cmd.cd(vim.fn.stdpath('config'))
vim.fn.delete(directory, 'rf')
print('PASS: backslash closes every tree source without changing the file or working directory')
