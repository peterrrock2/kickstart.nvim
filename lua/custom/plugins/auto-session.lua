return {
  'rmagatti/auto-session',
  lazy = false,
  dependencies = {
    'nvim-telescope/telescope.nvim', -- Only needed if you want to use session lens
  },
  opts = {
    log_level = 'error',
    enabled = true,
    auto_save = true,
    auto_restore = true,
    auto_restore_last_session = false,
    cwd_change_handline = true,
    use_git_branch_name = true,

    suppressed_dirs = { '~/', '~/Projects', '~/Downloads', '/' },
  },
}
