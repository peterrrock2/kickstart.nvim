return {
  'zbirenbaum/copilot.lua',
  cmd = 'Copilot',
  event = 'InsertEnter',
  config = function()
    require('copilot').setup {
      suggestion = {
        auto_trigger = true,
        keymap = {
          accept = '<S-C-Tab>',
          accept_word = '<S-C-Right>',
          accept_line = '<S-Tab>',
          next = '<M-]>',
          prev = '<M-[>',
          dismiss = '<C-e>',
        },
      },
    }
  end,
}
