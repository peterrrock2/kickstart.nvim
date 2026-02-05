return {
  'akinsho/bufferline.nvim',
  config = function()
    local bufferline = require 'bufferline'

    -- Shared order index used by the custom sorter (path -> position)
    local ORDER_IDX = setmetatable({}, {
      __index = function()
        return nil
      end,
    })

    bufferline.setup {
      options = {
        -- IMPORTANT: use "buffers" not "tabs"
        mode = 'buffers', -- replaces the old "view" option
        always_show_bufferline = false,
        separator_style = 'slant',
        persist_buffer_sort = false, -- keeps manual moves during the session
        -- Custom sort: use the ORDER_IDX we fill when loading
        sort_by = function(a, b)
          local na = vim.loop.fs_realpath(vim.api.nvim_buf_get_name(a.id)) or vim.api.nvim_buf_get_name(a.id)
          local nb = vim.loop.fs_realpath(vim.api.nvim_buf_get_name(b.id)) or vim.api.nvim_buf_get_name(b.id)
          local ia = ORDER_IDX[na]
          local ib = ORDER_IDX[nb]
          if ia and ib then
            return ia < ib
          end
          if ia then
            return true
          end
          if ib then
            return false
          end
          -- fallback: original ordinal so it doesn't jump randomly
          return a.ordinal < b.ordinal
        end,
        hover = { enabled = true, delay = 100, reveal = { 'close' } },
        offsets = {
          { filetype = 'neo-tree', text = 'File Explorer', highlight = 'Directory', separator = true },
        },
      },
    }

    -- === Buffer Order Persistence ===
    local bufferline_order_dir = vim.fn.stdpath 'data' .. '/bufferline_order/'
    vim.fn.mkdir(bufferline_order_dir, 'p')

    local function get_order_file_path()
      local session_path = vim.v.this_session
      if not session_path or session_path == '' then
        return nil -- no session loaded -> stay blank
      end
      local filename = vim.fs and vim.fs.basename(session_path) or vim.fn.fnamemodify(session_path, ':t')
      return bufferline_order_dir .. filename .. '.txt'
    end

    local function save_bufferline_order()
      local path = get_order_file_path()
      if not path then
        vim.notify('Could not determine session name. Skipping save.', vim.log.levels.WARN)
        return
      end

      -- Use bufferline.state as it exists even if nothing is drawn yet
      local components = require('bufferline.state').components or {}
      local bufs = {}
      for _, comp in ipairs(components) do
        if vim.api.nvim_buf_is_valid(comp.id) then
          local name = vim.api.nvim_buf_get_name(comp.id)
          if name ~= '' then
            local real = vim.loop.fs_realpath(name) or name
            table.insert(bufs, real)
          end
        end
      end

      if #bufs == 0 then
        vim.notify('No named buffers to save.', vim.log.levels.WARN)
        return
      end

      vim.fn.writefile(bufs, path)
      vim.notify('Saved buffer order to ' .. path, vim.log.levels.INFO)
    end

    local function load_bufferline_order()
      local path = get_order_file_path()
      if not path or vim.fn.filereadable(path) == 0 then
        return
      end

      local files = vim.fn.readfile(path)
      if #files == 0 then
        return
      end

      -- 1) Ensure buffers exist, are loaded, and listed
      local items = {}
      for _, f in ipairs(files) do
        if vim.fn.filereadable(f) == 1 then
          local bufnr = vim.fn.bufadd(f) -- create a buffer handle if missing
          vim.bo[bufnr].buflisted = true -- Bufferline only shows listed buffers
          items[#items + 1] = { bufnr = bufnr, path = vim.loop.fs_realpath(f) or f }
        end
      end

      -- 2) Rebuild ORDER_IDX using real paths
      for k in pairs(ORDER_IDX) do
        ORDER_IDX[k] = nil
      end
      for i, it in ipairs(items) do
        ORDER_IDX[it.path] = i
      end

      -- 3) Nudge Bufferline after the UI settles
      vim.schedule(function()
        -- force Bufferline to re-evaluate the comparator at least once
        pcall(vim.cmd, 'silent! bnext | silent! bprev')

        -- if available in your version, call a direct refresh; otherwise fallback to redraw
        local ok, bl = pcall(require, 'bufferline')
        if ok and type(bl.refresh) == 'function' then
          pcall(bl.refresh)
        end
        vim.cmd 'redrawtabline'
      end)
    end

    -- Expose for manual testing
    _G.save_bufferline_order = save_bufferline_order
    _G.load_bufferline_order = load_bufferline_order

    local loaded_for = nil
    local function load_if_possible()
      local path = get_order_file_path()
      if not path or vim.fn.filereadable(path) == 0 then
        return
      end
      if loaded_for == path then
        return
      end
      loaded_for = path
      load_bufferline_order()
    end

    -- After session restore (normal case)
    vim.api.nvim_create_autocmd('User', {
      pattern = 'AutoSessionRestorePost',
      callback = function()
        vim.schedule(load_if_possible)
      end,
    })

    -- If Bufferline loads AFTER the restore event already fired:
    vim.schedule(load_if_possible)

    -- Also handle manual :source Session.vim
    vim.api.nvim_create_autocmd('SessionLoadPost', {
      callback = function()
        vim.schedule(load_if_possible)
      end,
    })

    -- Save on exit as before
    vim.api.nvim_create_autocmd('VimLeavePre', { callback = save_bufferline_order })
  end,
}
