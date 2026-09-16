-- Run: nvim --clean --headless -i NONE -l tests/image_preview_scheduling.lua
vim.opt.runtimepath:append(vim.fn.stdpath('config'))
local cache = require('custom.image_preview_cache')
local system, jobs = vim.system, {}
-- Control renderer completion independently of key input to reproduce held-key starvation.
vim.system = function(command, _, callback)
  local job = { command = command, callback = callback }
  function job:kill()
    self.killed = true
  end
  function job:finish()
    for _, value in ipairs(self.command) do
      local path = value:match('^PNG32:(.*)$')
      if path then
        vim.fn.writefile({ 'tile' }, path)
      end
    end
    self.callback({ code = self.killed and 143 or 0, stderr = '' })
    vim.wait(5, function()
      return false
    end)
  end
  jobs[#jobs + 1] = job
  return job
end
local view = { source = '/preview.png', modified = 1, format = 'png', width = 4096, height = 4096 }
local viewport =
  { x = 0, y = 0, width = 128, height = 128, scaled_width = 4096, scaled_height = 4096 }
local displayed = {}
local function ready(plan)
  displayed[#displayed + 1] = plan
  cache.commit(view, plan)
end
cache.get(view, viewport, ready)
jobs[1]:finish()
assert(#displayed == 1)
local prefetch = assert(jobs[2], 'Prefetch was not started')
viewport.y = 32
cache.get(view, viewport, ready)
assert(not prefetch.killed, 'Cached scrolling cancelled useful prefetch')
viewport.x = 256
cache.get(view, viewport, ready)
assert(not prefetch.killed and jobs[#jobs] == prefetch, 'Scrolling restarted a needed prefetch')
prefetch:finish()
assert(displayed[#displayed].x == 256, 'Finished prefetch did not satisfy the waiting scroll')

-- Crossing tile boundaries faster than a render finishes must still make progress.
viewport.x, viewport.y = 0, 1024
cache.get(view, viewport, ready)
local active = jobs[#jobs]
local count = #displayed
for step = 1, 10 do
  viewport.y = 1024 + step * 32
  cache.get(view, viewport, ready)
end
assert(not active.killed, 'Held scrolling restarted its active render')
assert(jobs[#jobs] == active, 'Held scrolling spawned competing renders')
active:finish()
assert(#displayed > count, 'No visible progress while scrolling remained held')
local latest = jobs[#jobs]
latest:finish()
assert(displayed[#displayed].y == viewport.y, 'The newest scroll position was lost')

-- Repeated zoom input keeps one running render and one latest request.
viewport.scaled_width, viewport.scaled_height = 5000, 5000
cache.get(view, viewport, ready)
active = jobs[#jobs]
count = #displayed
for size = 5100, 6000, 100 do
  viewport.scaled_width, viewport.scaled_height = size, size
  cache.get(view, viewport, ready)
end
assert(not active.killed and jobs[#jobs] == active, 'Held zoom starved its renderer')
active:finish()
assert(#displayed > count, 'Held zoom made no visible progress')
jobs[#jobs]:finish()
assert(displayed[#displayed].scaled_width == 6000, 'The newest zoom was lost')
cache.clear(view)
for _, job in ipairs(jobs) do
  if job.killed then
    job:finish()
  end
end
vim.system = system
print('PASS: cached scrolling preserves prefetch; held scrolling and zoom keep making progress')
