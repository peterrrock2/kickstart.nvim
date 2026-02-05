-- You can add your own plugins here or in other files in this directory!
--  I promise not to create any merge conflicts in this directory :)
--
-- See the kickstart.nvim README for more information
return {
  { 'catppuccin/nvim', name = 'catppuccin', priority = 1000 },
  { 'rebelot/kanagawa.nvim', name = 'kanagawa', priority = 1000 },
  {
    'norcalli/nvim-colorizer.lua',
    config = function()
      require('colorizer').setup()
    end,
  },
  require 'custom.plugins.auto-session',
  require 'custom.plugins.bufferline',
  require 'custom.plugins.copilot',
  require 'custom.plugins.git-conflict',
  require 'custom.plugins.lazy-dev',
  require 'custom.plugins.lualine',
  require 'custom.plugins.onedark',
  require 'custom.plugins.nvim-lspconfig',
  require 'custom.plugins.toggleterm',
  require 'custom.plugins.treesitter-context',
  require 'custom.plugins.virt-column',
  require 'custom.plugins.which-key',
  -- {
  --   dir = '~/Desktop/GlowDeep.nvim',
  --   config = function()
  --     require('GlowDeep').setup()
  --
  --     vim.keymap.set('n', '<leader>glo', ':lua require("GlowDeep").setup()<CR>', { desc = 'Load Glow Deep' })
  --   end,
  -- },
}
