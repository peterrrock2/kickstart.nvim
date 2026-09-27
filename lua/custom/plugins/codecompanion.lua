return {
  'olimorris/codecompanion.nvim',
  version = '19.26.0',
  cmd = { 'CodeCompanion', 'CodeCompanionChat', 'CodeCompanionActions', 'CodeCompanionCmd', 'CodeCompanionCLI', 'CodeCompanionCodeReview' },
  dependencies = { 'nvim-lua/plenary.nvim', 'nvim-treesitter/nvim-treesitter' },
  opts = {
    display = {
      chat = { show_context = false },
    },
    adapters = {
      acp = {
        codex = function()
          return require('codecompanion.adapters').extend('codex', {
            defaults = { auth_method = 'chat-gpt' },
          })
        end,
      },
    },
    interactions = {
      chat = { adapter = 'codex' },
    },
  },
  keys = {
    { '<leader>ac', '<cmd>CodeCompanionChat Toggle<CR>', desc = 'AI: toggle chat' },
    { '<leader>aa', '<cmd>CodeCompanionActions<CR>', mode = { 'n', 'x' }, desc = 'AI: actions' },
    { '<leader>ai', ':CodeCompanion<CR>', mode = { 'n', 'x' }, desc = 'AI: inline edit' },
    { '<leader>as', ':CodeCompanionChat Add<CR>', mode = 'x', desc = 'AI: add selection to chat' },
  },
}
