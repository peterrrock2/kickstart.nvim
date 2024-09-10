-- You can add your own plugins here or in other files in this directory!
--  I promise not to create any merge conflicts in this directory :)
--
-- See the kickstart.nvim README for more information
return {
  { 'catppuccin/nvim', name = 'catppuccin', priority = 1000 },
  { 'rebelot/kanagawa.nvim', name = 'kanagawa', priority = 1000 },
  { 'navarasu/onedark.nvim', name = 'onedark', priority = 1000 },
  { 'nvim-lualine/lualine.nvim', name = 'lualine', dependencies = { 'nvim-tree/nvim-web-devicons' } },
  { 'akinsho/toggleterm.nvim', version = '*', config = true },
  { 'akinsho/bufferline.nvim', version = '*', dependencies = 'nvim-tree/nvim-web-devicons' },
  {
    'rmagatti/auto-session',
    lazy = false,
    dependencies = {
      'nvim-telescope/telescope.nvim', -- Only needed if you want to use session lens
    },
    opts = {
      suppressed_dirs = { '~/', '~/Projects', '~/Downloads', '/' },
    },
  },
}
