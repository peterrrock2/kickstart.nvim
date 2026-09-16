-- Run: nvim --clean --headless -i NONE -l tests/image_preview_cache.lua
vim.opt.runtimepath:append(vim.fn.stdpath('config'))
local frames = require('custom.image_preview_cache')
local source = vim.fn.tempname() .. '.png'
assert(vim.system({ 'magick', '-size', '800x600', 'gradient:red-blue', source }):wait().code == 0)

local view = { source = source, format = 'png', width = 800, height = 600, modified = 1 }
local viewport = {
  width = 200,
  height = 96,
  x = 0,
  y = 200,
  columns = 25,
  rows = 6,
  cell_width = 8,
  cell_height = 16,
  step = 32,
}
local system, jobs = vim.system, 0
vim.system = function(...)
  jobs = jobs + 1
  return system(...)
end

local function warm_cache()
  assert(
    vim.wait(10000, function()
      local cache = view.cache
      if cache.job then
        return false
      end
      for _, frame in ipairs(cache.wanted) do
        if not cache.frames[frame.key] then
          return false
        end
      end
      return true
    end, 5),
    'Neighbouring frames did not finish rendering'
  )
  assert(vim.tbl_count(view.cache.frames) <= 11, 'Frame cache exceeded its bound')
end

local initial = assert(frames.get(view, viewport))
warm_cache()
assert(jobs == 11, 'Expected the current frame and five neighbours in each direction')
viewport.y = viewport.y + viewport.step
local next_frame = assert(frames.get(view, viewport))
assert(jobs == 11 and next_frame.path ~= initial.path, 'Scrolling down missed the prefetched frame')
viewport.y = viewport.y - viewport.step
assert(
  frames.get(view, viewport).path == initial.path and jobs == 11,
  'Scrolling back missed the cache'
)

for offset = -5, 5 do
  viewport.y = 200 + offset * viewport.step
  assert(frames.get(view, viewport))
end
assert(jobs == 11, 'The fifth neighbour was not prefetched in both directions')
viewport.y = 200

local started = vim.uv.hrtime()
for _ = 1, 100 do
  viewport.y = viewport.y + viewport.step
  assert(frames.get(view, viewport))
  viewport.y = viewport.y - viewport.step
  assert(frames.get(view, viewport))
end
local elapsed = (vim.uv.hrtime() - started) / 1e6
assert(jobs == 11, 'Cached scrolling launched an image processing job')
print(('200 cached scroll steps: %.1f ms, 0 image processing jobs'):format(elapsed))

viewport.columns, viewport.rows = 50, 12
local enlarged = assert(frames.get(view, viewport))
assert(enlarged.path ~= initial.path and enlarged.width == 400, 'Zoom reused a stale frame')
warm_cache()
assert(vim.fn.filereadable(initial.path) == 0, 'Evicted frame was not deleted')

viewport.width, viewport.height, viewport.columns, viewport.rows = 160, 80, 20, 5
local resized = assert(frames.get(view, viewport))
assert(resized.path ~= enlarged.path and resized.width == 160, 'Resize reused a stale frame')
warm_cache()
viewport.columns, viewport.cell_width = 10, 16
local font_resized = assert(frames.get(view, viewport))
assert(
  font_resized.columns == 10 and font_resized.width == 160,
  'Font resize reused stale cell geometry'
)
warm_cache()
view.modified = 2
local refreshed = assert(frames.get(view, viewport))
assert(refreshed.path ~= font_resized.path, 'Source modification reused a stale frame')
warm_cache()

viewport.y = 0
assert(frames.get(view, viewport))
warm_cache()
assert(vim.tbl_count(view.cache.frames) == 6, 'Top edge generated duplicate or invalid frames')
viewport.y = view.height - viewport.height
assert(frames.get(view, viewport))
warm_cache()
assert(vim.tbl_count(view.cache.frames) == 6, 'Bottom edge generated duplicate or invalid frames')

-- Closing a view while prefetch runs must not leave files or resurrect its cache.
viewport.y = 200
local last_frame = assert(frames.get(view, viewport))
assert(vim.wait(10000, function()
  return view.cache.job ~= nil
end, 1))
local pending = view.cache.job
frames.clear(view)
pending.process:wait(5000)
vim.wait(20, function()
  return false
end)
assert(view.cache == nil, 'A finished prefetch resurrected the closed cache')
assert(vim.fn.filereadable(last_frame.path) == 0, 'Closing the view left a cached frame')
assert(vim.fn.filereadable(pending.frame.path) == 0, 'Cancelled prefetch left a frame')
vim.system = system
vim.fn.delete(source)
print('PASS: prefetch, cache hits, invalidation, bounds, edge clamping, and cancellation')
