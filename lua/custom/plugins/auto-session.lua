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

return {
  'rmagatti/auto-session',
  lazy = false,
  dependencies = {
    'nvim-telescope/telescope.nvim', -- Only needed if you want to use session lens
  },
  init = function()
    -- Drop 'terminal' so terminal buffers are not saved/restored with the session.
    vim.o.sessionoptions = 'blank,buffers,curdir,folds,help,tabpages,winsize,winpos,localoptions'
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
    post_restore_cmds = { prune_missing_buffers },

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
