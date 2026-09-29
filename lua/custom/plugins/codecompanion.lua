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
      background = { chat = { opts = { enabled = false } } },
      cli = {
        agent = 'codex',
        agents = { codex = { cmd = 'codex' } },
      },
      chat = {
        adapter = 'codex',
        keymaps = {
          close = {
            callback = function(chat)
              chat.ui:hide()
            end,
            description = 'Hide the chat buffer',
          },
        },
      },
    },
  },
  config = function(_, opts)
    local codecompanion = require 'codecompanion'
    codecompanion.setup(opts)

    -- ACP supports chat only; route inline entry points through the same chat adapter.
    codecompanion.inline = function(args)
      args = vim.tbl_extend('force', {}, args, { user_prompt = args.args })
      return codecompanion.chat(args)
    end

    local interactions = require 'codecompanion.interactions'
    interactions.inline = interactions.chat

    codecompanion.cmd = function(args)
      local context = require('codecompanion.utils.context').get(0, args)
      local function open_chat(prompt)
        if not prompt or vim.trim(prompt) == '' then
          return
        end

        return codecompanion.chat {
          context = context,
          user_prompt = 'Suggest a Neovim Ex command for the following request. Do not execute it.\n\n' .. prompt,
        }
      end

      if vim.trim(args.args or '') == '' then
        return vim.ui.input({ prompt = 'Neovim command: ' }, open_chat)
      end

      return open_chat(args.args)
    end
  end,
  keys = {
    { '<leader>ac', '<cmd>CodeCompanionChat Toggle<CR>', desc = 'AI: toggle chat' },
    { '<leader>aa', '<cmd>CodeCompanionActions<CR>', mode = { 'n', 'x' }, desc = 'AI: actions' },
    { '<leader>ai', ':CodeCompanion<CR>', mode = { 'n', 'x' }, desc = 'AI: edit with Codex chat' },
    { '<leader>as', ':CodeCompanionChat Add<CR>', mode = 'x', desc = 'AI: add selection to chat' },
  },
}
