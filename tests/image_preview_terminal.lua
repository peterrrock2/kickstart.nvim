-- Run: NVIM_LOG_FILE=/tmp/nvim-terminal.log nvim --clean --headless -i NONE -l tests/image_preview_terminal.lua
vim.opt.runtimepath:append(vim.fn.stdpath('config'))
vim.opt.runtimepath:append(vim.fn.stdpath('data') .. '/lazy/image.nvim')
local directory = vim.fn.tempname()
vim.fn.mkdir(directory, 'p')
vim.api.nvim_set_current_dir(directory)

local output = {}
vim.uv.new_tty = function()
  return {
    write = function(_, data)
      output[#output + 1] = data
    end,
  }
end
local detected_tty = 'not a tty'
package.loaded['image/utils/term'] = {
  get_tty = function()
    return detected_tty
  end,
}
package.loaded['image/utils/tmux'] = {
  is_tmux = false,
  get_pane_tty = function()
    return detected_tty
  end,
}

require('custom.image_preview').setup()
local utils = require('image/utils')
local helpers = require('image/backends/kitty/helpers')
for _, name in ipairs({ 'not a tty', '', '/missing/terminal', directory .. '/regular-file' }) do
  detected_tty = name
  if name:match('regular%-file$') then
    vim.fn.writefile({ 'keep me' }, name)
  end
  local before = #output
  helpers.write_graphics({
    action = 'd',
    display_delete = 'I',
    image_id = 1,
    tty = utils.term.get_tty(),
  })
  assert(vim.fn.filereadable('not a tty') == 0, 'Graphics output created a not a tty file')
  assert(#output == before + 1, 'Invalid terminal did not fall back to stdout')
  assert(utils.tmux.get_pane_tty() == nil, 'Invalid tmux terminal was accepted')
end
assert(vim.fn.readfile(directory .. '/regular-file')[1] == 'keep me')
detected_tty = '/dev/null'
assert(utils.term.get_tty() == detected_tty, 'Valid device path was rejected')
assert(utils.tmux.get_pane_tty() == detected_tty, 'Valid tmux device path was rejected')
vim.fn.delete(directory, 'rf')
print('PASS: invalid terminal detection cannot create or overwrite files')
