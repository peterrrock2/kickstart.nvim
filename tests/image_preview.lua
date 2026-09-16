-- Run: nvim --clean --headless -i NONE -l <this-file> [path-to-image_preview.lua]
vim.opt.runtimepath:append(vim.fn.stdpath('data') .. '/lazy/image.nvim')
vim.opt.runtimepath:append(vim.fn.stdpath('config'))
vim.o.columns, vim.o.lines = 100, 40
local term = {
  screen_cols = 100,
  screen_rows = 40,
  cell_width = 8,
  cell_height = 16,
  screen_x = 800,
  screen_y = 640,
}
package.loaded['image/utils/term'] = {
  get_size = function()
    return term
  end,
  get_tty = function()
    return '/dev/null'
  end,
}

-- Exercise the real renderer, Kitty upload cache, and ImageMagick without terminal output.
local transmitted, displayed = {}, {}
local graphics = {}
local fail_display = false
package.loaded['image/utils/tmux'] = { is_tmux = false }
package.loaded['image/backends/kitty/helpers'] = {
  write_graphics = function(payload, path)
    graphics[#graphics + 1] = vim.deepcopy(payload)
    if payload.action == 't' then
      transmitted[payload.image_id] = path
    elseif payload.action == 'd' and payload.image_id then
      displayed[payload.image_id] = nil
      if payload.display_delete == 'I' then
        transmitted[payload.image_id] = nil
      end
    end
  end,
  write_graphics_at = function(payload)
    if fail_display then
      fail_display = false
      error('Simulated terminal display failure')
    end
    graphics[#graphics + 1] = vim.deepcopy(payload)
    displayed[payload.image_id] = transmitted[payload.image_id]
  end,
}

local helper = arg[1] or vim.fn.stdpath('config') .. '/lua/custom/image_preview.lua'
dofile(helper).setup()
local api = require('image')
local integrations = {}
for _, name in ipairs({ 'markdown', 'asciidoc', 'typst', 'neorg', 'syslang', 'html', 'css', 'org' }) do
  integrations[name] = { enabled = false }
end
api.setup({ processor = 'magick_cli', integrations = integrations, hijack_file_patterns = {} })

local source = vim.fn.tempname() .. '.png'
assert(vim
  .system({
    'magick',
    '-size',
    '800x600',
    'xc:red',
    '-fill',
    'blue',
    '-draw',
    'rectangle 400,0 799,299',
    '-fill',
    'green',
    '-draw',
    'rectangle 0,300 399,599',
    '-fill',
    'yellow',
    '-draw',
    'rectangle 400,300 799,599',
    source,
  })
  :wait().code == 0)
local original = vim.fn.readfile(source, 'b')
vim.api.nvim_buf_set_name(0, source)

local function settle(image)
  assert(
    vim.wait(10000, function()
      return image.is_rendered and image.rendered_geometry.width and not image.pending_transform_key
    end, 10),
    'Image did not render'
  )
  assert(displayed[image.internal_id] == image.cropped_path, 'Kitty displayed an outdated image')
end
local image = assert(api.hijack_buffer(source))
image:render()
settle(image)
local initial = vim.deepcopy(image.rendered_geometry)
local function press(key, wait_for_render)
  local map = vim.fn.maparg(key, 'n', false, true)
  assert(map.buffer == 1 and type(map.callback) == 'function', 'Missing buffer mapping: ' .. key)
  local previous_id, previous_path, first_command = image.internal_id, image.path, #graphics + 1
  map.callback()
  assert(image.is_rendered, 'Preview was cleared while its replacement was being prepared')
  if key ~= '0' then
    assert(
      image.transform_key == nil and not image.pending_transform_key,
      'Prepared frame needed another resize'
    )
  end
  if wait_for_render ~= false then
    settle(image)
  end
  if image.path ~= previous_path then
    assert(image.internal_id > previous_id, 'Replacement must use a new image id to draw on top')
    local drawn = false
    for index = first_command, #graphics do
      local command = graphics[index]
      if command.action == 'p' and command.image_id == image.internal_id then
        drawn = true
      elseif command.action == 'd' and command.image_id == previous_id then
        assert(drawn, 'Old image was deleted before its replacement was drawn')
        assert(command.display_delete == 'I', 'Retired image data was not released')
      end
    end
    assert(drawn and not displayed[previous_id], 'Replacement left the old image displayed')
    assert(not transmitted[previous_id], 'Retired image data accumulated in the terminal')
  end
end

press('+')
assert(image.rendered_geometry.width > initial.width, 'Zoom did not enlarge the preview')
press('-')
assert(math.abs(image.rendered_geometry.width - initial.width) <= 1, 'Zoom out failed')
local previous_id, previous_frame = image.internal_id, displayed[image.internal_id]
fail_display = true
local ok, err = pcall(vim.fn.maparg('+', 'n', false, true).callback)
assert(not ok and tostring(err):find('Simulated terminal display failure', 1, true))
assert(image.internal_id == previous_id and image.is_rendered, 'Failed redraw lost the old image')
assert(displayed[previous_id] == previous_frame, 'Failed redraw erased the old placement')
assert(vim.tbl_count(transmitted) == 1, 'Failed redraw leaked an uploaded image')
image:render()
settle(image)
assert(
  image.internal_id > previous_id and not displayed[previous_id],
  'Retry did not replace the old image'
)
press('-')
for _ = 1, 12 do
  press('+')
end
assert(
  image.path ~= source and image.transform_key == nil,
  'Zoom did not produce a ready-to-display crop'
)
local preview_window = vim.api.nvim_get_current_win()
vim.cmd('vsplit')
local other = assert(api.hijack_buffer(source))
other:render()
settle(other)
assert(other.image_width == 800 and other.image_height == 600, 'Split inherited a cropped source')
assert(other.path == source, 'Split inherited the temporary source')
vim.cmd('close')
vim.api.nvim_set_current_win(preview_window)
vim.wait(100, function()
  return false
end)
image:render()
settle(image)
for _ = 1, 100 do
  press('l', false)
  press('j', false)
end
settle(image)
local pixel = vim
  .system({ 'magick', image.path, '-format', '%[pixel:p{0,0}]', 'info:' }, { text = true })
  :wait()
assert(
  pixel.stdout:find('255,255,0', 1, true),
  'Scrolling did not reach the bottom-right corner: ' .. pixel.stdout
)
assert(vim.system({ 'magick', '-size', '800x600', 'xc:magenta', source }):wait().code == 0)
press('j')
pixel = vim
  .system({ 'magick', image.path, '-format', '%[pixel:p{0,0}]', 'info:' }, { text = true })
  :wait()
assert(
  pixel.stdout:find('255,0,255', 1, true),
  'Source edit did not invalidate the cached viewport'
)
vim.fn.writefile(original, source, 'b')
for _ = 1, 100 do
  press('h')
  press('k')
end
pixel = vim
  .system({ 'magick', image.path, '-format', '%[pixel:p{0,0}]', 'info:' }, { text = true })
  :wait()
assert(pixel.stdout:find('255,0,0', 1, true), 'Scrolling back failed: ' .. pixel.stdout)
local modified = vim.fn.getftime(source) + 2
assert(vim.uv.fs_utime(source, modified, modified))
local cached_crop = image.path
press('0')
assert(vim.fn.filereadable(cached_crop) == 0, 'Reset did not release the cached frame')
assert(image.path == source and image.image_width == 800 and image.image_height == 600)
assert(not image.ignore_global_max_size, 'Reset lost the original size constraints')
assert(vim.deep_equal(image.rendered_geometry, initial), 'Reset did not restore the original view')
assert(vim.deep_equal(vim.fn.readfile(source, 'b'), original), 'Source file changed')

-- At one source pixel per screen pixel, panning must upload each crop even without a resize.
image.ignore_global_max_size = true
image:render({ width = 100, height = 38 })
settle(image)
press('j')
assert(image.transform_key == nil, 'Expected a crop that does not need resizing')
local previous_crop = displayed[image.internal_id]
press('k')
assert(displayed[image.internal_id] ~= previous_crop, 'Unscaled pan reused the old terminal upload')
press('0')

vim.cmd('enew')
for _, key in ipairs({ '+', '-', 'h', 'j', 'k', 'l', '0' }) do
  assert(vim.fn.maparg(key, 'n') == '', 'Preview mapping leaked into a normal buffer')
end

local pdf = vim.fn.tempname() .. '.pdf'
assert(vim.system({ 'magick', source, pdf }):wait().code == 0)
vim.api.nvim_buf_set_name(0, pdf)
image = assert(api.hijack_buffer(pdf))
image:render()
settle(image)
press('+')
for _ = 1, 12 do
  press('+')
end
assert(image.path ~= pdf and image.source_format == 'png', 'PDF zoom did not crop')
press('j')
press('l')
press('0')
assert(image.path == pdf, 'PDF reset failed: ' .. image.path .. ' expected ' .. pdf)

-- Subpixel vector stripes disappear if the PDF is rasterized at 72 DPI before enlargement.
local postscript = vim.fn.tempname() .. '.ps'
local vector_pdf = vim.fn.tempname() .. '.pdf'
vim.fn.writefile({
  '%!PS',
  '<< /PageSize [72 72] >> setpagedevice',
  '0 0.5 71.5 { 0 0.25 72 rectfill } for',
  'showpage',
}, postscript)
assert(vim
  .system({
    'gs',
    '-q',
    '-dBATCH',
    '-dNOPAUSE',
    '-sDEVICE=pdfwrite',
    '-sOutputFile=' .. vector_pdf,
    postscript,
  })
  :wait().code == 0)
vim.cmd('enew')
vim.api.nvim_buf_set_name(0, vector_pdf)
image = assert(api.hijack_buffer(vector_pdf, nil, nil, { width = 72, height = 36 }))
image.ignore_global_max_size = true
image:render()
settle(image)
local scanline = vim
  .system({
    'magick',
    image.cropped_path,
    '-crop',
    '576x1+0+200',
    '+repage',
    '-depth',
    '8',
    'gray:-',
  })
  :wait()
assert(scanline.code == 0)
local transitions = 0
for i = 2, #scanline.stdout do
  if (scanline.stdout:byte(i) < 128) ~= (scanline.stdout:byte(i - 1) < 128) then
    transitions = transitions + 1
  end
end
assert(transitions > 200, 'PDF vector detail was lost before enlargement: ' .. transitions)
for _ = 1, 6 do
  press('+')
end
assert(
  image.image_width >= image.rendered_geometry.width * term.cell_width,
  'Zoom enlarges a low-resolution PDF crop'
)
press('j')
press('l')
press('0')
assert(image.path == vector_pdf, 'Vector PDF reset failed')

for _, name in ipairs({ 'neo-tree.nvim', 'nui.nvim', 'plenary.nvim', 'nvim-web-devicons' }) do
  vim.opt.runtimepath:append(vim.fn.stdpath('data') .. '/lazy/' .. name)
end
local tree_options = dofile(vim.fn.stdpath('config') .. '/lua/kickstart/plugins/neo-tree.lua').opts
tree_options.log_to_file = false
require('neo-tree').setup(tree_options)
local tree_config = require('neo-tree').ensure_config()
api.setup({
  processor = 'magick_cli',
  integrations = integrations,
  hijack_file_patterns = { '*.png' },
})
vim.cmd('enew')
local original_buffer = vim.api.nvim_get_current_buf()
vim.cmd('vsplit')
local tree_window = vim.api.nvim_get_current_win()
local preview = require('neo-tree.sources.common.preview'):new({
  winid = tree_window,
  current_position = 'right',
  config = tree_config.filesystem.window.mappings.P.config,
})
local source_buffer = vim.fn.bufadd(source)
preview:preview(source_buffer)
assert(
  vim.api.nvim_win_get_buf(preview.winid) == source_buffer,
  'Neo-tree replaced the image buffer with an empty preview buffer'
)
image = assert(api.get_images({ window = preview.winid, buffer = source_buffer })[1])
settle(image)
assert(vim.api.nvim_get_current_win() == tree_window, 'Preview stole focus from the tree')
local preview_window = preview.winid
preview:revert()
assert(
  vim.api.nvim_win_get_buf(preview_window) == original_buffer,
  'Preview did not restore the buffer'
)
print(
  'PASS: preview controls, rapid scrolling, Kitty uploads, Neo-tree preview, and PDF vector detail'
)
