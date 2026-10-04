return {
  'MeanderingProgrammer/render-markdown.nvim',
  ft = { 'markdown', 'python', 'rust' },
  cmd = 'RenderMarkdown',
  dependencies = { 'nvim-treesitter/nvim-treesitter', 'nvim-tree/nvim-web-devicons' },
  opts = {
    enabled = false,
    overrides = {
      preview = { enabled = true },
      -- LSP hover floats, which is where docstring math from custom.docstring_hover is drawn.
      buftype = { nofile = { enabled = true, anti_conceal = { enabled = false } } },
    },
  },
}
