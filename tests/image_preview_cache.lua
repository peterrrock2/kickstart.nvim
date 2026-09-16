-- Run: nvim --clean --headless -i NONE -l tests/image_preview_cache.lua
vim.opt.runtimepath:append(vim.fn.stdpath('config'))
local released = {}
package.loaded['image/backends/kitty/helpers'] = {
  write_graphics = function(payload)
    assert(payload.action == 'd' and payload.display_delete == 'I')
    released[payload.image_id] = true
  end,
}
local tiles = require('custom.image_preview_cache')
local source = vim.fn.tempname() .. '.png'
assert(vim.system({ 'magick', '-size', '800x600', 'gradient:red-blue', source }):wait().code == 0)

local view = { source = source, format = 'png', width = 800, height = 600, modified = 1 }
local viewport =
  { width = 200, height = 96, x = 0, y = 200, scaled_width = 800, scaled_height = 600 }
local system, jobs = vim.system, 0
vim.system = function(...)
  jobs = jobs + 1
  return system(...)
end

local function render()
  local plan
  tiles.get(view, viewport, function(result)
    plan = result
    tiles.commit(view, plan)
  end)
  assert(
    vim.wait(10000, function()
      return plan ~= nil
    end, 5),
    'Tiles did not render'
  )
  return plan
end

local function warm_cache()
  assert(
    vim.wait(10000, function()
      local cache = view.cache
      if cache.job then
        return false
      end
      for key in pairs(cache.wanted) do
        if not cache.tiles[key] then
          return false
        end
      end
      return true
    end, 5),
    'Neighbouring tiles did not finish rendering'
  )
end

local initial = render()
warm_cache()
assert(jobs == 5, 'Expected one batch for two visible tiles plus four neighbours')
viewport.y = viewport.y + 32
local shifted = render()
assert(shifted.tiles[1] == initial.tiles[1] and jobs == 5, 'Pan duplicated overlapping pixels')
viewport.x = 100
render()
assert(jobs == 5, 'Horizontal pan missed prefetched tiles')

local started = vim.uv.hrtime()
for _ = 1, 100 do
  viewport.y = viewport.y + 32
  render()
  viewport.y = viewport.y - 32
  render()
end
local elapsed = (vim.uv.hrtime() - started) / 1e6
assert(jobs == 5, 'Cached scrolling launched an image processing job')
print(('200 cached scroll steps: %.1f ms, 0 image processing jobs'):format(elapsed))

-- Tiles use the same sampling grid even at fractional zoom.
viewport.scaled_width, viewport.scaled_height = 1037, 778
viewport.x, viewport.y, viewport.width, viewport.height = 0, 0, 512, 128
local enlarged = render()
assert(
  vim.fn.filereadable(initial.tiles[1].path) == 1,
  'Zoom discarded reusable tiles below budget'
)
local combined, reference = vim.fn.tempname() .. '.rgba', vim.fn.tempname() .. '.rgba'
assert(system({
  'magick',
  enlarged.tiles[1].path,
  enlarged.tiles[2].path,
  '+append',
  '-crop',
  '512x128+0+0',
  '+repage',
  '-depth',
  '8',
  'RGBA:' .. combined,
}):wait().code == 0)
assert(system({
  'magick',
  source,
  '+repage',
  '-define',
  'distort:viewport=512x128+0+0',
  '-distort',
  'AffineProjection',
  ('%.17g,0,0,%.17g,0,0'):format(1037 / 800, 778 / 600),
  '+repage',
  '-depth',
  '8',
  'RGBA:' .. reference,
}):wait().code == 0)
assert(
  vim.deep_equal(vim.fn.readfile(combined, 'b'), vim.fn.readfile(reference, 'b')),
  'Independent tiles have seams or use different sampling origins'
)
for _, path in ipairs({ combined, reference }) do
  vim.fn.delete(path)
end

warm_cache()
local before = jobs
viewport.width = 400
render()
assert(jobs == before, 'Viewport resize regenerated unchanged tiles')
view.modified = 2
local refreshed = render()
assert(refreshed.tiles[1].path ~= enlarged.tiles[1].path, 'Source edit reused stale tiles')
assert(vim.fn.filereadable(enlarged.tiles[1].path) == 0, 'Source edit retained old files')
assert(
  vim.fn.filereadable(initial.tiles[1].path) == 0,
  'Source edit kept stale tiles at another zoom'
)
warm_cache()

viewport.x = viewport.scaled_width - viewport.width
viewport.y = viewport.scaled_height - viewport.height
local edge = render()
for _, tile in ipairs(edge.tiles) do
  assert(tile.width > 0 and tile.width <= 256 and tile.height > 0 and tile.height <= 256)
  assert(tile.x + tile.width <= viewport.scaled_width)
  assert(tile.y + tile.height <= viewport.scaled_height)
end

-- Closing while prefetch runs must not leave files or resurrect the cache.
assert(vim.wait(10000, function()
  return view.cache.job ~= nil
end, 1))
local paused_job = view.cache.job
local jobs_before_pause = jobs
tiles.pause_prefetch(view)
paused_job.process:wait(5000)
vim.wait(20, function()
  return false
end)
assert(
  view.cache.paused and not view.cache.job and jobs == jobs_before_pause,
  'Hidden preview kept prefetching'
)
assert(vim.fn.filereadable(paused_job.tile.path) == 0, 'Paused prefetch retained partial output')
tiles.commit(view, edge)
assert(vim.wait(10000, function()
  return view.cache.job ~= nil
end, 1))
local pending = view.cache.job
local cache = view.cache
local paths = {}
for _, tile in pairs(cache.tiles) do
  paths[#paths + 1] = tile.path
end
paths[#paths + 1] = pending.tile.path
tiles.clear(view)
pending.process:wait(5000)
vim.wait(20, function()
  return false
end)
assert(view.cache == nil and cache.bytes == 0, 'Finished prefetch resurrected the closed cache')
for _, path in ipairs(paths) do
  assert(vim.fn.filereadable(path) == 0, 'Closing left a cached tile')
end

-- A small source zoomed far in can fill the cache without huge source decodes.
viewport = { width = 256, height = 256, x = 0, y = 0, scaled_width = 4096, scaled_height = 4096 }
local first_path, first_id
for index = 0, 139 do
  viewport.x, viewport.y = (index % 16) * 256, math.floor(index / 16) * 256
  local plan = render()
  plan.tiles[1].image_id = 50000 + index
  first_path = first_path or plan.tiles[1].path
  first_id = first_id or plan.tiles[1].image_id
  assert(view.cache.bytes <= 32 * 1024 * 1024, 'Cache exceeded budget with evictable tiles')
  assert(vim.fn.filereadable(plan.tiles[1].path) == 1, 'Eviction removed visible tiles')
end
assert(vim.fn.filereadable(first_path) == 0, 'Oldest tiles were not evicted')
assert(released[first_id], 'Eviction retained the decoded tile in the terminal')
warm_cache()
assert(view.cache.bytes <= 32 * 1024 * 1024, 'Prefetch exceeded the cache target')
tiles.clear(view)
vim.system = system
vim.fn.delete(source)
print('PASS: tile reuse, prefetch, sampling grid, invalidation, bounds, eviction, and cancellation')
