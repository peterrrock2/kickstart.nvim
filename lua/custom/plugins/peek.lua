return {
  'toppair/peek.nvim',
  ft = { 'markdown' },
  build = 'deno task --quiet build:fast',
  config = function()
    local peek = require 'peek'
    peek.setup { app = 'browser' }

    vim.api.nvim_create_user_command('PeekOpen', peek.open, {})
    vim.api.nvim_create_user_command('PeekClose', peek.close, {})
    vim.api.nvim_create_user_command('PeekToggle', function()
      if peek.is_open() then
        peek.close()
      else
        peek.open()
      end
    end, {})
  end,
}
