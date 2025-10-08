local venv = os.getenv 'VIRTUAL_ENV'
if venv and vim.fn.executable(venv .. '/bin/python') == 1 then
  vim.g.python3_host_prog = venv .. '/bin/python'
end

-- Set <space> as the leader key
-- See `:help mapleader`
--  NOTE: Must happen before plugins are loaded (otherwise wrong leader will be used)
vim.g.mapleader = ' '
vim.g.maplocalleader = ' '

-- Automatically detect .venv in the current project and set it for Python provider
local venv_path = vim.fn.finddir('.venv', '.;')
if venv_path ~= '' then
  local python_bin = vim.fn.getcwd() .. '/' .. venv_path .. '/bin/python'
  vim.g.python3_host_prog = python_bin
end

-- Set to true if you have a Nerd Font installed and selected in the terminal
vim.g.have_nerd_font = true

-- [[ Setting options ]]
-- See `:help vim.o`
-- NOTE: You can change these options as you wish!
--  For more options, you can see `:help option-list`

-- Make line numbers default
vim.o.number = true
-- You can also add relative line numbers, to help with jumping.
--  Experiment for yourself to see if you like it!
vim.o.relativenumber = true

-- Enable mouse mode, can be useful for resizing splits for example!
vim.o.mouse = 'a'

-- Don't show the mode, since it's already in the status line
vim.o.showmode = true

-- Sync clipboard between OS and Neovim.
--  Schedule the setting after `UiEnter` because it can increase startup-time.
--  Remove this option if you want your OS clipboard to remain independent.
--  See `:help 'clipboard'`
vim.schedule(function()
  vim.o.clipboard = 'unnamedplus'
  vim.g.clipboard = 'osc52'
end)

-- Enable break indent
vim.o.breakindent = true

-- Save undo history
vim.o.undofile = true

-- Case-insensitive searching UNLESS \C or one or more capital letters in the search term
vim.o.ignorecase = true
vim.o.smartcase = true

-- Keep signcolumn on by default
vim.o.signcolumn = 'yes'

-- Decrease update time
vim.o.updatetime = 250

-- Decrease mapped sequence wait time
vim.o.timeoutlen = 300

-- Configure how new splits should be opened
vim.o.splitright = true
vim.o.splitbelow = true

-- Sets how neovim will display certain whitespace characters in the editor.
--  See `:help 'list'`
--  and `:help 'listchars'`
--
--  Notice listchars is set using `vim.opt` instead of `vim.o`.
--  It is very similar to `vim.o` but offers an interface for conveniently interacting with tables.
--   See `:help lua-options`
--   and `:help lua-options-guide`
vim.o.list = true
vim.opt.listchars = { tab = '» ', trail = '·', nbsp = '␣' }

-- Preview substitutions live, as you type!
vim.o.inccommand = 'split'

-- Show which line your cursor is on
vim.o.cursorline = true

-- Minimal number of screen lines to keep above and below the cursor.
vim.o.scrolloff = 10

-- Needed for the bufferline extension to work
vim.o.termguicolors = true

-- Make the number of space that a tab character occupies 4
vim.o.tabstop = 4

-- Number of spaces to use for each step of an indentation
vim.o.shiftwidth = 4

-- Convert tabs to spaces
vim.o.expandtab = true

-- Turn on the spell checking
vim.o.spell = true
vim.o.spelllang = 'en_us'
vim.o.confirm = true

-- detect project name (using cwd here, but you could hook into something like project.nvim)
local project_name = vim.fn.fnamemodify(vim.fn.getcwd(), ':t')
local project_spellfile = vim.fn.stdpath 'config' .. '/spell/projects/' .. project_name .. '.utf-8.add'

vim.opt.spellfile = { vim.fn.stdpath 'config' .. '/spell/en.utf-8.add' }
vim.opt.spellfile:prepend(project_spellfile)
--
-- [[ Basic Keymaps ]]
--  See `:help vim.keymap.set()`

-- Clear highlights on search when pressing <Esc> in normal mode
--  See `:help hlsearch`
vim.keymap.set('n', '<Esc>', '<cmd>nohlsearch<CR>')

