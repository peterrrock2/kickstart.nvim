-- Run: NVIM_LOG_FILE=/tmp/nvim-json-test.log nvim --clean --headless -n -i NONE -l tests/json_reformat.lua
vim.opt.runtimepath:prepend(vim.fn.getcwd())
vim.opt.runtimepath:append(vim.fn.stdpath 'data' .. '/lazy/snacks.nvim')
local directory = vim.fn.tempname()
vim.fn.mkdir(directory, 'p')
local notices = {}
vim.notify = function(message)
  notices[#notices + 1] = message
end

require('custom.json_reformat').setup { min_line_length = 100, max_bytes = 2 * 1024 * 1024 }
require('snacks').setup { bigfile = { enabled = true, notify = false, size = 4096 } }
vim.cmd 'filetype on'

local function open(name, text)
  vim.cmd 'enew!'
  local path = directory .. '/' .. name
  vim.fn.writefile(vim.split(text, '\n', { plain = true }), path)
  vim.cmd.edit(vim.fn.fnameescape(path))
  return table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), '\n'), path
end

local function unchanged(name, text)
  local output = open(name, text)
  assert(output == text, name .. ': original content changed')
  assert(not vim.bo.modified, name .. ': unchanged buffer marked modified')
end

local payload = '"padding":[' .. string.rep('123,', 50) .. '456]'
local source = '{"integer":9007199254740993,"text":"spaces  and \\"quotes\\"",' .. payload .. '}'
local output, path = open('small.json', source)
assert(output:find('\n', 1, true), 'minified JSON did not expand')
assert(output:find('9007199254740993', 1, true), 'large integer changed')
assert(vim.bo.filetype == 'json', 'small expanded JSON did not get its normal filetype')
assert(vim.bo.modified, 'formatting must be visible as an unsaved change')
assert(vim.fn.readfile(path)[1] == source, 'opening the file wrote to disk')
vim.cmd 'undo'
assert(table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), '\n') == source, 'undo did not restore input')

output = open('later.json', '{\n\n\n' .. payload .. '\n}')
assert(#vim.split(output, '\n') > 10, 'long line after short leading lines was missed')

output = open('large.json', '[' .. string.rep('123,', 1400) .. '456]')
assert(output:find('\n', 1, true), 'large file was not expanded')
assert(vim.bo.filetype == 'bigfile', 'disk-size limit was lost after expanding JSON')
assert(vim.b.completion == false, 'bigfile did not disable completion')

unchanged('records.jsonl', source .. '\n' .. source)
unchanged('comments.jsonc', '// comment\n' .. source)
unchanged('notebook.ipynb', source)
unchanged('duplicate.json', '{"key":1,"key":2,' .. payload .. '}')
unchanged('escaped.json', '{"text":"\\u0061",' .. payload .. '}')
unchanged('overflow.json', '{"number":1e9999999999,' .. payload .. '}')
unchanged('invalid.json', '{' .. payload .. ', BROKEN}')
unchanged('comment-in-json.json', '// comment\n' .. source)
unchanged('trailing.json', source .. '\nBROKEN')
unchanged('stream.json', source .. '\n' .. source)
unchanged('formatted.json', '{\n  "small": true\n}')
unchanged('empty.json', '')
unchanged('ceiling.json', '{"text":"' .. string.rep('x', 2 * 1024 * 1024) .. '"}')

local system = vim.system
vim.system = function(command, opts)
  if command[2] == '--version' then
    return {
      wait = function()
        return { code = 0, stdout = 'jq-1.6\n' }
      end,
    }
  end
  return system(command, opts)
end
unchanged('old-jq.json', source)
vim.system = function(command, opts)
  if command[2] ~= '--version' then
    return {
      wait = function()
        return { code = 124, stdout = '{"partial":' }
      end,
    }
  end
  return system(command, opts)
end
unchanged('timeout.json', source)
vim.system = function()
  error 'jq executable missing'
end
unchanged('missing-jq.json', source)
vim.system = system

local confirm = vim.fn.confirm
vim.fn.confirm = function()
  return 1
end
output, path = open('exponent.json', '{"number":1e-05,' .. payload .. '}')
assert(output:find('\n', 1, true), 'confirmed lossy format did not expand the buffer')
assert(vim.bo.readonly, 'lossy format must require :w! to save')
assert(not pcall(vim.cmd.write), 'plain :w saved a lossy format')
assert(vim.fn.readfile(path)[1]:find('1e-05', 1, true), 'lossy format reached disk without :w!')
vim.cmd 'write!'
assert(vim.fn.readfile(path)[2]:find('0.00001', 1, true), ':w! did not save the lossy format')
vim.fn.confirm = confirm

vim.cmd 'bwipeout!'
vim.fn.delete(directory, 'rf')
print 'PASS: JSON preservation, failures, undo, exclusions, and bigfile detection after formatting'
