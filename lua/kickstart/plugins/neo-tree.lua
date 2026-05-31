-- Neo-tree is a Neovim plugin to browse the file system
-- https://github.com/nvim-neo-tree/neo-tree.nvim

return {
  'nvim-neo-tree/neo-tree.nvim',
  version = '*',
  dependencies = {
    'nvim-lua/plenary.nvim',
    'nvim-tree/nvim-web-devicons', -- not strictly required, but recommended
    'MunifTanjim/nui.nvim',
  },
  lazy = false,
  keys = {
    { '\\', ':Neotree reveal<CR>', desc = 'NeoTree reveal', silent = true },
  },
  opts = {
    -- By default neo-tree refuses to open files into a terminal window and
    -- falls back to vsplit. Remove "terminal" from the list so it will open
    -- normally into whatever window was last focused (even if it was a terminal).
    open_files_do_not_replace_types = { 'trouble', 'qf' },
    default_component_configs = {
      name = { use_git_status_colors = true },
      git_status = {
        symbols = {
          added = 'A',
          modified = 'M',
          deleted = 'D',
          renamed = 'R',
          untracked = '',
          ignored = 'I',
          unstaged = 'U',
          staged = 'S',
          conflict = 'X',
        },
        -- align = "right", -- uncomment to show badges on the right
      },
      modified = { symbol = '●', highlight = 'NeoTreeModified' },
    },

    filesystem = {
      window = {
        mappings = {
          ['\\'] = 'close_window',
        },
        position = 'right',
      },
    },
  },
}
