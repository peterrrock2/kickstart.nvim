-- Custom blink.cmp source for :shortcode: emoji completion.
-- Shares the _G.__gemoji_map cache with after/plugin/emoji_expand.lua.

local cache_file = vim.fn.stdpath 'data' .. '/gemoji/emoji.json'

local function load_map()
  if _G.__gemoji_map then
    return _G.__gemoji_map
  end
  if vim.fn.filereadable(cache_file) == 0 then
    return nil
  end
  local ok, lines = pcall(vim.fn.readfile, cache_file)
  if not ok then
    return nil
  end
  local ok2, decoded = pcall(vim.json.decode, table.concat(lines, '\n'))
  if not ok2 or type(decoded) ~= 'table' then
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

local source = {}
source.__index = source

function source.new()
  return setmetatable({}, source)
end

function source:get_trigger_characters()
  return { ':' }
end

function source:get_completions(ctx, callback)
  local cursor_before_line = ctx.line and ctx.line:sub(1, ctx.cursor and ctx.cursor[2] or #ctx.line) or ''
  if not cursor_before_line:match ':[%w_+%-]*$' then
    callback { items = {}, is_incomplete_forward = false, is_incomplete_backward = false }
    return
  end

  local map = load_map()
  if not map then
    callback { items = {}, is_incomplete_forward = false, is_incomplete_backward = false }
    return
  end

  local items = {}
  for code, emoji in pairs(map) do
    items[#items + 1] = {
      label = ':' .. code .. ':',
      insertText = emoji,
      kind = vim.lsp.protocol.CompletionItemKind.Text,
      labelDetails = { description = emoji },
    }
  end

  callback { items = items, is_incomplete_forward = false, is_incomplete_backward = false }
end

return source
