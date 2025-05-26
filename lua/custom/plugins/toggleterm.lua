return {
  'akinsho/toggleterm.nvim',
  config = function()
    require('toggleterm').setup {
      open_mapping = [[<M-i>]],
      direction = 'float',
      shell = 'zsh',
      float_opts = {
        border = 'curved',
        width = function()
          local terminal_width = vim.o.columns
          return math.floor(terminal_width * 0.7)
        end,
        height = function()
          local terminal_height = vim.o.lines
          return math.floor(terminal_height * 0.6)
        end,
        row = function()
          local terminal_height = vim.o.lines
          return math.floor((terminal_height * 0.4) / 2)
        end,
        col = function()
          local terminal_width = vim.o.columns
          return math.floor((terminal_width * 0.3) / 2)
        end,
        title_pos = 'center',
      },
    }
  end,
}
