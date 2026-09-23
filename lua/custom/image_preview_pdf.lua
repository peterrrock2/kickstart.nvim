local M = {}

function M.read_document(path)
  local result = vim
    .system({ 'pdfinfo', '-f', '1', '-l', '2147483647', path }, {
      text = true,
      env = { LC_ALL = 'C' },
      timeout = 5000,
    })
    :wait()
  assert(result.code == 0, 'Cannot read PDF: ' .. (result.stderr or path))

  local pages = {}
  for number, width, height in result.stdout:gmatch('Page%s+(%d+) size:%s+([%d.]+)%s+x%s+([%d.]+)') do
    pages[tonumber(number)] = { width = tonumber(width), height = tonumber(height) }
  end
  for number, rotation in result.stdout:gmatch('Page%s+(%d+) rot:%s+(%-?%d+)') do
    local page = pages[tonumber(number)]
    if page and tonumber(rotation) % 180 ~= 0 then
      page.width, page.height = page.height, page.width
    end
  end

  local count = tonumber(result.stdout:match('Pages:%s+(%d+)'))
  assert(count and count > 0 and #pages == count, 'Invalid PDF page count')
  local document = { pages = pages, width = 0, height = 0 }
  for number, page in ipairs(pages) do
    assert(page.width > 0 and page.height > 0, 'Invalid PDF page dimensions')
    page.number, page.y = number, document.height
    document.width = math.max(document.width, page.width)
    document.height = document.height + page.height + (number < count and 12 or 0)
  end
  for _, page in ipairs(pages) do
    page.x = (document.width - page.width) / 2
  end
  return document
end

function M.page_at(document, y)
  for number = #document.pages, 1, -1 do
    if y >= document.pages[number].y then
      return number
    end
  end
  return 1
end

function M.build_command(path, width, height, crop, output, page)
  local command = {
    'pdftoppm',
    '-f',
    tostring(page or 1),
    '-singlefile',
    '-png',
    '-scale-dimension-before-rotation',
    '-scale-to-x',
    tostring(width),
    '-scale-to-y',
    tostring(height),
  }
  if crop then
    vim.list_extend(command, {
      '-x',
      tostring(crop.x),
      '-y',
      tostring(crop.y),
      '-W',
      tostring(crop.width),
      '-H',
      tostring(crop.height),
    })
  end
  vim.list_extend(command, { path, (output:gsub('%.png$', '')) })
  return command
end

function M.setup()
  local processor = require('image/processors/magick_cli')
  local get_dimensions, transform = processor.get_dimensions, processor.transform
  processor.get_dimensions = function(path)
    if processor.get_format(path) == 'pdf' then
      -- Fit the first page initially, rather than shrinking the entire document to the window.
      return M.read_document(path).pages[1]
    end
    return get_dimensions(path)
  end
  processor.transform = function(path, request, output, callback)
    if request.source_format ~= 'pdf' then
      return transform(path, request, output, callback)
    end
    -- Rasterize vectors at the requested pixel size, including the initial view and reset.
    local command =
      M.build_command(path, request.target_width, request.target_height, request.crop, output)
    vim.system(command, { text = true }, function(result)
      callback({ ok = result.code == 0, path = output, error = result.stderr })
    end)
  end
end

return M
