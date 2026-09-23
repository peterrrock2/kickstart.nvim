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
local tile_cache = require('custom.image_preview_cache')
local get_plan, current_view = tile_cache.get
tile_cache.get = function(view, viewport, ready)
  current_view = view
  return get_plan(view, viewport, ready)
end
local function placement_key(payload)
  return payload.image_id .. ':' .. (payload.placement_id or 0)
end
package.loaded['image/utils/tmux'] = { is_tmux = false }
package.loaded['image/backends/kitty/helpers'] = {
  write_graphics = function(payload, path)
    graphics[#graphics + 1] = vim.deepcopy(payload)
    if payload.action == 't' then
      transmitted[payload.image_id] = path
    elseif payload.action == 'd' and payload.display_delete == 'a' then
      displayed = {}
    elseif payload.action == 'd' and payload.image_id then
      for key, placement in pairs(displayed) do
        if
          placement.image_id == payload.image_id
          and (not payload.placement_id or placement.placement_id == payload.placement_id)
        then
          displayed[key] = nil
        end
      end
      if payload.display_delete == 'I' then
        transmitted[payload.image_id] = nil
      end
    end
  end,
  write_graphics_at = function(payload, column, row)
    if fail_display then
      fail_display = false
      error('Simulated terminal display failure')
    end
    graphics[#graphics + 1] = vim.deepcopy(payload)
    assert(transmitted[payload.image_id], 'Placement used an image that was not uploaded')
    local placement = vim.deepcopy(payload)
    placement.column, placement.row = column, row
    displayed[placement_key(payload)] = placement
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
      return image.is_rendered
        and image.rendered_geometry.width
        and not image.pending_transform_key
        and not (
          current_view
          and current_view.cache
          and (current_view.cache.demand or current_view.cache.queued)
        )
    end, 10),
    'Image did not render'
  )
  assert(next(displayed), 'No image was displayed')
end
local image = assert(api.hijack_buffer(source))
image:render()
settle(image)
local initial = vim.deepcopy(image.rendered_geometry)
-- Panning a fully visible image must leave its existing terminal placement untouched.
local fitted_placements = vim.deepcopy(displayed)
local fitted_path = image.path
local fitted_commands = #graphics
for _, key in ipairs({ 'h', 'j', 'k', 'l', '10j', '10h' }) do
  vim.cmd.normal({ key })
end
assert(not current_view or not current_view.cache, 'A clamped pan started rendering tiles')
assert(
  image.path == fitted_path and vim.deep_equal(displayed, fitted_placements),
  'Panning a fitted image replaced its placement'
)
assert(#graphics == fitted_commands, 'A clamped pan sent terminal graphics commands')

local function check_tiles()
  local plan = current_view.plan
  local geometry, bounds = image.rendered_geometry, image.bounds
  local left = math.max(0, (bounds.left - geometry.x) * term.cell_width)
  local top = math.max(0, (bounds.top - geometry.y) * term.cell_height)
  local right = math.min(plan.width, (bounds.right - geometry.x) * term.cell_width)
  local bottom = math.min(plan.height, (bounds.bottom - geometry.y + 1) * term.cell_height)
  local rectangles, area = {}, 0
  for _, payload in ipairs(current_view.placements) do
    local placement = assert(displayed[placement_key(payload)], 'Tile placement disappeared')
    local x = (placement.column - 1 - geometry.x) * term.cell_width + placement.display_x_offset
    local y = (placement.row - 1 - geometry.y) * term.cell_height + placement.display_y_offset
    local width, height = placement.display_width, placement.display_height
    assert(
      x >= left and y >= top and x + width <= right and y + height <= bottom,
      'Tile extends beyond the viewport'
    )
    assert(placement.display_x >= 0 and placement.display_y >= 0)
    assert(placement.display_x + width <= 256 and placement.display_y + height <= 256)
    for _, rectangle in ipairs(rectangles) do
      assert(
        x >= rectangle.right
          or x + width <= rectangle.x
          or y >= rectangle.bottom
          or y + height <= rectangle.y,
        'Tile placements overlap'
      )
    end
    rectangles[#rectangles + 1] = { x = x, y = y, right = x + width, bottom = y + height }
    area = area + width * height
  end
  if not current_view.document then
    assert(area == (right - left) * (bottom - top), 'Tile placements leave gaps')
  end
end

local function press(key, wait_for_render)
  local map = vim.fn.maparg(key, 'n', false, true)
  assert(map.buffer == 1 and type(map.callback) == 'function', 'Missing buffer mapping: ' .. key)
  local first_command = #graphics + 1
  vim.cmd.normal({ key })
  assert(image.is_rendered, 'Preview was cleared while its replacement was being prepared')
  if wait_for_render == false then
    return
  end
  settle(image)
  if key ~= '0' then
    assert(
      image.transform_key == nil and not image.pending_transform_key,
      'Prepared tiles needed another resize'
    )
    check_tiles()
  end
  local drawn = 0
  local expected = key == '0' and not current_view.plan and 1 or #current_view.placements
  for index = first_command, #graphics do
    local command = graphics[index]
    if command.action == 't' then
      assert(drawn == 0, 'Uploading after drawing started exposes a partially updated zoom')
    elseif command.action == 'p' then
      drawn = drawn + 1
    elseif command.action == 'd' then
      assert(drawn == expected, 'Old image was deleted before every replacement tile was drawn')
    end
  end
end

-- Rapid zooms accumulate immediately without replacing the visible image mid-render.
local before_zoom = vim.deepcopy(displayed)
vim.cmd.normal({ '+++' })
assert(math.abs(current_view.zoom - 1.25 ^ 3) < 1e-8, 'Rapid zoom keys were dropped')
assert(
  vim.deep_equal(displayed, before_zoom),
  'Cold zoom replaced the image before rendering finished'
)
local pending_zoom = assert(current_view.cache.demand)
-- Ordinary image.nvim redraws during the first zoom must not act like a reset.
local geometry = image.rendered_geometry
require('image/backends/kitty').render(
  image,
  geometry.x,
  geometry.y,
  geometry.width,
  geometry.height
)
assert(current_view.cache.demand == pending_zoom, 'Redraw cancelled an in-flight zoom')
press('0')
assert(vim.wait(10000, function()
  return pending_zoom.finished
end, 5))
assert(image.path == source and current_view.cache == nil, 'Reset allowed stale zoom completion')

press('+')
assert(image.rendered_geometry.width > initial.width, 'Zoom did not enlarge the preview')
press('-')
assert(math.abs(image.rendered_geometry.width - initial.width) <= 1, 'Zoom out failed')
local fitted_tiles = current_view.plan
local graphics_before_pan = #graphics
vim.cmd.normal({ 'hjkl' })
assert(
  current_view.plan == fitted_tiles and #graphics == graphics_before_pan,
  'Panning a fitted tiled view unnecessarily redrew or removed it'
)
local upload_start = #graphics + 1
press('+')
for index = upload_start, #graphics do
  assert(graphics[index].action ~= 't', 'Returning to a cached zoom uploaded its tiles again')
end
press('-')
local previous_placements = vim.deepcopy(displayed)
local draw = require('custom.image_preview_tiles').draw
fail_display = true
local ok, err = pcall(
  draw,
  image,
  current_view,
  current_view.plan,
  image.rendered_geometry.x,
  image.rendered_geometry.y
)
assert(not ok and tostring(err):find('Simulated terminal display failure', 1, true))
assert(image.is_rendered, 'Failed redraw lost the old image')
assert(vim.deep_equal(displayed, previous_placements), 'Failed redraw erased the old placements')
press('+')
assert(not vim.deep_equal(displayed, previous_placements), 'Retry did not replace the old image')
press('-')
-- Completing a zoom after tmux focus loss must wait for image.nvim's restore.
press('+', false)
image.global_state.disable_decorator_handling = true
image:clear(true)
assert(vim.wait(10000, function()
  return current_view.cache.demand == nil
end, 5))
assert(not image.is_rendered and next(displayed) == nil, 'Background zoom drew after focus loss')
image.global_state.disable_decorator_handling = false
image:render()
settle(image)
check_tiles()
press('-')

for _ = 1, 12 do
  press('+')
end
local frame_cache = tile_cache
local get_frame, requests = frame_cache.get, {}
frame_cache.get = function(view, viewport, ready)
  requests[#requests + 1] = viewport
  return get_frame(view, viewport, ready)
end
vim.cmd('normal 10j5k')
assert(#requests == 2, 'Counted motions rendered intermediate frames')
assert(math.abs(requests[1].y - 10 * 2 * term.cell_height) < 1e-8, '10j did not move ten steps')
assert(math.abs(requests[2].y - 5 * 2 * term.cell_height) < 1e-8, '5k did not move back five steps')
vim.cmd('normal 5k10l5h')
local horizontal_step = 4 * term.cell_width
assert(math.abs(requests[3].y) < 1e-8, 'Counted scrolling did not return to the top')
assert(math.abs(requests[4].x - 10 * horizontal_step) < 1e-8, '10l did not move ten steps')
assert(math.abs(requests[5].x - 5 * horizontal_step) < 1e-8, '5h did not move back five steps')
vim.cmd('normal 5h')
frame_cache.get = get_frame
settle(image)
assert(
  image.path ~= source and image.transform_key == nil,
  'Zoom did not produce ready-to-display tiles'
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

-- Unscaled pans move existing placements without uploading overlapping pixels again.
image.ignore_global_max_size = true
image:render({ width = 100, height = 38 })
settle(image)
press('j')
assert(image.transform_key == nil, 'Expected a crop that does not need resizing')
local previous_crop = vim.deepcopy(displayed)
local first_command = #graphics + 1
press('k')
for index = first_command, #graphics do
  assert(graphics[index].action ~= 't', 'Cached pan uploaded unchanged pixels again')
end
assert(not vim.deep_equal(displayed, previous_crop), 'Unscaled pan reused old placements')
press('0')

-- Font cells need not divide the tile size; within-cell offsets must preserve coverage.
term.cell_width, term.cell_height = 9, 19
press('+')
press('j')
press('l')
check_tiles()
local saved_tiles = current_view.plan.tiles
local saved_paths = {}
for _, tile in ipairs(saved_tiles) do
  saved_paths[#saved_paths + 1] = tile.path
end
local tmux = require('image/utils').tmux
local clear_start = #graphics + 1
tmux.is_tmux = true
tmux.get_pane_tty = function()
  return '/dev/preview-test'
end
image:clear(true)
tmux.is_tmux = false
for index = clear_start, #graphics do
  assert(graphics[index].tty == '/dev/preview-test', 'Tmux clear targeted the wrong terminal')
end
assert(next(displayed) == nil, 'Hiding the preview left tile placements')
for _, tile in ipairs(saved_tiles) do
  assert(tile.image_id == nil, 'Hiding retained uploads')
end
image:render()
settle(image)
check_tiles()
for _, path in ipairs(saved_paths) do
  assert(vim.fn.filereadable(path) == 1)
end

-- Leaving a preview frees its cache even when its buffer and window remain alive.
local hidden_view = current_view
local old_buffer = image.buffer
local cached_tiles = {}
for _, tile in pairs(hidden_view.cache.tiles) do
  cached_tiles[#cached_tiles + 1] = { path = tile.path, id = tile.image_id }
end
vim.cmd('enew')
assert(
  vim.wait(1000, function()
    return hidden_view.cache == nil
  end, 5),
  'Switching buffers retained the hidden preview cache'
)
for _, tile in ipairs(cached_tiles) do
  assert(vim.fn.filereadable(tile.path) == 0, 'Hidden preview retained a tile file')
  assert(not tile.id or not transmitted[tile.id], 'Hidden preview retained a terminal upload')
end
vim.cmd.buffer(old_buffer)
image = assert(api.hijack_buffer(source))
settle(image)
assert(image.path == source, 'Returning to a preview used a deleted tile as its source')
local parent_id = image.internal_id
assert(transmitted[parent_id], 'Original preview did not upload')
vim.cmd('enew')
assert(
  vim.wait(1000, function()
    return transmitted[parent_id] == nil
  end, 5),
  'Leaving an untiled preview retained its terminal image data'
)
vim.cmd.buffer(old_buffer)
image = assert(api.hijack_buffer(source))
settle(image)
press('+')
press('0')
term.cell_width, term.cell_height = 8, 16

vim.cmd('enew')
for _, key in ipairs({ '+', '-', 'h', 'j', 'k', 'l', '0' }) do
  assert(vim.fn.maparg(key, 'n') == '', 'Preview mapping leaked into a normal buffer')
end

local pdf = vim.fn.tempname() .. '.pdf'
assert(vim.system({ 'magick', source, '-size', '600x800', 'xc:cyan', pdf }):wait().code == 0)
local dimensions = require('image/processors/magick_cli').get_dimensions(pdf)
assert(
  dimensions.width == 800 and dimensions.height == 600,
  'PDF dimensions combine multiple pages'
)
vim.api.nvim_buf_set_name(0, pdf)
image = assert(api.hijack_buffer(pdf))
image:render()
settle(image)
assert(
  vim.wait(10000, function()
    return current_view and current_view.source == pdf and current_view.plan
  end, 10),
  'Multi-page PDF did not start continuous rendering'
)
settle(image)
local boundary_scroll = math.ceil(
  (current_view.document.pages[2].y * current_view.scale - current_view.plan.height / 2)
    / (2 * term.cell_height)
)
vim.cmd.normal({ boundary_scroll .. 'j' })
settle(image)
local visible_pages = {}
for _, tile in ipairs(current_view.plan.tiles) do
  visible_pages[tile.page] = true
end
assert(visible_pages[1] and visible_pages[2], 'Scrolling cannot show two pages together')
vim.cmd.normal({ '100k' })
settle(image)
assert(current_view.y == 0, 'Scrolling did not return to the document start')
press('+')
for _ = 1, 12 do
  press('+')
end
assert(image.path ~= pdf and image.source_format == 'png', 'PDF zoom did not crop')
press('j')
press('l')
press('0')
assert(current_view.source == pdf and current_view.zoom == 1, 'PDF reset failed')

vim.cmd.normal({ ']p' })
settle(image)
assert(current_view.page == 2, 'Next page did not select page two')
local page_two_tile
for _, tile in ipairs(current_view.plan.tiles) do
  if tile.page == 2 then
    page_two_tile = tile.path
    break
  end
end
assert(page_two_tile, 'Next page is not visible')
pixel = vim
  .system({ 'magick', page_two_tile, '-format', '%[pixel:p{10,10}]', 'info:' }, { text = true })
  :wait()
assert(
  pixel.stdout:find('0,255,255', 1, true),
  'Next page reused page-one pixels: ' .. pixel.stdout
)
press('+')
press('j')
press('0')
assert(current_view.page == 2 and current_view.zoom == 1, 'Reset left the selected PDF page')
vim.cmd.normal({ '10]p' })
settle(image)
assert(current_view.page == 2, 'Page navigation exceeded the document')
vim.cmd.normal({ '[p' })
settle(image)
assert(current_view.page == 1, 'Previous page did not return to page one')
pixel = vim
  .system({ 'magick', image.path, '-format', '%[pixel:p{0,0}]', 'info:' }, { text = true })
  :wait()
assert(pixel.stdout:find('255,0,0', 1, true), 'Previous page reused page-two pixels')
press('0')

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
local second_source = vim.fn.tempname() .. '.png'
assert(vim.system({ 'magick', '-size', '320x240', 'xc:purple', second_source }):wait().code == 0)
local second_buffer = vim.fn.bufadd(second_source)
for _, buffer in ipairs({ second_buffer, source_buffer, second_buffer }) do
  preview:preview(buffer)
  image = assert(api.get_images({ window = preview.winid, buffer = buffer })[1])
  settle(image)
  vim.wait(100)
  assert(
    displayed[image.internal_id .. ':' .. image.internal_id],
    'Switching previews lost the current image'
  )
  assert(vim.api.nvim_get_current_win() == tree_window, 'Switching previews stole focus')
end
local preview_window = preview.winid
preview:revert()
assert(
  vim.api.nvim_win_get_buf(preview_window) == original_buffer,
  'Preview did not restore the buffer'
)
print(
  'PASS: preview controls, continuous PDFs, Kitty uploads, Neo-tree preview, and PDF vector detail'
)
