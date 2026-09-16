-- Run: nvim --clean --headless -i NONE -l tests/image_preview_zoom.lua
vim.opt.runtimepath:append(vim.fn.stdpath('config'))
local cache = require('custom.image_preview_cache')
local source = vim.fn.tempname() .. '.png'
assert(vim.system({ 'magick', '-size', '800x600', 'gradient:red-blue', source }):wait().code == 0)
local view = { source = source, format = 'png', width = 800, height = 600, modified = 1 }
local viewport =
  { x = 0, y = 0, width = 800, height = 600, scaled_width = 1000, scaled_height = 750 }
local system, waits, processes = vim.system, 0, 0
vim.system = function(...)
  processes = processes + 1
  local process = system(...)
  local wait = process.wait
  process.wait = function(self, ...)
    waits = waits + 1
    return wait(self, ...)
  end
  return process
end
local completed = {}
local function ready(plan)
  assert(plan)
  completed[#completed + 1] = plan
  cache.commit(view, plan)
end
cache.get(view, viewport, ready)
assert(waits == 0, 'Zoom blocks Neovim while rendering cold tiles')
assert(#completed == 0, 'Cold rendering completed inside the input handler')
assert(processes == 1, 'Zoom decodes the source separately for every tile')
local first_request = view.cache.demand
cache.get(view, viewport, ready)
assert(
  view.cache.demand == first_request and processes == 1,
  'Repeated input restarted the same zoom'
)
viewport.scaled_width, viewport.scaled_height = 1250, 938
cache.get(view, viewport, ready)
assert(vim.wait(10000, function()
  return #completed > 0 and completed[#completed].scaled_width == 1250
end, 5))
local old_plan = completed[#completed]
local completed_count = #completed
assert(waits == 0, 'Background rendering performed a blocking wait')

-- A cached view completes immediately without rendering pixels again.
local before = processes
cache.get(view, viewport, ready)
assert(
  #completed == completed_count + 1 and processes == before,
  'Cached rendering became asynchronous or did extra work'
)

completed_count = #completed

-- Returning to a previous zoom reuses its files within the shared cache budget.
viewport.scaled_width, viewport.scaled_height = 1000, 750
cache.get(view, viewport, ready)
assert(vim.wait(10000, function()
  return #completed == completed_count + 1
end, 5))
viewport.scaled_width, viewport.scaled_height = 1250, 938
before = processes
completed_count = #completed
cache.get(view, viewport, ready)
assert(
  #completed == completed_count + 1
    and processes == before
    and completed[#completed].tiles[1] == old_plan.tiles[1],
  'Returning to a previous zoom regenerated cached pixels'
)

completed_count = #completed

-- A render failure leaves the displayed cache and its files intact.
local previous_source = view.source
view.source = source .. '.missing'
local notify, notices = vim.notify, {}
vim.notify = function(message)
  notices[#notices + 1] = message
end
cache.get(view, viewport, ready)
assert(vim.wait(10000, function()
  return view.cache.demand == nil
end, 5))
vim.notify = notify
view.source = previous_source
assert(
  #completed == completed_count and #notices == 1,
  'Failed zoom was displayed or failed silently'
)
for _, tile in ipairs(old_plan.tiles) do
  assert(
    view.cache.visible[tile.key] and vim.fn.filereadable(tile.path) == 1,
    'Failed zoom removed the current view'
  )
end

-- Reset/close cancels in-flight work and discards partial output.
viewport.scaled_width, viewport.scaled_height = 1600, 1200
cache.get(view, viewport, ready)
local pending = view.cache.demand
assert(pending, 'Missing cancellable demand request')
cache.clear(view)
assert(vim.wait(10000, function()
  return pending.finished
end, 5))
assert(#completed == completed_count and view.cache == nil, 'Cancelled zoom resurrected a view')
for _, tile in ipairs(pending.missing) do
  assert(vim.fn.filereadable(tile.path) == 0, 'Cancelled zoom left a tile file')
end
for _, tile in ipairs(old_plan.tiles) do
  assert(vim.fn.filereadable(tile.path) == 0, 'Closing retained old tile files')
end
vim.system = system
vim.fn.delete(source)
print('PASS: nonblocking batched zoom, latest request wins, cached views, and cancellation')
