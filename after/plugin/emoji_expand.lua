-- Expand GitHub-style :shortcode: -> Unicode emoji across all buffers.

local cache_dir = vim.fn.stdpath 'data' .. '/gemoji'
local cache_file = cache_dir .. '/emoji.json'
local gemoji_url = 'https://raw.githubusercontent.com/github/gemoji/master/db/emoji.json'

-- Shortcodes to never auto-expand (still available via completion).
local expand_shortcode_blacklist = {
  link = true,
}

local function ensure_dir()
  if vim.fn.isdirectory(cache_dir) == 0 then
    vim.fn.mkdir(cache_dir, 'p')
  end
end

local function read_file(path)
  local ok, lines = pcall(vim.fn.readfile, path)
  if not ok or not lines then
    return nil
  end
  return table.concat(lines, '\n')
end

local function write_file(path, data)
  local ok = pcall(vim.fn.writefile, vim.split(data, '\n', { plain = true }), path)
  return ok
end

-- Global cache for this Neovim instance
_G.__gemoji_map = _G.__gemoji_map or nil

local function build_map()
  if _G.__gemoji_map then
    return _G.__gemoji_map
  end

  ensure_dir()

  if vim.fn.filereadable(cache_file) == 0 then
    -- Download once
    local cmd = { 'curl', '-fsSL', gemoji_url }
    local data = vim.fn.system(cmd)
    if vim.v.shell_error ~= 0 or not data or data == '' then
      vim.notify('gemoji: failed to download emoji.json (need curl)', vim.log.levels.ERROR)
      return nil
    end
    if not write_file(cache_file, data) then
      vim.notify('gemoji: failed to write cache file: ' .. cache_file, vim.log.levels.ERROR)
      return nil
    end
  end

  local raw = read_file(cache_file)
  if not raw or raw == '' then
    vim.notify('gemoji: cache file empty: ' .. cache_file, vim.log.levels.ERROR)
    return nil
  end

  local ok, decoded = pcall(vim.json.decode, raw)
  if not ok or type(decoded) ~= 'table' then
    vim.notify('gemoji: failed to parse emoji.json', vim.log.levels.ERROR)
    return nil
  end

  local map = {}
  for _, item in ipairs(decoded) do
    local emo = item.emoji
    local aliases = item.aliases
    if type(emo) == 'string' and type(aliases) == 'table' then
      for _, a in ipairs(aliases) do
        if type(a) == 'string' and a ~= '' then
          map[a] = emo
        end
      end
    end
  end

  _G.__gemoji_map = map
  return map
end

