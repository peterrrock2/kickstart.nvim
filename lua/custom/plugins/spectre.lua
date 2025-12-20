return {
  'nvim-pack/nvim-spectre',
  dependencies = {
    'nvim-lua/plenary.nvim',
    -- optional, for nice icons:
    'nvim-tree/nvim-web-devicons',
  },
  cmd = { 'Spectre' },
  keys = {
    {
      '<leader>S',
      function()
        require('spectre').toggle()
      end,
      desc = 'Toggle Spectre',
    },
    {
      '<leader>SR',
      function()
        require('spectre').open()
      end,
      desc = 'Spectre: Search/Replace (project)',
    },
    {
      '<leader>sw',
      function()
        require('spectre').open_visual { select_word = true }
      end,
      desc = 'Spectre: Search word',
    },
    {
      '<leader>sf',
      function()
        require('spectre').open_file_search { select_word = true }
      end,
      desc = 'Spectre: File only',
    },
  },
  opts = {
    -- examples; tweak to taste
    color_devicons = true,
    live_update = false, -- live write to file while editing replace text
    is_block_ui_break = true,
    highlight = { ui = 'Search', search = 'IncSearch', replace = 'DiffText' },
    mapping = {
      -- keep defaults; you can override if you want
    },
  },
  config = function(_, opts)
    require('spectre').setup(opts)
  end,
}
