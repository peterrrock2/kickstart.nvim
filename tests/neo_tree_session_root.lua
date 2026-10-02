-- Run: nvim --clean --headless -i NONE -l tests/neo_tree_session_root.lua
vim.opt.runtimepath:append(vim.fn.stdpath('config'))
for _, name in ipairs({
  'auto-session',
  'neo-tree.nvim',
  'nui.nvim',
  'plenary.nvim',
  'nvim-web-devicons',
}) do
  vim.opt.runtimepath:append(vim.fn.stdpath('data') .. '/lazy/' .. name)
end
vim.env.AUTOSESSION_UNIT_TESTING = '1'

local directory = vim.fn.tempname()
local project = directory .. '/project with spaces'
local nested = project .. '/src'
local documents = project .. '/docs'
vim.fn.mkdir(nested, 'p')
vim.fn.mkdir(documents, 'p')
vim.fn.writefile({ 'restored file' }, nested .. '/example.txt')
vim.fn.writefile({ 'another restored file' }, documents .. '/notes.txt')
vim.cmd.cd(project)
vim.cmd.edit(nested .. '/example.txt')
vim.cmd.tcd(nested)
vim.cmd.tabnew(documents .. '/notes.txt')
vim.cmd.tcd(documents)
vim.cmd.lcd(nested)
vim.cmd.vsplit(documents .. '/notes.txt')
vim.cmd.lcd(documents)
vim.cmd.tabfirst()

local session_config = dofile(vim.fn.stdpath('config') .. '/lua/custom/plugins/auto-session.lua')
session_config.init()
local sessions = directory .. '/sessions/'
vim.fn.mkdir(sessions, 'p')
local session = sessions .. require('auto-session.lib').escape_session_name(project) .. '.vim'
vim.cmd('mksession! ' .. vim.fn.fnameescape(session))
assert(vim.fn.filereadable(session) == 1, 'Session was not saved at its encoded filename')
vim.cmd.cd(project)
vim.cmd.enew()

-- Directory restoration also works when the sidebar plugin has not loaded.
vim.cmd.lcd(nested)
session_config.opts.post_restore_cmds[3]()
assert(vim.fn.getcwd() == project, 'Restoring the directory depended on Neo-tree being loaded')

local tree_options = dofile(vim.fn.stdpath('config') .. '/lua/kickstart/plugins/neo-tree.lua').opts
tree_options.log_to_file = false
require('neo-tree').setup(tree_options)
local auto_session = require('auto-session')
auto_session.setup(vim.tbl_deep_extend('force', session_config.opts, {
  root_dir = sessions,
  auto_save = false,
  session_lens = { load_on_setup = false, session_control = { control_dir = directory } },
}))
assert(auto_session.auto_restore_session_at_vim_enter(), 'Session did not automatically restore')
-- Neo-tree batches directory-change events from the sourced session for 200 ms.
vim.wait(300, function()
  return false
end)
assert(vim.fn.getcwd(-1, -1) == project, 'Session changed the global project directory')
assert(vim.fn.getcwd() == project, 'Session restored a stale tab directory')
assert(vim.v.this_session == session, 'Resetting directories cleared the restored session')
assert(vim.api.nvim_buf_get_name(0) == nested .. '/example.txt', 'Session lost the current file')
assert(#vim.api.nvim_list_wins() == 3, 'Restoring roots changed the saved window layout')

for _, window in ipairs(vim.api.nvim_list_wins()) do
  vim.api.nvim_win_call(window, function()
    assert(vim.fn.getcwd() == project, 'Session restored a stale window or tab directory')
    assert(vim.fn.haslocaldir() == 0, 'Session left a local directory override')
  end)
end

local command = require('neo-tree.command')
local manager = require('neo-tree.sources.manager')
for _, tab in ipairs(vim.api.nvim_list_tabpages()) do
  vim.api.nvim_set_current_tabpage(tab)
  local window = vim.api.nvim_get_current_win()
  local source = vim.api.nvim_buf_get_name(0)
  command.execute({ action = 'show', reveal = true })
  local state = manager.get_state('filesystem', tab)
  assert(
    vim.wait(1000, function()
      return state._ready and require('neo-tree.ui.renderer').window_exists(state)
    end, 10),
    'Restored tree did not finish rendering'
  )
  assert(
    state.path == project,
    'Neo-tree used the restored local directory instead of the launch directory'
  )
  assert(vim.api.nvim_get_current_win() == window, 'Restoring the tree root stole focus')
  assert(vim.api.nvim_buf_get_name(0) == source, 'Opening the tree changed the restored file')
  command.execute({ action = 'close' })
end

-- Explicit root changes retain Neo-tree's normal tab-directory binding after restore.
command.execute({ action = 'show', dir = documents })
assert(
  vim.wait(1000, function()
    return manager.get_state('filesystem').path == documents
  end, 10),
  'Explicit tree navigation was overridden'
)
assert(vim.fn.getcwd(-1, 0) == documents, 'Explicit tree navigation lost its tab-directory binding')
assert(vim.fn.getcwd(-1, -1) == project, 'Opening Neo-tree changed the global project directory')
command.execute({ action = 'close' })

vim.fn.delete(directory, 'rf')
print(
  'PASS: automatic restore resets local directories and sidebar roots, preserving navigation'
)
