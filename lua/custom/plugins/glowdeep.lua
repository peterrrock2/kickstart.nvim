return {
  -- dir = '~/Documents/glowdeep.nvim/', -- absolute path to your local repo
  'GlowTheme/glowdeep.nvim',
  name = 'glowdeep.nvim',
  priority = 1000,
  config = function()
    require('glowdeep').setup {
      style = 'dark',
      transparent = false,
    }
    vim.cmd.colorscheme 'glowdeep'
  end,
}