-- Diagnostic keymaps
vim.keymap.set('n', '<leader>q', vim.diagnostic.setloclist, { desc = 'Open diagnostic [Q]uickfix list' })
local function diag_loclist_with_source(bufnr, opts)
  bufnr = bufnr or 0
  opts = opts or {}
  local diags = vim.diagnostic.get(bufnr, opts)
  local items = {}

  local sev2qf = {
    [vim.diagnostic.severity.ERROR] = 'E',
    [vim.diagnostic.severity.WARN] = 'W',
    [vim.diagnostic.severity.INFO] = 'I',
    [vim.diagnostic.severity.HINT] = 'H',
  }

  for _, d in ipairs(diags) do
    local src = d.source or 'LSP'
    local code = d.code and ('[' .. tostring(d.code) .. '] ') or ''
    table.insert(items, {
      bufnr = d.bufnr or bufnr,
      lnum = (d.lnum or 0) + 1,
      col = (d.col or 0) + 1,
      end_lnum = d.end_lnum and (d.end_lnum + 1) or nil,
      end_col = d.end_col and (d.end_col + 1) or nil,
      text = string.format('[%s] %s%s', src, code, d.message or ''),
      type = sev2qf[d.severity] or 'I',
    })
  end

  vim.fn.setloclist(0, {}, ' ', { title = 'Diagnostics', items = items })
  if #items > 0 then
    vim.cmd.lopen()
  else
    vim.cmd.lclose()
    if not opts.silent then
      vim.notify('No diagnostics', vim.log.levels.INFO, { title = 'Diagnostics' })
    end
  end
end

-- replace setloclist binding
vim.keymap.set('n', '<leader>q', function()
  diag_loclist_with_source(0) -- current buffer
end, { desc = 'Diagnostics → Loclist (with source)' })

-- Exit terminal mode in the builtin terminal with a shortcut that is a bit easier
-- for people to discover. Otherwise, you normally need to press <C-\><C-n>, which
-- is not what someone will guess without a bit more experience.
--
-- NOTE: This won't work in all terminal emulators/tmux/etc. Try your own mapping
-- or just use <C-\><C-n> to exit terminal mode
vim.keymap.set('t', '<Esc><Esc>', '<C-\\><C-n>', { desc = 'Exit terminal mode' })

-- TIP: Disable arrow keys in normal mode
-- vim.keymap.set('n', '<left>', '<cmd>echo "Use h to move!!"<CR>')
-- vim.keymap.set('n', '<right>', '<cmd>echo "Use l to move!!"<CR>')
-- vim.keymap.set('n', '<up>', '<cmd>echo "Use k to move!!"<CR>')
-- vim.keymap.set('n', '<down>', '<cmd>echo "Use j to move!!"<CR>')

-- Keybinds to make split navigation easier.
--  Use CTRL+<hjkl> to switch between windows
--
--  See `:help wincmd` for a list of all window commands
--
-- NOTE: Movement keybinds
vim.keymap.set('n', '<M-S-h>', '<C-w><C-h>', { desc = 'Move focus to the left window' })
vim.keymap.set('n', '<M-S-l>', '<C-w><C-l>', { desc = 'Move focus to the right window' })
vim.keymap.set('n', '<M-S-j>', '<C-w><C-j>', { desc = 'Move focus to the lower window' })
vim.keymap.set('n', '<M-S-k>', '<C-w><C-k>', { desc = 'Move focus to the upper window' })
vim.keymap.set('n', '<C-j>', ':m +1<CR>', { desc = 'Move line down 1' })
vim.keymap.set('i', '<C-j>', '<Esc>:m +1<CR>', { desc = 'Move line down 1' })
vim.keymap.set('n', '<C-k>', ':m -2<CR>', { desc = 'Move line up 1' })
vim.keymap.set('i', '<C-k>', '<Esc>:m -2<CR>', { desc = 'Move line up 1' })

-- NOTE: Peter keybinds start
vim.keymap.set('n', '<C-s>', ':wa<CR>', { desc = 'Save the file in the current buffer' })
vim.keymap.set('i', '<C-s>', '<Esc>:wa<CR>i', { desc = 'Save the file in the current buffer' })
vim.keymap.set('n', '<M-S-q>', ':wa <CR>:qa!<CR>', { desc = 'Quits out of everything' })
vim.keymap.set('i', '<M-S-q>', '<Esc>:wa <CR>:qa!<CR>', { desc = 'Quits out of everything' })
vim.keymap.set('n', '<C-S-Left>', ':BufferLineMovePrev<CR>', { desc = 'Moves buffer left' })
vim.keymap.set('n', '<C-S-Right>', ':BufferLineMoveNext<CR>', { desc = 'Moves buffer right' })
vim.keymap.set('i', '<M-h>', '<Esc>:BufferLineCyclePrev<CR>', { desc = 'Move to the previous buffer' })
vim.keymap.set('i', '<M-l>', '<Esc>:BufferLineCycleNext<CR>', { desc = 'Move to the next buffer' })
vim.keymap.set('n', '<M-h>', ':BufferLineCyclePrev<CR>', { desc = 'Move to the previous buffer' })
vim.keymap.set('n', '<M-l>', ':BufferLineCycleNext<CR>', { desc = 'Move to the next buffer' })
vim.keymap.set('n', '<M-S-c>', ':bp | bd #<CR>', { desc = 'Close current buffer' })
vim.keymap.set('i', '<M-S-c>', '<Esc>:bp | bd #<CR>', { desc = 'Close current buffer' })
vim.keymap.set('n', '<M-c>', '<C-w>c', { desc = 'Close current panel' })
vim.keymap.set('i', '<M-c>', '<Esc><C-w>c', { desc = 'Close current panel' })
vim.keymap.set('i', '<C-h>', '<C-w>', { noremap = true, silent = true, desc = 'Delete the previous word' })
vim.keymap.set('i', '<C-BS>', '<C-w>', { noremap = true, silent = true, desc = 'Delete the previous word' })
vim.keymap.set('i', '<C-Del>', '<C-o>dw', { noremap = true, silent = true, desc = 'Delete the next word' })
vim.keymap.set('i', '<C-Right>', '<C-o>e<C-o>a', { desc = 'Move to the end of the next word with insert' })
vim.keymap.set('i', '<C-Left>', '<C-o>b', { desc = 'Move to the beginning of the next word with insert' })
vim.keymap.set('n', '<leader>gd', function()
  require('diffview').open()
end, { silent = true, desc = 'Git Diff View' })
vim.keymap.set('n', '<leader>gq', function()
  require('diffview').close()
end, { silent = true, desc = 'Git Diff View' })
vim.keymap.set('x', 'gr', '<cmd>diffget<CR>', { desc = 'DiffGet on the selected text', silent = true })
vim.keymap.set('x', 'gs', '<cmd>diffput<CR>', { desc = 'DiffPut on the selected text', silent = true })

