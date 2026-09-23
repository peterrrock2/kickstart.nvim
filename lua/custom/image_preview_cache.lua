local M = {}
local renderer = require('custom.image_preview_tiles')
local pdf = require('custom.image_preview_pdf')
local TILE_SIZE = 256
-- Estimated RGBA pixels plus PNG files; visible tiles stay pinned even above this target.
local CACHE_BYTES = 32 * 1024 * 1024

local function build_regions(view, viewport)
  if not view.document then
    return { { x = 0, y = 0, width = viewport.scaled_width, height = viewport.scaled_height } }
  end
  local scale_x = viewport.scaled_width / view.document.width
  local scale_y = viewport.scaled_height / view.document.height
  local regions = {}
  for _, page in ipairs(view.document.pages) do
    local x, y = math.floor(page.x * scale_x + 0.5), math.floor(page.y * scale_y + 0.5)
    regions[#regions + 1] = {
      page = page.number,
      x = x,
      y = y,
      width = math.max(1, math.floor((page.x + page.width) * scale_x + 0.5) - x),
      height = math.max(1, math.floor((page.y + page.height) * scale_y + 0.5) - y),
    }
  end
  return regions
end

local function build_tile(view, viewport, region, column, row)
  local x, y = column * TILE_SIZE, row * TILE_SIZE
  return {
    key = viewport.signature .. ':' .. (region.page or 1) .. ':' .. column .. ':' .. row,
    source_key = viewport.source_key,
    source = view.source,
    format = view.format,
    page = region.page,
    source_width = view.width,
    source_height = view.height,
    scaled_width = region.width,
    scaled_height = region.height,
    crop_x = x,
    crop_y = y,
    x = region.x + x,
    y = region.y + y,
    width = math.min(TILE_SIZE, region.width - x),
    height = math.min(TILE_SIZE, region.height - y),
  }
end

