-- Run: nvim --clean --headless -n -i NONE -l tests/molten_image_preview.lua
local directory = vim.fn.tempname() .. ' molten plots'
vim.fn.mkdir(directory, 'p')
local first_path, second_path = directory .. '/first plot.svg', directory .. '/second plot.png'
vim.fn.writefile({ 'first image' }, first_path)
vim.fn.writefile({ 'second image' }, second_path)
local buffer, window = vim.api.nvim_get_current_buf(), vim.api.nvim_get_current_win()
vim.api.nvim_buf_set_lines(buffer, 0, -1, false, { 'plot source remains here' })
local images, opened = {}, {}
package.loaded.image = {
  get_images = function(options)
    assert(options.buffer == buffer, 'plot lookup used another buffer')
    return images
  end,
  hijack_buffer = function(path)
    assert(vim.api.nvim_get_current_buf() ~= buffer, 'preview overwrote notebook source')
    assert(vim.api.nvim_get_current_win() ~= window, 'preview did not open a split')
    assert(vim.api.nvim_buf_get_name(0) == path, 'image path was not escaped correctly')
    vim.bo.filetype = 'image_nvim'
    opened[#opened + 1] = path
  end,
}
local config = dofile 'lua/custom/plugins/molten.lua'
local preview
for _, key in ipairs(config.keys) do
  if key[1] == '<leader>jz' then
    preview = key[2]
  end
end
assert(preview, 'plot preview mapping is missing')

local notices = {}
vim.notify = function(message)
  notices[#notices + 1] = message
end
preview()
assert(#vim.api.nvim_list_wins() == 1 and #notices == 1, 'empty output opened a preview')

images = {
  { id = 'virt-first', is_rendered = false, original_path = first_path, geometry = { y = 3 } },
  { id = 'markdown', is_rendered = true, original_path = second_path, geometry = { y = 4 } },
}
preview()
assert(opened[1] == first_path, 'preview did not open an offscreen Molten plot')
local close = vim.fn.maparg('q', 'n', false, true)
assert(close.buffer == 1 and close.rhs == '<cmd>close<CR>', 'preview has no close shortcut')
vim.cmd.close()
assert(vim.api.nvim_get_current_win() == window, 'closing did not return to notebook')
assert(vim.api.nvim_buf_get_lines(buffer, 0, -1, false)[1] == 'plot source remains here')

table.insert(images, 1, {
  id = 'virt-second',
  is_rendered = true,
  original_path = second_path,
  geometry = { y = 8 },
})
vim.ui.select = function(choices, options, choose)
  assert(#choices == 2 and choices[1].original_path == first_path, 'plot choices were not filtered and sorted')
  assert(options.format_item(choices[2]) == 'Plot after line 9')
  choose(nil)
  assert(#vim.api.nvim_list_wins() == 1, 'cancelling opened a preview')
  choose(choices[2])
end
preview()
assert(opened[2] == second_path, 'chosen plot did not open')
vim.cmd.close()
vim.fn.delete(directory, 'rf')
print 'PASS: offscreen Molten plots, plot selection, separate preview, cancellation, and notebook preservation'
