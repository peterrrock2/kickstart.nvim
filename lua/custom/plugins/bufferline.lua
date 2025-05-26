return {
  'akinsho/bufferline.nvim',
  config = function()
    require('bufferline').setup {
      options = {
        view = 'tabs',
        always_show_bufferline = false,
        separator_style = 'slant',
        hover = {
          enabled = true,
          delay = 100,
          reveal = { 'close' },
        },
        offsets = {
          {
            filetype = 'neo-tree',
            text = 'File Explorer',
            highlight = 'Directory',
            separator = true,
          },
        },
      },
    }
  end,
}
