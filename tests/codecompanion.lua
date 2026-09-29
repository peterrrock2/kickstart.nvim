-- Run: NVIM_LOG_FILE=/tmp/nvim-codecompanion.log nvim -n --clean --headless -i NONE -l tests/codecompanion.lua
vim.opt.runtimepath:prepend(vim.fn.getcwd())
vim.opt.runtimepath:append(vim.fn.stdpath('data') .. '/site')
vim.opt.runtimepath:append(vim.fn.stdpath('data') .. '/lazy/codecompanion.nvim')
vim.opt.runtimepath:append(vim.fn.stdpath('data') .. '/lazy/plenary.nvim')

local spec = dofile 'lua/custom/plugins/codecompanion.lua'
spec.config(nil, spec.opts)

local config = require 'codecompanion.config'
local adapter = require('codecompanion.adapters').resolve(config.interactions.chat.adapter)
assert(adapter.name == 'codex' and adapter.type == 'acp')
assert(config.interactions.cli.agent == 'codex')
assert(config.interactions.cli.agents.codex.cmd == 'codex')
assert(not config.interactions.background.chat.opts.enabled)

local requests = {}
require('codecompanion.interactions.chat').new = function(args)
  requests[#requests + 1] = args
  return {}
end
require('codecompanion.http').new = function()
  error('Unexpected HTTP request')
end

vim.api.nvim_buf_set_name(0, '/tmp/codecompanion-routing.lua')
vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'local value = 1', 'print(value)' })
vim.bo.filetype = 'lua'
vim.api.nvim_buf_set_mark(0, '<', 1, 0, {})
vim.api.nvim_buf_set_mark(0, '>', 2, 11, {})

vim.cmd 'CodeCompanion simplify this buffer'
assert(requests[#requests].messages[1].content == 'simplify this buffer')
assert(requests[#requests].auto_submit)

vim.ui.input = function(_, callback)
  callback('Rename value to count')
end
vim.cmd "'<,'>CodeCompanion"
local request = requests[#requests]
assert(request.messages[1].content == 'Rename value to count')
assert(request.buffer_context.is_visual)
assert(request.buffer_context.code:find('local value = 1', 1, true))

vim.cmd "'<,'>CodeCompanion /tests"
request = requests[#requests]
assert(request.messages[#request.messages].content:find('local value = 1', 1, true))
assert(request.auto_submit)

local context = require('codecompanion.utils.context').get(0)
local palette = require 'codecompanion.action_palette'
local found_inline = false
for _, item in ipairs(palette.get_cached_items(context)) do
  if item.name == 'Inline prompt' then
    found_inline = true
    palette.resolve(item, context)
    request = requests[#requests]
    assert(request.messages[#request.messages].content == 'Rename value to count')
  end
end
assert(found_inline, 'Inline action was not checked')

vim.cmd 'CodeCompanionCmd sort these lines'
assert(requests[#requests].messages[1].content:find('Do not execute it.', 1, true))
assert(requests[#requests].messages[1].content:find('sort these lines', 1, true))
vim.cmd 'CodeCompanionCmd'
assert(requests[#requests].messages[1].content:find('Rename value to count', 1, true))

local request_count = #requests
vim.ui.input = function(_, callback)
  callback(nil)
end
vim.cmd 'CodeCompanion'
vim.cmd 'CodeCompanionCmd'
assert(#requests == request_count, 'Cancelled input should not create a chat')

print 'CodeCompanion Codex routing checks passed'
vim.cmd 'qa!'
