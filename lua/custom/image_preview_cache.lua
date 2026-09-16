local M = {}

function M.build_pdf_command(path, width, height, crop, output)
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

local function build_frame(view, viewport, y)
  local frame = {
    source = view.source,
    format = view.format,
    source_width = view.width,
    source_height = view.height,
    x = math.floor(viewport.x),
    y = math.floor(math.max(0, math.min(view.height - viewport.height, y))),
    crop_width = viewport.width,
    crop_height = viewport.height,
    columns = viewport.columns,
    rows = viewport.rows,
    width = viewport.columns * viewport.cell_width,
    height = viewport.rows * viewport.cell_height,
  }
  frame.key = table.concat({
    frame.source,
    view.modified,
    frame.format,
    frame.source_width,
    frame.source_height,
    frame.x,
    frame.y,
    frame.crop_width,
    frame.crop_height,
    frame.width,
    frame.height,
    frame.columns,
    frame.rows,
  }, ':')
  return frame
end

local function build_command(frame)
  if frame.format == 'pdf' then
    local scale_x = frame.width / frame.crop_width
    local scale_y = frame.height / frame.crop_height
    return M.build_pdf_command(
      frame.source,
      math.ceil(frame.source_width * scale_x),
      math.ceil(frame.source_height * scale_y),
      {
        x = math.floor(frame.x * scale_x),
        y = math.floor(frame.y * scale_y),
        width = frame.width,
        height = frame.height,
      },
      frame.path
    )
  end

  return {
    'magick',
    frame.source .. '[0]',
    '-crop',
    ('%dx%d+%d+%d'):format(frame.crop_width, frame.crop_height, frame.x, frame.y),
    '+repage',
    '-resize',
    ('%dx%d!'):format(frame.width, frame.height),
    'png:' .. frame.path,
  }
end

local function cancel_job(cache)
  if cache.job then
    cache.job.process:kill(15)
    cache.job = nil
  end
end

function M.clear(view)
  local cache = view.cache
  if not cache then
    return
  end
  cache.closed = true
  cancel_job(cache)
  for _, frame in pairs(cache.frames) do
    vim.fn.delete(frame.path)
  end
  view.cache = nil
end

local function fill_cache(cache)
  if cache.closed then
    return
  end

  local wanted = {}
  for _, frame in ipairs(cache.wanted) do
    wanted[frame.key] = true
  end
  for key, frame in pairs(cache.frames) do
    if not wanted[key] then
      vim.fn.delete(frame.path)
      cache.frames[key] = nil
    end
  end
  if cache.job then
    if wanted[cache.job.frame.key] then
      return
    end
    cancel_job(cache)
  end

  for _, frame in ipairs(cache.wanted) do
    if not cache.frames[frame.key] then
      frame.path = vim.fn.tempname() .. '.png'
      local job = { frame = frame }
      cache.job = job
      job.process = vim.system(
        build_command(frame),
        { text = true, timeout = 5000 },
        vim.schedule_wrap(function(result)
          if cache.closed or cache.job ~= job then
            vim.fn.delete(frame.path)
            return
          end
          cache.job = nil
          if result.code ~= 0 then
            vim.fn.delete(frame.path)
            return -- Retry on demand; speculative failures should not interrupt editing.
          end
          cache.frames[frame.key] = frame
          fill_cache(cache)
        end)
      )
      return
    end
  end
end

function M.get(view, viewport)
  local cache = view.cache or { frames = {} }
  view.cache = cache
  local wanted = { build_frame(view, viewport, viewport.y) }
  for steps = 1, 5 do
    wanted[#wanted + 1] = build_frame(view, viewport, viewport.y + steps * viewport.step)
    wanted[#wanted + 1] = build_frame(view, viewport, viewport.y - steps * viewport.step)
  end

  local frame = cache.frames[wanted[1].key]
  if not frame then
    cancel_job(cache)
    frame = wanted[1]
    frame.path = vim.fn.tempname() .. '.png'
    -- ponytail: a cache miss blocks for one frame; use asynchronous demand rendering for large files.
    local result = vim.system(build_command(frame), { text = true }):wait(5000)
    if result.code ~= 0 then
      vim.fn.delete(frame.path)
      vim.notify(
        'Preview crop failed: ' .. (result.stderr or 'Renderer timed out'),
        vim.log.levels.ERROR
      )
      return
    end
    cache.frames[frame.key] = frame
  end

  cache.wanted = wanted
  -- Evict only after the caller has replaced the displayed source with this frame.
  vim.schedule(function()
    fill_cache(cache)
  end)
  return frame
end

return M