local function expand_at_cursor()
  local map = build_map()
  if not map then
    return false
  end

  local row, col = unpack(vim.api.nvim_win_get_cursor(0)) -- col is 0-based (byte)
  local line = vim.api.nvim_get_current_line()

  -- Look left of cursor for :shortcode:
  local left = line:sub(1, col)
  local s, e, code = left:find ':([%w_+%-]+):$'

  if not code then
    return false
  end
  if expand_shortcode_blacklist[code] then
    return false
  end
  local emoji = map[code]
  if not emoji then
    return false
  end

  -- Replace from s..e in the LINE (Lua indices are 1-based)
  local new_line = line:sub(1, s - 1) .. emoji .. line:sub(e + 1)
  vim.api.nvim_set_current_line(new_line)

  -- Put cursor after inserted emoji (compute new col in bytes)
  local before = new_line:sub(1, (s - 1)) .. emoji
  vim.api.nvim_win_set_cursor(0, { row, #before })
  return true
end

local function expand_line(line, map)
  return line:gsub(':([%w_+%-]+):', function(code)
    if expand_shortcode_blacklist[code] then
      return ':' .. code .. ':'
    end
    return map[code] or (':' .. code .. ':')
  end)
end

local function expand_buffer(bufnr)
  bufnr = bufnr or 0
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end
  if vim.bo[bufnr].buftype ~= '' then
    return
  end
  if not vim.bo[bufnr].modifiable or vim.bo[bufnr].readonly or vim.bo[bufnr].binary then
    return
  end

  local map = build_map()
  if not map then
    return
  end

  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local changed = false
  for i, line in ipairs(lines) do
    local new_line = expand_line(line, map)
    if new_line ~= line then
      lines[i] = new_line
      changed = true
    end
  end

  if changed then
    local view = vim.fn.winsaveview()
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
    vim.fn.winrestview(view)
  end
end

local function expand_unicode_entity_at_cursor()
  local ok, unicode_entities = pcall(require, 'custom.unicode_entities')
  return ok and unicode_entities.expand_at_cursor()
end

local function expand_unicode_entity_pending_char(typed)
  local ok, unicode_entities = pcall(require, 'custom.unicode_entities')
  return ok and unicode_entities.expand_pending_char(typed)
end

local function expand_after_insert()
  vim.schedule(function()
    if expand_unicode_entity_at_cursor() then
      return
    end
    pcall(expand_at_cursor)
  end)
end

local function make_expand_map(typed, omit_typed_on_expand)
  return function()
    if expand_unicode_entity_pending_char(typed) then
      return ''
    end
    if expand_unicode_entity_at_cursor() then
      if omit_typed_on_expand then
        return ''
      end
      return typed
    end
    expand_after_insert()
    return typed
  end
end

local function set_insert_maps(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end
  if vim.bo[bufnr].buftype ~= '' then
    return
  end

  -- Expand when you "commit" the word (buffer-local insert-mode maps)
  vim.keymap.set('i', '<Space>', make_expand_map ' ', { buffer = bufnr, expr = true, silent = true })
  vim.keymap.set('i', '<CR>', make_expand_map '\n', { buffer = bufnr, expr = true, silent = true })
  vim.keymap.set('i', '<Tab>', make_expand_map('\t', true), { buffer = bufnr, expr = true, silent = true })

  -- Optional: expand before common punctuation
  for _, ch in ipairs { ',', '.', '!', '?', ')', ']', '}', ':', ';', '-', '>' } do
    vim.keymap.set('i', ch, make_expand_map(ch), { buffer = bufnr, expr = true, silent = true })
  end
end

local unicode_expand_filetype_blacklist = {
  -- Add filetypes here to disable insert-mode emoji/unicode expansion.
  rust = true,
  sh = true,
  lua = true,
  python = true,
}

-- Reapply insert-mode maps per buffer to avoid being overridden by ftplugins
vim.api.nvim_create_autocmd({ 'BufEnter', 'FileType' }, {
  desc = 'Set emoji/unicode expansion insert maps',
  group = vim.api.nvim_create_augroup('emoji-expand-maps', { clear = true }),
  callback = function(args)
    if not unicode_expand_filetype_blacklist[vim.bo[args.buf].filetype] then
      set_insert_maps(args.buf)
    end
  end,
})

-- Expand all :shortcode: on save for markdown buffers only
vim.api.nvim_create_autocmd('BufWritePre', {
  desc = 'Expand :shortcode: to emoji on save',
  group = vim.api.nvim_create_augroup('emoji-expand', { clear = true }),
  callback = function(args)
    if vim.bo[args.buf].filetype == 'markdown' then
      expand_buffer(args.buf)
    end
  end,
})

-- Debug helpers (avoid redefinition if this file is reloaded)
if vim.fn.exists ':EmojiExpand' == 0 then
  vim.api.nvim_create_user_command('EmojiExpand', function()
    expand_at_cursor()
  end, { desc = 'Expand :shortcode: under cursor' })
end

if vim.fn.exists ':EmojiStatus' == 0 then
  vim.api.nvim_create_user_command('EmojiStatus', function()
    local has = (_G.__gemoji_map ~= nil)
    local readable = (vim.fn.filereadable(cache_file) == 1)
    vim.notify(('gemoji: map_loaded=%s cache=%s (%s)'):format(tostring(has), tostring(readable), cache_file), vim.log.levels.INFO)
  end, { desc = 'Show gemoji cache/map status' })
end
