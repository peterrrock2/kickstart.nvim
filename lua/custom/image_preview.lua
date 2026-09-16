local M = {}
local views = setmetatable({}, { __mode = 'k' })

local function pdf_command(path, width, height, crop, output)
  local command = {
    'pdftoppm',
    '-f',
    '1',
    '-singlefile',
    '-png',
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

local function install_pdf_renderer()
  local processor = require('image/processors/magick_cli')
  local transform = processor.transform
  processor.transform = function(path, request, output, callback)
    if request.source_format ~= 'pdf' then
      return transform(path, request, output, callback)
    end

    -- Rasterize vectors at the requested pixel size, including the initial view and reset.
    local command =
      pdf_command(path, request.target_width, request.target_height, request.crop, output)
    vim.system(command, { text = true }, function(result)
      callback({ ok = result.code == 0, path = output, error = result.stderr })
    end)
  end
end

local function get_view(image, cell_width)
  local view = views[image]
  if view and view.modified == vim.fn.getftime(view.source) then
    return view
  end

  local processor = image.global_state.processor
  local source = view and view.source or image.original_path
  local dimensions = processor.get_dimensions(source)
  if view then
    view.scale = view.scale * view.width / dimensions.width
    view.width, view.height = dimensions.width, dimensions.height
    view.format = processor.get_format(source)
    view.modified = vim.fn.getftime(source)
    return view
  end

  view = {
    source = source,
    width = dimensions.width,
    height = dimensions.height,
    format = processor.get_format(source),
    geometry = vim.deepcopy(image.geometry),
    ignore_max = image.ignore_global_max_size,
    offset = image.render_offset_top,
    modified = vim.fn.getftime(source),
    scale = image.rendered_geometry.width * cell_width / dimensions.width,
    zoom = 1,
    x = 0,
    y = 0,
  }
  views[image] = view
  return view
end

local function replace_source(image, path, format, width, height)
  image:clear()
  -- Keep cropped sources separate so image.nvim does not clone them into another window.
  image.original_path = path
  image.path, image.source_format = path, format
  image.image_width, image.image_height = width, height
  image.resized_path, image.cropped_path = path, path
  image.resize_hash, image.crop_hash = nil, nil
  image.transform_key, image.transform_signature = nil, nil
  image.last_modified = vim.fn.getftime(image.original_path)
end

local function crop_view(view, scale, width, height, x, y)
  if view.format ~= 'pdf' and width == view.width and height == view.height then
    return view.source, view.format, width, height
  end

  local path = vim.fn.tempname() .. '.png'
  local command
  if view.format == 'pdf' then
    width = math.max(1, math.floor(width * scale))
    height = math.max(1, math.floor(height * scale))
    command = pdf_command(
      view.source,
      math.max(1, math.floor(view.width * scale)),
      math.max(1, math.floor(view.height * scale)),
      { x = math.floor(x * scale), y = math.floor(y * scale), width = width, height = height },
      path
    )
  else
    command = {
      'magick',
      view.source .. '[0]',
      '-crop',
      ('%dx%d+%d+%d'):format(width, height, math.floor(x), math.floor(y)),
      '+repage',
      'png:' .. path,
    }
  end

  -- ponytail: synchronous crops suit small plots; use cancellable jobs for large documents.
  local result = vim.system(command, { text = true }):wait(5000)
  if result.code ~= 0 then
    vim.fn.delete(path)
    vim.notify(
      'Preview crop failed: ' .. (result.stderr or 'Renderer timed out'),
      vim.log.levels.ERROR
    )
    return
  end
  return path, 'png', width, height
end

local function change_view(action)
  local window = vim.api.nvim_get_current_win()
  local image =
    require('image').get_images({ window = window, buffer = vim.api.nvim_get_current_buf() })[1]
  local term = require('image/utils').term.get_size()
  if not image or not term or not image.rendered_geometry.width then
    return
  end

  local view = get_view(image, term.cell_width)
  if action == 'reset' then
    replace_source(image, view.source, view.format, view.width, view.height)
    image.geometry = vim.deepcopy(view.geometry)
    image.ignore_global_max_size, image.render_offset_top = view.ignore_max, view.offset
    views[image] = nil
    image:render()
    return
  end

  local zoom = math.max(0.125, math.min(16, view.zoom * (action.zoom or 1)))
  local scale = view.scale * zoom
  local info = vim.fn.getwininfo(window)[1]
  local width = math.min(
    view.width,
    math.max(1, math.floor((info.width - info.textoff) * term.cell_width / scale))
  )
  local height =
    math.min(view.height, math.max(1, math.floor((info.height - 1) * term.cell_height / scale)))
  local x =
    math.max(0, math.min(view.width - width, view.x + (action.x or 0) * term.cell_width / scale))
  local y =
    math.max(0, math.min(view.height - height, view.y + (action.y or 0) * term.cell_height / scale))
  local path, format, source_width, source_height = crop_view(view, scale, width, height, x, y)
  if not path then
    return
  end

  view.zoom, view.x, view.y = zoom, x, y
  replace_source(image, path, format, source_width, source_height)
  image.ignore_global_max_size = true
  image.render_offset_top = 0
  image:render({
    x = 0,
    y = 0,
    width = math.max(1, math.floor(width * scale / term.cell_width)),
    height = math.max(1, math.floor(height * scale / term.cell_height)),
  })
end

function M.setup()
  install_pdf_renderer()
  vim.api.nvim_create_autocmd('FileType', {
    group = vim.api.nvim_create_augroup('ImagePreviewKeys', { clear = true }),
    pattern = 'image_nvim',
    callback = function(event)
      local bindings = {
        ['+'] = { { zoom = 1.25 }, 'Zoom in' },
        ['-'] = { { zoom = 0.8 }, 'Zoom out' },
        h = { { x = -4 }, 'Scroll left' },
        j = { { y = 2 }, 'Scroll down' },
        k = { { y = -2 }, 'Scroll up' },
        l = { { x = 4 }, 'Scroll right' },
        ['0'] = { 'reset', 'Reset preview' },
      }
      for key, binding in pairs(bindings) do
        vim.keymap.set('n', key, function()
          change_view(binding[1])
        end, { buffer = event.buf, silent = true, desc = binding[2] })
      end
    end,
  })
end

return M
