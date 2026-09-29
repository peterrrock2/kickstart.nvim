return {
  'MeanderingProgrammer/render-markdown.nvim',
  ft = { 'markdown', 'python', 'rust' },
  cmd = 'RenderMarkdown',
  dependencies = { 'nvim-treesitter/nvim-treesitter', 'nvim-tree/nvim-web-devicons' },
  opts = {
    enabled = false,
    overrides = {
      preview = { enabled = true },
    },
  },
}