local function build_plan_tiles(view, plan)
  local tiles = {}
  for _, region in ipairs(build_regions(view, plan)) do
    local left = math.max(0, math.floor((plan.x - region.x) / TILE_SIZE) - 1)
    local top = math.max(0, math.floor((plan.y - region.y) / TILE_SIZE) - 1)
    local right = math.min(
      math.ceil(region.width / TILE_SIZE) - 1,
      math.floor((plan.x + plan.width - 1 - region.x) / TILE_SIZE) + 1
    )
    local bottom = math.min(
      math.ceil(region.height / TILE_SIZE) - 1,
      math.floor((plan.y + plan.height - 1 - region.y) / TILE_SIZE) + 1
    )
    for row = top, bottom do
      for column = left, right do
        tiles[#tiles + 1] = build_tile(view, plan, region, column, row)
      end
    end
  end
  return tiles
end

local function build_raster_command(tiles)
  -- These temporary PNGs favour fast lossless encoding over smaller files.
  local command =
    { 'magick', tiles[1].source .. '[0]', '+repage', '-define', 'png:compression-level=1' }
  for _, tile in ipairs(tiles) do
    -- Clone one decoded source and use a global sampling grid to avoid tile seams.
    vim.list_extend(command, {
      '(',
      '+clone',
      '-define',
      ('distort:viewport=%dx%d+%d+%d'):format(tile.width, tile.height, tile.x, tile.y),
      '-distort',
      'AffineProjection',
      ('%.17g,0,0,%.17g,0,0'):format(
        tile.scaled_width / tile.source_width,
        tile.scaled_height / tile.source_height
      ),
      '+repage',
      '-depth',
      '8',
      '-write',
      'PNG32:' .. tile.path,
      '+delete',
      ')',
    })
  end
  command[#command + 1] = 'null:'
  return command
end

local function build_command(tile)
  if tile.format ~= 'pdf' then
    return build_raster_command({ tile })
  end
  return pdf.build_command(
    tile.source,
    tile.scaled_width,
    tile.scaled_height,
    { x = tile.crop_x, y = tile.crop_y, width = tile.width, height = tile.height },
    tile.path,
    tile.page
  )
end

local function cancel_job(cache)
  if cache.job then
    cache.job.process:kill(15)
    cache.job = nil
  end
end

function M.pause_prefetch(view)
  if view.cache then
    view.cache.paused = true
    cancel_job(view.cache)
  end
end

local function cancel_demand(cache)
  cache.queued = nil
  if cache.demand then
    cache.demand.process:kill(15)
    cache.demand = nil
  end
end

function M.cancel(view)
  local cache = view.cache
  if cache then
    cancel_job(cache)
    cancel_demand(cache)
  end
end

local function remove_tile(cache, tile)
  renderer.release(tile)
  vim.fn.delete(tile.path)
  cache.tiles[tile.key] = nil
  cache.bytes = cache.bytes - tile.bytes
end

function M.clear(view)
  local cache = view.cache
  if not cache then
    return
  end
  cache.closed = true
  M.cancel(view)
  renderer.hide(view)
  for _, tile in pairs(cache.tiles) do
    remove_tile(cache, tile)
  end
  view.cache = nil
end

local function store_tile(cache, tile)
  tile.bytes = tile.width * tile.height * 4 + vim.fn.getfsize(tile.path)
  cache.clock = cache.clock + 1
  tile.used = cache.clock
  cache.tiles[tile.key] = tile
  cache.bytes = cache.bytes + tile.bytes
end

local function trim_cache(cache, source_key, reserve)
  local unused = {}
  for key, tile in pairs(cache.tiles) do
    if not cache.visible[key] and not (cache.demand and cache.demand.keys[key]) then
      if tile.source_key ~= source_key then
        remove_tile(cache, tile)
      elseif not reserve or not cache.wanted[key] then
        unused[#unused + 1] = tile
      end
    end
  end
  table.sort(unused, function(a, b)
    return a.used < b.used
  end)
  for _, tile in ipairs(unused) do
    if cache.bytes <= CACHE_BYTES - (reserve or 0) then
      break
    end
    remove_tile(cache, tile)
  end
end

local function prefetch(cache)
  if cache.closed or cache.paused or cache.job or cache.demand then
    return
  end
  while #cache.queue > 0 do
    local tile = table.remove(cache.queue, 1)
    if not cache.tiles[tile.key] then
      -- Leave room for decoded pixels and the PNG without evicting visible tiles.
      local reserve = tile.width * tile.height * 8
      trim_cache(cache, tile.source_key, reserve)
      if cache.bytes + reserve > CACHE_BYTES then
        return
      end
      tile.path = vim.fn.tempname() .. '.png'
      local job = { tile = tile }
      cache.job = job
      job.process = vim.system(
        build_command(tile),
        { text = true, timeout = 5000 },
        vim.schedule_wrap(function(result)
          if cache.closed or cache.job ~= job then
            vim.fn.delete(tile.path)
            return
          end
          cache.job = nil
          if result.code == 0 and cache.wanted[tile.key] then
            store_tile(cache, tile)
            trim_cache(cache, tile.source_key)
          else
            vim.fn.delete(tile.path)
          end
          local queued = cache.queued
          cache.queued = nil
          if queued then
            M.get(queued.view, queued.viewport, queued.ready)
          else
            prefetch(cache)
          end
        end)
      )
      return
    end
  end
end

local function finish_demand(cache, request, result)
  request.finished = true
  if cache.closed or cache.demand ~= request or result.code ~= 0 then
    for _, tile in ipairs(request.missing) do
      vim.fn.delete(tile.path)
    end
  else
    for _, tile in ipairs(request.missing) do
      store_tile(cache, tile)
    end
  end
  if cache.closed or cache.demand ~= request then
    return
  end

  local queued = cache.queued
  cache.demand, cache.queued = nil, nil
  local presented = false
  if queued then
    M.get(queued.view, queued.viewport, function(plan)
      presented = true
      queued.ready(plan)
    end)
  end
  if result.code ~= 0 then
    vim.notify(
      'Preview tiles failed: ' .. (result.stderr or 'Renderer timed out'),
      vim.log.levels.ERROR
    )
  elseif not presented then
    -- Show completed work while the newest request renders, so held keys keep moving.
    request.ready(request.plan)
  end
end

local function render_demand(cache, request, index)
  local tile = request.missing[index]
  local is_pdf = tile.format == 'pdf'
  local command = is_pdf and build_command(tile) or build_raster_command(request.missing)
  request.process = vim.system(
    command,
    { text = true, timeout = 10000 },
    vim.schedule_wrap(function(result)
      if result.code == 0 and cache.demand == request and is_pdf and index < #request.missing then
        render_demand(cache, request, index + 1)
      else
        finish_demand(cache, request, result)
      end
    end)
  )
end

function M.get(view, viewport, ready)
  local cache = view.cache or { tiles = {}, bytes = 0, clock = 0, visible = {} }
  view.cache = cache
  local source_key = table.concat({ view.source, view.modified, view.format }, ':')
  local signature = table.concat({ source_key, viewport.scaled_width, viewport.scaled_height }, ':')
  local pending = cache.demand and cache.demand.plan
  if
    pending
    and pending.signature == signature
    and pending.x == viewport.x
    and pending.y == viewport.y
    and pending.width == viewport.width
    and pending.height == viewport.height
  then
    cache.demand.ready = ready
    cache.queued = nil
    return
  end
  local plan = vim.tbl_extend('force', viewport, {
    tiles = {},
    neighbours = {},
    signature = signature,
    source_key = source_key,
  })
  local request = { plan = plan, missing = {}, keys = {}, ready = ready }
  for _, tile in ipairs(build_plan_tiles(view, plan)) do
    if
      tile.x < plan.x + plan.width
      and tile.x + tile.width > plan.x
      and tile.y < plan.y + plan.height
      and tile.y + tile.height > plan.y
    then
      tile = cache.tiles[tile.key] or tile
      if not tile.path then
        request.missing[#request.missing + 1] = tile
      end
      cache.clock = cache.clock + 1
      tile.used = cache.clock
      request.keys[tile.key] = true
      plan.tiles[#plan.tiles + 1] = tile
    else
      plan.neighbours[#plan.neighbours + 1] = tile
    end
  end
  if #request.missing == 0 then
    cancel_demand(cache)
    ready(plan)
  elseif
    (cache.demand and cache.demand.plan.source_key == source_key)
    or (cache.job and request.keys[cache.job.tile.key])
  then
    cache.queued = { view = view, viewport = vim.deepcopy(viewport), ready = ready }
  else
    cancel_demand(cache)
    cancel_job(cache)
    for _, tile in ipairs(request.missing) do
      tile.path = vim.fn.tempname() .. '.png'
    end
    cache.demand = request
    render_demand(cache, request, 1)
  end
end

function M.commit(view, plan)
  local cache = view.cache
  cache.paused = false
  cache.visible, cache.wanted = {}, {}
  for _, tile in ipairs(plan.tiles) do
    cache.visible[tile.key] = true
    cache.wanted[tile.key] = true
  end
  cache.queue = vim.list_extend({}, plan.neighbours)
  for _, tile in ipairs(plan.neighbours) do
    cache.wanted[tile.key] = true
  end
  if cache.job and not cache.wanted[cache.job.tile.key] then
    cancel_job(cache)
  end
  trim_cache(cache, plan.source_key)
  vim.schedule(function()
    prefetch(cache)
  end)
end

return M
