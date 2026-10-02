local function prune_missing_buffers()
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    local name = vim.api.nvim_buf_get_name(bufnr)
    if
      vim.bo[bufnr].buflisted
      and not vim.api.nvim_buf_is_loaded(bufnr)
      and name ~= ''
      and not vim.uv.fs_stat(name)
    then
      vim.api.nvim_buf_delete(bufnr, {})
    end
  end
end

local function restore_python_folding()
  -- Session options are restored after ftplugins and can override Python's fold method.
  for _, window in ipairs(vim.api.nvim_list_wins()) do
    local buffer = vim.api.nvim_win_get_buf(window)
    if vim.bo[buffer].filetype == 'python' and vim.wo[window].foldmethod ~= 'indent' then
      vim.wo[window].foldmethod = 'indent'
      vim.wo[window].foldlevel = 99
    end
  end
end

local function restore_session_root_directory()
  local directory = vim.fn.getcwd(-1, -1)
  -- Clear saved local directories without triggering another session save or restore.
  for _, window in ipairs(vim.api.nvim_list_wins()) do
    vim.api.nvim_win_call(window, function()
      vim.cmd.cd { directory, mods = { noautocmd = true } }
    end)
  end

  if not package.loaded['neo-tree'] then
    return
  end

  local manager = require('neo-tree.sources.manager')
  for _, tab in ipairs(vim.api.nvim_list_tabpages()) do
    local state = manager.get_state('filesystem', tab)
    state.path, state.dirty = directory, true
  end
end

return {
  'rmagatti/auto-session',
  lazy = false,
  dependencies = {
    'nvim-telescope/telescope.nvim', -- Only needed if you want to use session lens
  },
  init = function()
    -- Drop 'terminal' so terminal buffers are not saved/restored with the session.
    vim.o.sessionoptions =
      'blank,buffers,curdir,folds,globals,help,tabpages,winsize,winpos,localoptions'
  end,
  opts = {
    log_level = 'error',
    enabled = true,
    auto_save = true,
    auto_restore = true,
    auto_restore_last_session = false,
    cwd_change_handling = true,
    use_git_branch_name = true,
    pre_save_cmds = { prune_missing_buffers },
    pre_restore_cmds = {
      function()
        vim.g.BufferlinePositions = nil
      end,
    },
    post_restore_cmds = { prune_missing_buffers, restore_python_folding, restore_session_root_directory },

    -- Show restore errors but keep auto-save enabled, so a stale session entry
    -- (e.g. a deleted file image.nvim chokes on) gets overwritten on exit
    -- instead of breaking every subsequent startup.
    restore_error_handler = function(error_msg)
      vim.notify('Session restore error (auto-save kept on): ' .. error_msg, vim.log.levels.WARN)
      return true
    end,

    suppressed_dirs = { '~/', '~/Projects', '~/Downloads', '/' },
  },
}
