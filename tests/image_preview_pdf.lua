-- Run: nvim --clean --headless -i NONE -l tests/image_preview_pdf.lua
vim.opt.runtimepath:append(vim.fn.stdpath('config'))
local pdf = require('custom.image_preview_pdf')
local cache = require('custom.image_preview_cache')
local source, postscript = vim.fn.tempname() .. '.pdf', vim.fn.tempname() .. '.ps'
vim.fn.writefile({
  '%!PS',
  '<< /PageSize [800 600] >> setpagedevice',
  '1 0 0 setrgbcolor 0 0 800 600 rectfill showpage',
  '<< /PageSize [600 800] >> setpagedevice',
  '0 1 1 setrgbcolor 0 0 600 800 rectfill showpage',
  '<< /PageSize [200 300] >> setpagedevice',
  '0 0 1 setrgbcolor 0 0 200 300 rectfill showpage',
}, postscript)
assert(vim
  .system({
    'gs',
    '-q',
    '-dBATCH',
    '-dNOPAUSE',
    '-sDEVICE=pdfwrite',
    '-sOutputFile=' .. source,
    postscript,
  })
  :wait().code == 0)
local document = pdf.read_document(source)
assert(#document.pages == 3 and document.width == 800 and document.height == 1724)
assert(document.pages[2].x == 100 and document.pages[2].y == 612)
local view =
  { source = source, format = 'pdf', width = 800, height = 600, document = document, modified = 1 }
local viewport =
  { x = 0, y = 280, width = 400, height = 70, scaled_width = 400, scaled_height = 862 }

local function render()
  local plan
  cache.get(view, viewport, function(result)
    plan = result
    cache.commit(view, plan)
  end)
  assert(
    vim.wait(10000, function()
      return plan ~= nil
    end, 5),
    'PDF tiles did not render'
  )
  return plan
end

local plan = render()
local frame = vim.fn.tempname() .. '.png'
local command = { 'magick', '-size', '400x70', 'xc:black' }
for _, tile in ipairs(plan.tiles) do
  assert(tile.page ~= 3, 'Rendered a distant page')
  vim.list_extend(
    command,
    { tile.path, '-geometry', ('%+d%+d'):format(tile.x - plan.x, tile.y - plan.y), '-composite' }
  )
end
command[#command + 1] = frame
assert(vim.system(command):wait().code == 0)
local pixels = vim.system({ 'magick', frame, '-depth', '8', 'RGB:-' }):wait()
assert(pixels.code == 0)
local function pixel(x, y)
  local offset = (y * 400 + x) * 3 + 1
  return { pixels.stdout:byte(offset, offset + 2) }
end
assert(vim.deep_equal(pixel(20, 10), { 255, 0, 0 }), 'Lost the bottom of page one')
assert(vim.deep_equal(pixel(60, 30), { 0, 255, 255 }), 'Lost the top of page two')
assert(vim.deep_equal(pixel(60, 22), { 0, 0, 0 }), 'Page gap contains stale pixels')
assert(vim.deep_equal(pixel(20, 30), { 0, 0, 0 }), 'Narrow page is not centered')

-- Adjacent scroll positions keep the same page tiles and their global coordinates.
viewport.y = 285
local shifted = render()
assert(
  shifted.tiles[1] == plan.tiles[1],
  'Scrolling across a page boundary discarded cached pixels'
)
viewport.y, viewport.height = 301, 4
assert(#render().tiles == 0, 'A viewport inside a page gap should have no page tiles')
cache.clear(view)

local rotated = vim.fn.tempname() .. '.pdf'
assert(vim.system({ 'qpdf', '--rotate=+90:2', source, rotated }):wait().code == 0)
view.source, view.document = rotated, pdf.read_document(rotated)
assert(view.document.pages[2].width == 800 and view.document.pages[2].height == 600)
viewport.y, viewport.height = 310, 290
viewport.scaled_height = view.document.height / 2
for _, tile in ipairs(render().tiles) do
  local size = vim
    .system({ 'magick', 'identify', '-format', '%wx%h', tile.path }, { text = true })
    :wait()
  assert(
    size.stdout == ('%dx%d'):format(tile.width, tile.height),
    'Rotated PDF tile has wrong dimensions'
  )
end
cache.clear(view)
for _, path in ipairs({ source, postscript, frame, rotated }) do
  vim.fn.delete(path)
end
print('PASS: continuous PDF boundaries, mixed page sizes, page gaps, tile reuse, and rotation')
