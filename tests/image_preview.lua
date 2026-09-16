-- Run: nvim --clean --headless -i NONE -l <this-file> [path-to-image_preview.lua]
vim.opt.runtimepath:append(vim.fn.stdpath('data') .. '/lazy/image.nvim')
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
}

-- Keep the real renderer and ImageMagick; replace only terminal output.
local backend = { features = { crop = true } }
function backend.setup(state)
  backend.state = state
end
function backend.render(image)
  backend.state.images[image.id] = image
  image.is_rendered = true
end
function backend.clear(id, shallow)
  local image = backend.state.images[id]
  if image then
    image.is_rendered = false
    if not shallow then
      backend.state.images[id] = nil
    end
  end
end
package.loaded['image/backends/kitty'] = backend

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
end
local image = assert(api.hijack_buffer(source))
image:render()
settle(image)
local initial = vim.deepcopy(image.rendered_geometry)
local function press(key)
  local map = vim.fn.maparg(key, 'n', false, true)
  assert(map.buffer == 1 and type(map.callback) == 'function', 'Missing buffer mapping: ' .. key)
  map.callback()
  settle(image)
end

press('+')
assert(image.rendered_geometry.width > initial.width, 'Zoom did not enlarge the preview')
press('-')
assert(math.abs(image.rendered_geometry.width - initial.width) <= 1, 'Zoom out failed')
for _ = 1, 12 do
  press('+')
end
assert(image.image_width < 400 and image.image_height < 300, 'Zoom did not crop the viewport')
local preview_window = vim.api.nvim_get_current_win()
vim.cmd('vsplit')
local other = assert(api.hijack_buffer(source))
other:render()
settle(other)
assert(other.image_width == 800 and other.image_height == 600, 'Split inherited a cropped source')
assert(other.path == source, 'Split inherited the temporary source')
vim.cmd('close')
vim.api.nvim_set_current_win(preview_window)
for _ = 1, 100 do
  press('l')
  press('j')
end
local pixel = vim
  .system({ 'magick', image.path, '-format', '%[pixel:p{0,0}]', 'info:' }, { text = true })
  :wait()
assert(
  pixel.stdout:find('255,255,0', 1, true),
  'Scrolling did not reach the bottom-right corner: ' .. pixel.stdout
)
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
press('0')
assert(image.path == source and image.image_width == 800 and image.image_height == 600)
assert(not image.ignore_global_max_size, 'Reset lost the original size constraints')
assert(vim.deep_equal(image.rendered_geometry, initial), 'Reset did not restore the original view')
assert(vim.deep_equal(vim.fn.readfile(source, 'b'), original), 'Source file changed')

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
print('PASS: preview controls, source preservation, buffer/split isolation, and PDF vector detail')
