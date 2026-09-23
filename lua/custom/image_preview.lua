local M = {}
local cache = require('custom.image_preview_cache')
local views = setmetatable({}, { __mode = 'k' })
local tiles = require('custom.image_preview_tiles')
local pdf = require('custom.image_preview_pdf')
local change_view

local function validate_terminal_detection()
  local utils = require('image/utils')
  for _, entry in ipairs({ { utils.term, 'get_tty' }, { utils.tmux, 'get_pane_tty' } }) do
    local module, name = entry[1], entry[2]
    local detect = module[name]
    module[name] = function()
      local path = detect()
      local stat = path and path:sub(1, 1) == '/' and vim.uv.fs_stat(path)
      -- Failed `tty`/tmux commands return text that image.nvim would open as a filename.
      if stat and stat.type == 'char' then
        return path
      end
    end
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
  local format = processor.get_format(source)
  local document = format == 'pdf' and pdf.read_document(source) or nil
  local dimensions = document and document.pages[1] or processor.get_dimensions(source)
  document = document and #document.pages > 1 and document or nil
  if view then
    view.scale = view.scale * view.width / dimensions.width
    view.width, view.height = dimensions.width, dimensions.height
    view.format, view.document = format, document
    view.page = document and math.min(view.page or 1, #document.pages) or nil
    view.modified = modified
    return view, true
  end

  local scale = image.rendered_geometry.width * cell_width / dimensions.width
  if document then
    local info = vim.fn.getwininfo(image.window)[1]
    scale = math.max(1, info.width - info.textoff) * cell_width / document.width
  end
  view = {
    source = source,
    width = dimensions.width,
    height = dimensions.height,
    format = format,
    document = document,
    anchor = image.cropped_path,
    geometry = vim.deepcopy(image.geometry),
    ignore_max = image.ignore_global_max_size,
    offset = image.render_offset_top,
    modified = modified,
    scale = scale,
    zoom = 1,
    x = 0,
    y = 0,
  }
  views[image] = view
  return view
end

local function replace_source(image, path, format, width, height)
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

local function discard_view(image, view)
  -- image.nvim can retain hijacked image objects after their windows stop displaying them.
  replace_source(image, view.source, view.format, view.width, view.height)
  image.geometry = vim.deepcopy(view.geometry)
  image.ignore_global_max_size, image.render_offset_top = view.ignore_max, view.offset
  cache.clear(view)
  views[image] = nil
end

local function is_preview_visible(image)
  return image.window
    and vim.api.nvim_win_is_valid(image.window)
    and vim.api.nvim_win_get_tabpage(image.window) == vim.api.nvim_get_current_tabpage()
    and vim.api.nvim_win_get_buf(image.window) == image.buffer
end

local function install_tile_renderer()
  local backend = require('image/backends/kitty')
  local render, clear = backend.render, backend.clear
  backend.render = function(image, ...)
    local view = views[image]
    if view and view.plan then
      local ok, err = pcall(tiles.draw, image, view, view.plan, ...)
      if not ok then
        image.resize_hash = 'preview:' .. image.path
        error(err, 0)
      end
      if not view.tiled then
        image.is_rendered = false
        clear(image.id, true)
        require('image/backends/kitty/helpers').write_graphics({
          action = 'd',
          display_delete = 'I',
          image_id = image.internal_id,
          quiet = 2,
        })
        view.tiled = true
      end
      image.is_rendered = true
      backend.state.images[image.id] = image
      cache.commit(view, view.plan)
      return
    end

    if not view or not view.resetting then
      local result = render(image, ...)
      if not view and image.is_rendered and image.source_format == 'pdf' and image.window then
        vim.schedule(function()
          if
            not views[image]
            and is_preview_visible(image)
            and vim.bo[image.buffer].filetype == 'image_nvim'
          then
            vim.api.nvim_win_call(image.window, function()
              change_view({ refresh = true })
            end)
          end
        end)
      end
      return result
    end
    local ok, err = pcall(render, image, ...)
    if not ok then
      image.resize_hash = 'preview:' .. image.path
      error(err, 0)
    end
    if image.is_rendered then
      cache.clear(view)
      views[image] = nil
    end
  end
  backend.clear = function(id, shallow)
    for _, image in pairs(backend.state.images) do
      if not id or image.id == id then
        local view = views[image]
        if view then
          if is_preview_visible(image) then
            cache.pause_prefetch(view)
            tiles.hide(view)
          else
            discard_view(image, view)
          end
        end
        -- Native clear removes placements but retains decoded image data in the terminal.
        tiles.release_image(image)
      end
    end
    return clear(id, shallow)
  end
end

change_view = function(action)
  local window = vim.api.nvim_get_current_win()
  local image =
    require('image').get_images({ window = window, buffer = vim.api.nvim_get_current_buf() })[1]
  local term = require('image/utils').term.get_size()
  if not image or not term or not image.rendered_geometry.width then
    return
  end

  local view, source_changed = get_view(image, term.cell_width)
  if not view then
    return
  end
  local resetting = action == 'reset'
  local info = vim.fn.getwininfo(window)[1]
  if type(action) == 'table' and action.refresh and not view.document then
    return
  end
  if type(action) == 'table' and action.page then
    if not view.document then
      return
    end
    local page =
      math.max(1, math.min(#view.document.pages, (view.page or 1) + action.page * vim.v.count1))
    view.y = view.document.pages[page].y
    action = { refresh = true }
    vim.api.nvim_echo({ { ('PDF page %d / %d'):format(page, #view.document.pages) } }, false, {})
  end
  if action == 'reset' and view.document then
    cache.cancel(view)
    view.scale = math.max(1, info.width - info.textoff) * term.cell_width / view.document.width
    action = { zoom = 1 / view.zoom }
    view.x, view.y = 0, view.document.pages[view.page or 1].y
  end
  if action == 'reset' then
    cache.cancel(view)
    view.resetting = true
    view.zoom, view.x, view.y = 1, 0, 0
    replace_source(image, view.source, view.format, view.width, view.height)
    image.geometry = vim.deepcopy(view.geometry)
    image.ignore_global_max_size, image.render_offset_top = view.ignore_max, view.offset
    view.plan = nil
    image:render()
    return
  end

  local count = vim.v.count1
  local zoom = math.max(0.125, math.min(16, view.zoom * (action.zoom or 1)))
  local scale = view.scale * zoom
  local dimensions = view.document or view
  local scaled_width = math.max(1, math.floor(dimensions.width * scale + 0.5))
  local scaled_height = math.max(1, math.floor(dimensions.height * scale + 0.5))
  local width = math.min(scaled_width, math.max(1, info.width - info.textoff) * term.cell_width)
  local height = math.min(scaled_height, math.max(1, info.height - 1) * term.cell_height)
  local source_x, source_y = view.x, view.y
  if view.document and view.plan and action.zoom and not resetting then
    local previous_scale = view.scale * view.zoom
    source_x = source_x + view.plan.width / (2 * previous_scale) - width / (2 * scale)
    source_y = source_y + view.plan.height / (2 * previous_scale) - height / (2 * scale)
  end
  local x = math.max(
    0,
    math.min(
      scaled_width - width,
      math.floor(source_x * scale + 0.5) + count * (action.x or 0) * term.cell_width
    )
  )
  local y = math.max(
    0,
    math.min(
      scaled_height - height,
      math.floor(source_y * scale + 0.5) + count * (action.y or 0) * term.cell_height
    )
  )
  local plan = view.plan
  local same_size = not plan
    or (
      plan.width == width
      and plan.height == height
      and plan.scaled_width == scaled_width
      and plan.scaled_height == scaled_height
    )
  if
    not action.zoom
    and not action.refresh
    and not source_changed
    and same_size
    and x == math.floor(view.x * scale + 0.5)
    and y == math.floor(view.y * scale + 0.5)
  then
    return
  end

  if view.resetting then
    image.pending_transform_key = nil
    view.tiled = false
    view.resetting = false
  end
  local columns, rows = math.ceil(width / term.cell_width), math.ceil(height / term.cell_height)
  view.zoom, view.x, view.y = zoom, x / scale, y / scale
  view.page = view.document and pdf.page_at(view.document, (y + height / 2) / scale) or nil
  cache.get(view, {
    width = width,
    height = height,
    x = x,
    y = y,
    scaled_width = scaled_width,
    scaled_height = scaled_height,
  }, function(plan)
    if views[image] ~= view then
      return
    end
    view.plan = plan
    -- Let image.nvim determine visibility and bounds; the backend draws the actual tiles.
    replace_source(
      image,
      plan.tiles[1] and plan.tiles[1].path or view.anchor,
      'png',
      columns * term.cell_width,
      rows * term.cell_height
    )
    image.ignore_global_max_size = true
    image.render_offset_top = 0
    -- Leave height headroom so aspect-ratio rounding cannot add a column and trigger a resize.
    image.geometry =
      vim.tbl_extend('force', image.geometry, { x = 0, y = 0, width = columns, height = rows + 1 })
    -- image.nvim restores this view on focus gain; do not draw into another tmux window.
    if not image.global_state.disable_decorator_handling then
      image:render()
    end
  end)
end

function M.setup()
  validate_terminal_detection()
  pdf.setup()
  install_tile_renderer()
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
          discard_view(image, view)
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
        ['<ScrollWheelDown>'] = { { y = 2 }, 'Scroll down' },
        ['<ScrollWheelUp>'] = { { y = -2 }, 'Scroll up' },
        l = { { x = 4 }, 'Scroll right' },
        ['0'] = { 'reset', 'Reset preview' },
        [']p'] = { { page = 1 }, 'Next PDF page' },
        ['[p'] = { { page = -1 }, 'Previous PDF page' },
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
