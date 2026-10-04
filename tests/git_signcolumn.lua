-- Run: NVIM_LOG_FILE=/tmp/nvim-git-signcolumn.log nvim --headless -n -i NONE -c 'luafile tests/git_signcolumn.lua'
local function check_cancel_preview(source, source_window, sidebar_window)
  local path = vim.fn.tempname() .. '.png'
  vim.fn.writefile({ 'preview fixture' }, path)
  local image = require 'image'
  local from_file = image.from_file
  image.from_file = function()
    return { render = function() end }
  end
  vim.api.nvim_set_option_value('number', true, { win = source_window, scope = 'local' })
  local config = require('neo-tree').ensure_config()
  local state = {
    name = 'filesystem',
    winid = sidebar_window,
    current_position = 'right',
    config = config.filesystem.window.mappings.P.config,
    tree = {
      get_node = function()
        return { path = path }
      end,
    },
  }
  local preview = require 'neo-tree.sources.common.preview'
  preview.show(state)
  assert(preview.is_active(), 'Neo-tree preview did not open')
  assert(vim.bo[vim.api.nvim_win_get_buf(source_window)].filetype == 'image_nvim')
  assert(vim.wo[source_window].signcolumn == 'no' and not vim.wo[source_window].number)

  require('neo-tree.sources.common.commands').cancel(state)
  assert(vim.api.nvim_win_get_buf(source_window) == source, 'Escape did not restore the source buffer')
  assert(
    vim.wait(1000, function()
      return vim.wo[source_window].signcolumn == 'yes' and vim.wo[source_window].number and vim.wo[source_window].relativenumber
    end, 10),
    'Escape left source Git signs or line numbers hidden'
  )
  assert(vim.wo[sidebar_window].signcolumn == 'no', 'Escape changed the sidebar gutter')
  image.from_file = from_file
  vim.fn.delete(path)
end

local function check_signcolumn()
  local image = require 'image'
  local from_file = image.from_file
  image.from_file = function()
    return { render = function() end }
  end
  vim.cmd.enew()
  image.hijack_buffer '/tmp/signcolumn-preview.png'
  image.from_file = from_file
  assert(vim.wo.signcolumn == 'no', 'image preview did not reproduce the hidden gutter')

  vim.cmd.edit 'lua/kickstart/plugins/gitsigns.lua'
  local source = vim.api.nvim_get_current_buf()
  local source_window = vim.api.nvim_get_current_win()
  assert(vim.wo.signcolumn == 'yes', 'new source file inherited the hidden preview gutter')
  assert(vim.wo.number and vim.wo.relativenumber, 'new source file inherited hidden preview line numbers')
  vim.api.nvim_buf_set_lines(source, 0, 0, false, { '-- Unsaved Git sign regression check.' })
  assert(
    vim.wait(5000, function()
      local namespace = vim.api.nvim_get_namespaces().gitsigns_signs_
      if not namespace then
        return false
      end
      for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(source, namespace, 0, -1, { details = true })) do
        if mark[2] == 0 and mark[4].sign_hl_group == 'GitSignsAdd' then
          return true
        end
      end
      return false
    end, 20),
    'Gitsigns did not display the unsaved addition'
  )

  vim.cmd.vnew()
  vim.bo.buftype = 'nofile'
  vim.bo.filetype = 'neo-tree'
  vim.cmd 'setlocal signcolumn=no nonumber norelativenumber'
  local sidebar_window = vim.api.nvim_get_current_win()
  vim.api.nvim_set_option_value('signcolumn', 'no', { win = source_window, scope = 'local' })
  vim.api.nvim_set_option_value('number', false, { win = source_window, scope = 'local' })
  vim.api.nvim_set_option_value('relativenumber', false, { win = source_window, scope = 'local' })
  vim.api.nvim_exec_autocmds('SessionLoadPost', {})
  assert(vim.wo[source_window].signcolumn == 'yes', 'session restoration hid source Git signs')
  assert(vim.wo[source_window].number and vim.wo[source_window].relativenumber, 'session restoration hid source line numbers')
  assert(vim.wo[sidebar_window].signcolumn == 'no', 'session repair changed a sidebar gutter')
  assert(not vim.wo[sidebar_window].number and not vim.wo[sidebar_window].relativenumber, 'session repair enabled sidebar line numbers')
  check_cancel_preview(source, source_window, sidebar_window)
end

vim.schedule(function()
  local ok, message = xpcall(check_signcolumn, debug.traceback)
  if not ok then
    print(message)
    vim.cmd 'cquit 1'
  end

  print 'PASS: Git signs and line numbers survive preview Escape and session restoration; sidebar gutters remain hidden'
  vim.cmd 'qa!'
end)
