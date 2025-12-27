return {
  '3rd/image.nvim',
  build = false,

  opts = {
    backend = 'kitty',
    processor = 'magick_cli',
    integrations = {
      markdown = {
        enabled = true,
        clear_in_insert_mode = false,
        download_remote_images = true,
        only_render_image_at_cursor = false,
        only_render_image_at_cursor_mode = 'popup',
        floating_windows = false,
        filetypes = { 'markdown', 'vimwiki' },
      },
      neorg = { enabled = true, filetypes = { 'norg' } },
      typst = { enabled = true, filetypes = { 'typst' } },
      html = { enabled = false },
      css = { enabled = false },
    },

    max_width = nil,
    max_height = nil,
    max_width_window_percentage = nil,
    max_height_window_percentage = nil,
    scale_factor = 3.0,

    window_overlap_clear_enabled = true,
    window_overlap_clear_ft_ignore = {
      'cmp_menu',
      'cmp_docs',
      'snacks_notif',
      'scrollview',
      'scrollview_sign',
    },

    editor_only_render_when_focused = true,
    tmux_show_only_in_active_window = true,

    hijack_file_patterns = { '*.png', '*.jpg', '*.jpeg', '*.gif', '*.webp', '*.avif' },
  },

  config = function(_, opts)
    require('image').setup(opts)

    local function kitty_delete_all_images()
      local esc = '\27'
      local seq
      if vim.env.TMUX ~= nil then
        -- tmux passthrough; inner ESC\ must be escaped as ESC ESC \
        seq = esc .. 'Ptmux;' .. esc .. esc .. '_Ga=d' .. esc .. esc .. '\\' .. esc .. '\\'
      else
        seq = esc .. '_Ga=d' .. esc .. '\\'
      end
      -- write directly to the TUI
      io.stdout:write(seq)
      io.stdout:flush()
    end

    -- Clear via plugin (best effort) + hard delete (works even if plugin state is confused)
    local function clear_images_everywhere()
      pcall(function()
        require('image').clear()
      end)
      kitty_delete_all_images()
    end

    vim.api.nvim_create_autocmd({ 'BufLeave', 'WinLeave', 'VimLeavePre' }, {
      callback = clear_images_everywhere,
    })

    -- Optional manual key
    vim.keymap.set('n', '<leader>ic', clear_images_everywhere, { desc = 'Clear images' })
  end,
}
