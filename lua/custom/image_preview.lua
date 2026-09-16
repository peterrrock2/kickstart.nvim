local M = {}
local frames = require('custom.image_preview_cache')
local views = setmetatable({}, { __mode = 'k' })
local pending_frames = setmetatable({}, { __mode = 'k' })

local function install_frame_swap()
  local backend = require('image/backends/kitty')
  local graphics = require('image/backends/kitty/helpers')
  local render = backend.render
  backend.render = function(image, ...)
    if not pending_frames[image] then
      return render(image, ...)
    end

    -- Allocate through image.nvim so the new id cannot collide with another image.
    local replacement = assert(require('image').from_file(image.path))
    local previous_id, was_rendered = image.internal_id, image.is_rendered
    image.is_rendered = false
    backend.clear(image.id, true) -- Invalidate the upload cache without erasing the old placement.
    image.internal_id = replacement.internal_id

    local ok, err = pcall(render, image, ...)
    local retired_id = previous_id
    if ok and image.is_rendered then
      pending_frames[image] = nil
    else
      retired_id = image.internal_id
      image.internal_id, image.is_rendered = previous_id, was_rendered
      image.resize_hash = 'preview:' .. image.path
    end
    graphics.write_graphics({ action = 'd', display_delete = 'I', image_id = retired_id, quiet = 2 })
    if not ok then
      error(err, 0)
    end
  end
end

local function install_pdf_renderer()
  local processor = require('image/processors/magick_cli')
  local transform = processor.transform
  processor.transform = function(path, request, output, callback)
    if request.source_format ~= 'pdf' then
      return transform(path, request, output, callback)
    end

    -- Rasterize vectors at the requested pixel size, including the initial view and reset.
    local command = frames.build_pdf_command(
      path,
      request.target_width,
      request.target_height,
      request.crop,
      output
    )
    vim.system(command, { text = true }, function(result)
      callback({ ok = result.code == 0, path = output, error = result.stderr })
    end)
  end
end

local function get_view(image, cell_width)
  local view = views[image]
  local source = view and view.source or image.original_path
  local stat = vim.uv.fs_stat(source)
  if not stat then
    vim.notify('Preview source is no longer available: ' .. source, vim.log.levels.WARN)
    return
  end
  local modified = table.concat({ stat.size, stat.mtime.sec, stat.mtime.nsec }, ':')
  if view and view.modified == modified then
    return view
  end

  local processor = image.global_state.processor
  local dimensions = processor.get_dimensions(source)
  if view then
    view.scale = view.scale * view.width / dimensions.width
    view.width, view.height = dimensions.width, dimensions.height
    view.format = processor.get_format(source)
    view.modified = modified
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
    modified = modified,
    scale = image.rendered_geometry.width * cell_width / dimensions.width,
    zoom = 1,
    x = 0,
    y = 0,
  }
  views[image] = view
  return view
end

local function replace_source(image, path, format, width, height)
  pending_frames[image] = true
  -- Keep cropped sources separate so image.nvim does not clone them into another window.
  image.original_path = path
  image.path, image.source_format = path, format
  image.image_width, image.image_height = width, height
  image.resized_path, image.cropped_path = path, path
  image.resize_hash, image.crop_hash = 'preview:' .. path, nil
  image.transform_key, image.transform_signature = nil, nil
  image.pending_transform_key = nil
  image.last_modified = vim.fn.getftime(image.original_path)
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
  if not view then
    return
  end
  if action == 'reset' then
    replace_source(image, view.source, view.format, view.width, view.height)
    image.geometry = vim.deepcopy(view.geometry)
    image.ignore_global_max_size, image.render_offset_top = view.ignore_max, view.offset
    image:render()
    frames.clear(view)
    views[image] = nil
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
  local columns, rows = require('image/utils').math.adjust_to_aspect_ratio(
    term,
    width,
    height,
    math.max(1, math.floor(width * scale / term.cell_width)),
    math.max(1, math.floor(height * scale / term.cell_height))
  )
  local frame = frames.get(view, {
    width = width,
    height = height,
    x = x,
    y = y,
    columns = columns,
    rows = rows,
    cell_width = term.cell_width,
    cell_height = term.cell_height,
    step = 2 * term.cell_height / scale,
  })
  if not frame then
    return
  end

  view.zoom, view.x, view.y = zoom, x, y
  if image.path ~= frame.path then
    replace_source(image, frame.path, 'png', frame.width, frame.height)
  end
  image.ignore_global_max_size = true
  image.render_offset_top = 0
  image:render({ x = 0, y = 0, width = frame.columns, height = frame.rows })
end

function M.setup()
  install_pdf_renderer()
  install_frame_swap()
  local group = vim.api.nvim_create_augroup('ImagePreviewKeys', { clear = true })
  vim.api.nvim_create_autocmd({ 'WinClosed', 'BufWipeout', 'VimLeavePre' }, {
    group = group,
    callback = function(event)
      for image, view in pairs(views) do
        if
          event.event == 'VimLeavePre'
          or (event.event == 'WinClosed' and image.window == tonumber(event.match))
          or (event.event == 'BufWipeout' and image.buffer == event.buf)
        then
          frames.clear(view)
          views[image] = nil
        end
      end
    end,
  })
  vim.api.nvim_create_autocmd('FileType', {
    group = group,
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
