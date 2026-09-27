return {
  'nvim-treesitter/nvim-treesitter-context',
  opts = {
    max_lines = 2,
    separator = '-',
    on_attach = function(buffer)
      return vim.bo[buffer].filetype ~= 'bigfile'
    end,
  },
}
