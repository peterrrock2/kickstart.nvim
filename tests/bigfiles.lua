-- Run: NVIM_LOG_FILE=/tmp/nvim-bigfiles-test.log nvim --headless -n -i NONE -c 'luafile tests/bigfiles.lua'
local directory = vim.fn.tempname()
vim.fn.mkdir(directory, 'p')

local function open(name, lines)
  local path = directory .. '/' .. name
  vim.fn.writefile(lines, path)
  local start = vim.uv.hrtime()
  vim.cmd.edit(vim.fn.fnameescape(path))
  print(('%s: %d lines, %s, %.0f ms'):format(name, vim.api.nvim_buf_line_count(0), vim.bo.filetype, (vim.uv.hrtime() - start) / 1e6))
end

local function check_bigfiles()
  local default_wrap = vim.go.wrap
  open('moderate.json', { '[' .. string.rep('123,', 60000) .. '456]' })
  assert(vim.bo.filetype == 'json', 'moderate JSON lost its filetype')
  assert(vim.api.nvim_buf_line_count(0) > 60000, 'JSON did not expand before detection')
  assert(vim.treesitter.highlighter.active[vim.api.nvim_get_current_buf()], 'normal JSON highlighting did not start')
  vim.cmd 'bwipeout!'

  open('large.json', { '[' .. string.rep('123,', 400000) .. '456]' })
  assert(vim.api.nvim_buf_line_count(0) > 400000, 'large JSON did not expand')
  assert(vim.bo.filetype == 'bigfile', 'large JSON did not use bigfile mode')
  assert(not vim.treesitter.highlighter.active[vim.api.nvim_get_current_buf()], 'Tree-sitter attached to large JSON')
  assert(#vim.lsp.get_clients { bufnr = 0 } == 0, 'LSP attached to a bigfile')
  assert(vim.b.completion == false, 'completion remained enabled')
  assert(vim.wo.foldmethod == 'manual', 'expensive folding remained enabled')

  -- Older sessions can restore parser-backed options after bigfile detection.
  local session = directory .. '/stale-session.vim'
  vim.fn.writefile({
    'setlocal filetype=json',
    "setlocal indentexpr=v:lua.require'nvim-treesitter'.indentexpr()",
    'setlocal foldmethod=expr',
    'setlocal wrap',
    'doautoall SessionLoadPost',
  }, session)
  vim.cmd.source(vim.fn.fnameescape(session))
  assert(vim.bo.filetype == 'bigfile', 'session restore bypassed bigfile protection')
  assert(not vim.treesitter.highlighter.active[vim.api.nvim_get_current_buf()], 'session attached Tree-sitter')
  assert(not require('rainbow-delimiters.lib').buffers[vim.api.nvim_get_current_buf()], 'session attached rainbow delimiters')
  assert(#vim.lsp.get_clients { bufnr = 0 } == 0, 'session attached an LSP to a bigfile')
  assert(vim.bo.indentexpr == '', 'session restored Tree-sitter indentation')
  assert(vim.wo.foldmethod == 'manual', 'session restored expensive folding')
  assert(not vim.wo.wrap, 'session restored wrapping of enormous lines')
  assert(vim.go.wrap == default_wrap, 'bigfile changed the default wrapping for other files')
  vim.cmd 'bwipeout!'

  open('large.py', vim.fn['repeat']({ '# An ordinary line of generated Python data.' }, 50000))
  assert(vim.bo.filetype == 'bigfile', 'non-JSON large file did not use bigfile mode')
  assert(not vim.treesitter.highlighter.active[vim.api.nvim_get_current_buf()], 'Tree-sitter attached to large Python')
  assert(require('kickstart.plugins.conform').opts.format_on_save(vim.api.nvim_get_current_buf()) == nil, 'format-on-save remained enabled')
end

vim.schedule(function()
  local ok, message = xpcall(check_bigfiles, debug.traceback)
  vim.cmd 'bwipeout!'
  vim.fn.delete(directory, 'rf')
  if not ok then
    print(message)
    vim.cmd 'cquit 1'
  end

  print 'PASS: full-config JSON formatting order and bigfile feature suppression'
  vim.cmd 'qa!'
end)
