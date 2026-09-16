return {
  'akinsho/bufferline.nvim',
  config = function()
    -- Read existing order files until each session has been saved with native persistence.
    vim.api.nvim_create_autocmd('SessionLoadPost', {
      callback = function()
        if vim.g.BufferlinePositions or vim.v.this_session == '' then
          return
        end
        local filename = vim.fs.basename(vim.v.this_session) .. '.txt'
        local path = vim.fs.joinpath(vim.fn.stdpath 'data', 'bufferline_order', filename)
        if vim.fn.filereadable(path) == 1 then
          vim.g.BufferlinePositions = vim.json.encode(vim.fn.readfile(path))
        end
      end,
    })

    require('bufferline').setup {
      options = {
        mode = 'buffers',
        always_show_bufferline = false,
        separator_style = 'slant',
        persist_buffer_sort = true,
        sort_by = 'id',
        hover = { enabled = true, delay = 100, reveal = { 'close' } },
        offsets = {
          { filetype = 'neo-tree', text = 'File Explorer', highlight = 'Directory', separator = true },
        },
      },
    }
  end,
}
