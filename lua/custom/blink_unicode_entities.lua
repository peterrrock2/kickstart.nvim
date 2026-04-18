-- Custom blink.cmp source for ::&name:: Unicode entity completion.

local entities = require 'custom.unicode_entities'

local source = {}
source.__index = source

function source.new()
  return setmetatable({}, source)
end

function source:get_trigger_characters()
  return { ':', '&' }
end

function source:get_completions(ctx, callback)
  local prefix = entities.completion_prefix(ctx)
  if not prefix then
    callback { items = {}, is_incomplete_forward = false, is_incomplete_backward = false }
    return
  end

  local items = {}
  local line = ctx.cursor and ctx.cursor[1] - 1 or 0
  for _, name in ipairs(entities.sorted_names()) do
    local char = entities.entities[name]
    items[#items + 1] = {
      label = '::&' .. name .. '::',
      filterText = name .. ' ::&' .. name .. ':: ' .. char,
      sortText = name,
      kind = vim.lsp.protocol.CompletionItemKind.Text,
      labelDetails = { description = char },
      textEdit = {
        newText = char,
        range = {
          start = { line = line, character = prefix.start_col },
          ['end'] = { line = line, character = prefix.end_col },
        },
      },
      insertTextFormat = vim.lsp.protocol.InsertTextFormat.PlainText,
      score_offset = 20,
    }
  end

  callback { items = items, is_incomplete_forward = false, is_incomplete_backward = false }
end

return source
