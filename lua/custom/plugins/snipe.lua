return {
  'leath-dub/snipe.nvim',
  dependencies = {
    'akinsho/bufferline.nvim', -- so it's available to reference
  },
  keys = {
    {
      'gb',
      function()
        require('snipe').open_buffer_menu()
      end,
      desc = 'Open Snipe buffer menu',
    },
  },
  opts = {

    ui = {
      position = 'topleft',
      persist_tags = false,
    },
    hints = {
      -- Charaters to use for hints (NOTE: make sure they don't collide with the navigation keymaps)
      ---@type string
      dictionary = '1234567890qwertyuiop;',
      -- Character used to disambiguate tags when 'persist_tags' option is set
      prefix_key = '.',
    },
    preselect_current = true,
    sort = function(buffers)
      local bufferline = require 'bufferline.state'
      local id_to_buffer = {}
      for _, buf in ipairs(buffers) do
        id_to_buffer[buf.id] = buf
      end

      local sorted = {}
      if bufferline and bufferline.components then
        for _, component in ipairs(bufferline.components) do
          local buf = id_to_buffer[component.id]
          if buf then
            table.insert(sorted, buf)
            id_to_buffer[component.id] = nil
          end
        end
      end

      -- Add any remaining buffers that aren't in bufferline.components
      for _, buf in pairs(id_to_buffer) do
        table.insert(sorted, buf)
      end

      return sorted
    end,
  },
}
