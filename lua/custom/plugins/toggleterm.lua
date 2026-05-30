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

    -- Make terminal buffers show up in bufferline and snipe (gb)
    vim.api.nvim_create_autocmd('TermOpen', {
      callback = function()
        vim.bo.buflisted = true
      end,
    })

    -- Full-window terminal in a new buffer (Alt+t)
    vim.keymap.set('n', '<M-S-t>', function()
      vim.cmd 'enew'
      vim.cmd 'terminal'
      vim.cmd 'startinsert'
    end, { desc = 'Open terminal in new full buffer' })

    -- Horizontal split terminal (Alt+S+h)
    vim.keymap.set('n', '<M-4>', function()
      vim.cmd 'split | terminal'
      vim.cmd 'startinsert'
    end, { desc = 'Open terminal in horizontal split' })

    -- Vertical split terminal (Alt+v) — 50% width
    vim.keymap.set('n', '<M-v>', function()
      vim.cmd(math.floor(vim.o.columns * 0.5) .. 'vsplit | terminal')
      vim.cmd 'startinsert'
    end, { desc = 'Open terminal in vertical split' })
  end,
}