--
-- [[ Basic Autocommands ]]
--  See `:help lua-guide-autocommands`

-- Highlight when yanking (copying) text
--  Try it with `yap` in normal mode
--  See `:help vim.hl.on_yank()`
vim.api.nvim_create_autocmd('TextYankPost', {
  desc = 'Highlight when yanking (copying) text',
  group = vim.api.nvim_create_augroup('kickstart-highlight-yank', { clear = true }),
  callback = function()
    vim.hl.on_yank()
  end,
})

-- [[ Install `lazy.nvim` plugin manager ]]
--    See `:help lazy.nvim.txt` or https://github.com/folke/lazy.nvim for more info
local lazypath = vim.fn.stdpath 'data' .. '/lazy/lazy.nvim'
if not (vim.uv or vim.loop).fs_stat(lazypath) then
  local lazyrepo = 'https://github.com/folke/lazy.nvim.git'
  local out = vim.fn.system { 'git', 'clone', '--filter=blob:none', '--branch=stable', lazyrepo, lazypath }
  if vim.v.shell_error ~= 0 then
    error('Error cloning lazy.nvim:\n' .. out)
  end
end

---@type vim.Option
local rtp = vim.opt.rtp
rtp:prepend(lazypath)

-- [[ Configure and install plugins ]]
--
--  To check the current status of your plugins, run
--    :Lazy
--
--  You can press `?` in this menu for help. Use `:q` to close the window
--
--  To update plugins you can run
--    :Lazy update
--
-- NOTE: Here is where you install your plugins.
require('lazy').setup({
  -- NOTE: Plugins can be added with a link (or for a github repo: 'owner/repo' link).
  'NMAC427/guess-indent.nvim', -- Detect tabstop and shiftwidth automatically

  -- Highlight todo, notes, etc in comments
  { 'folke/todo-comments.nvim', event = 'VimEnter', dependencies = { 'nvim-lua/plenary.nvim' }, opts = { signs = false } },

  require 'kickstart.plugins.autopairs',
  require 'kickstart.plugins.blink', -- autocompletion
  require 'kickstart.plugins.conform', -- autoformatting
  require 'kickstart.plugins.indent_line',
  require 'kickstart.plugins.gitsigns', -- adds gitsigns recommend keymaps
  require 'kickstart.plugins.mini',
  require 'kickstart.plugins.neo-tree',
  require 'kickstart.plugins.tokyonight',
  require 'kickstart.plugins.treesitter',

  { import = 'custom.plugins' },
}, {
  ui = {
    -- If you are using a Nerd Font: set icons to an empty table which will use the
    -- default lazy.nvim defined Nerd Font icons, otherwise define a unicode icons table
    icons = vim.g.have_nerd_font and {} or {
      cmd = '⌘',
      config = '🛠',
      event = '📅',
      ft = '📂',
      init = '⚙',
      keys = '🗝',
      plugin = '🔌',
      runtime = '💻',
      require = '🌙',
      source = '📄',
      start = '🚀',
      task = '📌',
      lazy = '💤 ',
    },
  },
})

vim.api.nvim_create_autocmd('ColorScheme', {
  pattern = '*',
  callback = function()
    vim.cmd [[highlight SpellBad cterm=underline guisp=Red gui=undercurl]]
  end,
})
vim.cmd.colorscheme 'onedark'

-- The line beneath this is called `modeline`. See `:help modeline`
-- vim: ts=2 sts=2 sw=2 et
