-- Pyright's markdown hover drops `.. math::` blocks and turns :math: roles into code spans, so
-- pyright is asked for plaintext hovers (see nvim-lspconfig.lua) and the raw docstring is
-- converted here into Markdown math that render-markdown can draw.
local M = {}

local function convert_roles(line)
  line = line:gsub(':math:`([^`]+)`', '$%1$')
  return (line:gsub(':[%w_:%-]+:`~?([^`]+)`', '`%1`'))
end

-- Markdown math cannot span blank lines, so blank lines inside a math directive are dropped.
local function convert_rst_math(docstring)
  local output = {}
  local math_indent = nil

  for _, line in ipairs(vim.split(docstring, '\n')) do
    local indent = #line:match '^%s*'

    if math_indent and (line:match '^%s*$' or indent > math_indent) then
      if not line:match '^%s*$' and not line:match '^%s*:[%w_-]+:' then
        output[#output + 1] = vim.trim(line)
      end
    else
      if math_indent then
        vim.list_extend(output, { '$$', '' })
        math_indent = nil
      end

      local directive_indent, formula = line:match '^(%s*)%.%. math::%s*(.-)%s*$'
      if directive_indent then
        math_indent = #directive_indent
        output[#output + 1] = '$$'
        output[#output + 1] = formula ~= '' and formula or nil
      else
        output[#output + 1] = convert_roles(line)
      end
    end
  end

  if math_indent then
    output[#output + 1] = '$$'
  end
  return output
end

--- Convert pyright's plaintext hover (signature, blank line, docstring) into Markdown lines.
function M.to_markdown(text)
  local signature, docstring = text:match '^(.-)\n\n(.*)$'
  signature = signature or text

  local lines = { '```python' }
  vim.list_extend(lines, vim.split(signature, '\n'))
  lines[#lines + 1] = '```'

  if docstring then
    lines[#lines + 1] = ''
    vim.list_extend(lines, convert_rst_math(docstring))
  end
  return lines
end

function M.hover()
  local client = vim.lsp.get_clients({ bufnr = 0, name = 'pyright' })[1]
  if not client then
    return vim.lsp.buf.hover()
  end

  local params = vim.lsp.util.make_position_params(0, client.offset_encoding)
  client:request('textDocument/hover', params, function(err, result)
    local contents = not err and result and result.contents
    if not contents or contents.value == '' then
      return vim.notify('No information available', vim.log.levels.INFO)
    end

    local lines = contents.kind == 'plaintext' and M.to_markdown(contents.value) or vim.lsp.util.convert_input_to_markdown_lines(contents)
    vim.lsp.util.open_floating_preview(lines, 'markdown', { focus_id = 'textDocument/hover' })
  end, 0)
end

return M
