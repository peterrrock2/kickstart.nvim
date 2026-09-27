local M = {}

local function parse(source, language)
  local parser = vim.treesitter.get_string_parser(source, language)
  return parser:parse()[1]:root()
end

local function is_docstring(node)
  local statement = node:parent()
  local scope = statement and statement:parent()
  if not scope or statement:type() ~= 'expression_statement' or statement:named_child_count() ~= 1 then
    return false
  end

  local owner = scope:parent()
  if scope:type() ~= 'module' and not (scope:type() == 'block' and owner and (owner:type() == 'function_definition' or owner:type() == 'class_definition')) then
    return false
  end

  for child in scope:iter_children() do
    if child:named() and child:type() ~= 'comment' then
      return child == statement
    end
  end
  return false
end

local function collect_blocks(lines, language)
  local source = table.concat(lines, '\n') .. '\n'
  local root = parse(source, language)
  if root:has_error() then
    error('Reflow: fix ' .. language .. ' syntax errors before reflowing prose')
  end
  local pattern = language == 'python' and '[(comment) (string)] @prose' or '[(line_comment) (block_comment)] @prose'
  local query = vim.treesitter.query.parse(language, pattern)
  local blocks = {}

  for _, node in query:iter_captures(root, source) do
    local first, column, last, end_column = node:range()
    last = end_column == 0 and last or last + 1
    local before = lines[first + 1]:sub(1, column)
    local after = end_column == 0 and '' or lines[last]:sub(end_column + 1)
    if before:match '^%s*$' and after:match '^%s*$' then
      local kind = node:type()
      if kind == 'comment' or kind == 'line_comment' then
        local marker = language == 'python' and '#' or lines[first + 1]:sub(column + 1):match '^//[/!]*'
        local prefix = before .. marker
        if lines[first + 1]:sub(#prefix + 1, #prefix + 1) == ' ' then
          prefix = prefix .. ' '
        end
        local previous = blocks[#blocks]
        if previous and previous.last == first and previous.prefix == prefix then
          previous.last = last
        else
          blocks[#blocks + 1] = { first = first, last = last, prefix = prefix }
        end
      elseif kind == 'block_comment' or (kind == 'string' and is_docstring(node)) then
        blocks[#blocks + 1] = { first = first, last = last, kind = kind }
      end
    end
  end
  return blocks
end

local function unpack_docstring(content, block)
  local indent, modifier, quote = content[1]:match '^(%s*)([rRuU]?)(""")'
  if not quote then
    indent, modifier, quote = content[1]:match "^(%s*)([rRuU]?)(''')"
  end
  if not quote then
    return
  end
  content[1] = content[1]:sub(#indent + #modifier + 4)
  content[#content] = content[#content]:gsub(quote .. '%s*$', '')
  for i = 2, #content do
    if content[i]:sub(1, #indent) == indent then
      content[i] = content[i]:sub(#indent + 1)
    elseif not content[i]:match '^%s*$' then
      return
    end
  end
  if content[#content]:match '^%s*$' then
    table.remove(content)
  end
  block.content_offset = 0
  if content[1] == '' then
    table.remove(content, 1)
    block.content_offset = 1
  else
    block.summary_prefix = modifier .. quote
  end
  return content, indent, { indent .. modifier .. quote }, { indent .. quote }
end

local function unpack_block_comment(content, block)
  local indent, opener = content[1]:match '^(%s*)(/%*+!?)'
  local closing = content[#content]:match '^%s*%*/%s*$' or indent .. ' */'
  content[1] = content[1]:sub(#indent + #opener + 1):gsub('^ ', '')
  content[#content] = content[#content]:gsub('%s*%*/%s*$', '')
  local prefix = content[2] and (content[2]:match '^%s*%* ?' or content[2]:match '^%s*') or indent .. ' '
  for i = 2, #content do
    if content[i]:match '^%s*$' or (prefix:find('*', 1, true) and vim.trim(content[i]) == '*') then
      content[i] = ''
    elseif content[i]:sub(1, #prefix) == prefix then
      content[i] = content[i]:sub(#prefix + 1)
    else
      return
    end
  end
  if table.concat(content):find '/%*' or table.concat(content):find '%*/' then
    return
  end
  if content[#content] == '' then
    table.remove(content)
  end
  block.content_offset = 0
  if content[1] == '' then
    table.remove(content, 1)
    block.content_offset = 1
  end
  return content, prefix, { indent .. opener }, { closing }
end

local function unpack_block(lines, block)
  local content = vim.list_slice(lines, block.first + 1, block.last)
  if block.kind == 'string' then
    return unpack_docstring(content, block)
  elseif block.kind == 'block_comment' then
    return unpack_block_comment(content, block)
  end

  for i, line in ipairs(content) do
    content[i] = line:sub(#block.prefix + 1)
  end
  return content, block.prefix, {}, {}
end

local function can_reflow(lines, first, last, field)
  for row = first, last do
    local line = lines[row]
    if
      line:match '  $'
      or line:match '\\$'
      or line:match '^%s*>>>'
      or line:match '^%s*%.%.%.'
      or line:match '^%s*```'
      or line:match '^%s*~~~'
      or line:match '^%s*|'
      or line:match '^%s*%[[^%]]+%]:'
      or (line:find('|', 1, true) and line:match '^[%s|:%-]+$')
      or (not field and (line:match '^%s*[%w_]+:%s*$' or line:match '^%s*[:@]' or line:match '^%s*[%w_-]+:' or line:match '^%s*!'))
    then
      return false
    end
  end
  return true
end

local atomic_nodes = {
  inline_link = 'link',
  full_reference_link = 'link',
  collapsed_reference_link = 'link',
  shortcut_link = 'link',
  image = 'link',
  code_span = 'verbatim',
  latex_block = 'verbatim',
  html_tag = 'verbatim',
  uri_autolink = 'verbatim',
  email_autolink = 'verbatim',
}

local function protect_inline_units(source, label)
  local pieces, replacements, position, codepoint = {}, {}, 1, 0xE000
  local _, quote_depth = (source:match '^[ \t>]*'):gsub('>', '')
  local preserve = false
  local function protect(first, last, policy)
    local text = source:sub(first + 1, last)
    if policy == 'link' then
      for _ = 1, quote_depth do
        text = text:gsub('\n[ \t]*>[ \t]?', '\n')
      end
      text = text:gsub('[ \t]*\n[ \t]*', ' ')
    elseif text:find('\n', 1, true) then
      preserve = true
    end
    local marker
    repeat
      marker = vim.fn.nr2char(codepoint)
      codepoint = codepoint + 1
    until not source:find(marker, 1, true)
    -- A same-width, unbreakable placeholder lets gq keep its native list/quote handling.
    local columns = vim.fn.strdisplaywidth((text:gsub('\n', ' ')))
    local placeholder = marker:rep(math.max(1, math.ceil(columns / vim.fn.strdisplaywidth(marker))))
    pieces[#pieces + 1] = source:sub(position, first)
    pieces[#pieces + 1] = placeholder
    replacements[#replacements + 1] = { placeholder, text }
    position = last + 1
  end
  if label then
    protect(#label:match '^%s*', #label)
  end
  local function visit(node)
    if atomic_nodes[node:type()] then
      local _, _, first = node:start()
      local _, _, last = node:end_()
      if first >= position - 1 then
        protect(first, last, atomic_nodes[node:type()])
      end
      return
    end
    for child in node:iter_children() do
      visit(child)
    end
  end
  visit(parse(source, 'markdown_inline'))
  pieces[#pieces + 1] = source:sub(position)
  local masked = table.concat(pieces)
  -- Unparsed brackets can be nested links that the inline parser did not recognize.
  preserve = preserve or masked:gsub('\\.', ''):find '[%[%]]' ~= nil
  return masked, replacements, preserve
end

local function markdown_shape(source)
  local function shape(node)
    if node:type() == 'inline' or node:type() == 'block_continuation' then
      return ''
    end

    local children = { node:type() }
    for child in node:iter_children() do
      if child:named() then
        children[#children + 1] = shape(child)
      end
    end
    return '(' .. table.concat(children) .. ')'
  end
  return shape(parse(source .. '\n', 'markdown'))
end

local function wrap_paragraph(lines, width, field, scratch, summary_prefix)
  local original = table.concat(lines, '\n')
  if summary_prefix then
    lines[1] = summary_prefix .. lines[1]
  end
  local label, description = lines[1]:match '^(%s*.-:)%s*(.*)$'
  local hanging = field and label
  if hanging and description ~= '' then
    local indent = lines[1]:match '^%s*' .. '    '
    lines[1] = label
    table.insert(lines, 2, indent .. description)
  end
  local source, replacements, preserve = protect_inline_units(table.concat(lines, '\n'), hanging)
  if preserve then
    return vim.split(original, '\n', { plain = true })
  end

  vim.api.nvim_buf_set_lines(scratch, 0, -1, false, vim.split(source, '\n', { plain = true }))
  vim.bo[scratch].textwidth = width
  local numbered = lines[1]:match '^[%s>]*%d+[.)]%s'
  vim.bo[scratch].formatoptions = hanging and 'tq2' or (numbered and 'tqn' or 'tq')
  vim.api.nvim_buf_call(scratch, function()
    vim.cmd 'silent keepjumps normal! gggqG'
  end)
  local result = table.concat(vim.api.nvim_buf_get_lines(scratch, 0, -1, false), '\n')
  for _, replacement in ipairs(replacements) do
    result = result:gsub(replacement[1], function()
      return replacement[2]
    end)
  end
  if summary_prefix then
    result = result:sub(#summary_prefix + 1)
  end
  if markdown_shape(original) ~= markdown_shape(result) then
    return vim.split(original, '\n', { plain = true })
  end
  return vim.split(result, '\n', { plain = true })
end

local field_sections = {
  Args = true,
  Arguments = true,
  Parameters = true,
  KeywordArgs = true,
  Returns = true,
  Yields = true,
  Raises = true,
  Attributes = true,
}

local prose_sections = { Note = true, Notes = true }

local function collect_docstring_ranges(lines)
  local ranges, structured = {}, {}
  local section, style, first, indent, section_indent
  local function finish(last)
    if first then
      ranges[#ranges + 1] = { first, last, field = style == 'google' and field_sections[section] }
      first = nil
    end
  end

  for row, line in ipairs(lines) do
    local heading = line:match '^(%a[%a ]*):$'
    local numpy = lines[row + 1] and lines[row + 1]:match '^%-%-%-+$'
    if heading or numpy then
      finish(row - 1)
      section, style = heading or line, heading and 'google' or 'numpy'
      section_indent = nil
    end
    if section then
      structured[row] = true
      local whitespace = line:match '^%s*'
      local supported = field_sections[section] or (style == 'google' and prose_sections[section])
      local entry = supported and #whitespace > 0 and not line:match '^%s*$'
      if entry then
        section_indent = section_indent or #whitespace
        -- A separately indented block can be a code example, even inside a field section.
        entry = first ~= nil or #whitespace <= section_indent
      end
      if not entry then
        finish(row - 1)
      elseif
        not first
        or #whitespace < indent
        or (#whitespace == indent and style == 'google' and field_sections[section] and (line:match ':%s' or line:match ':$'))
      then
        finish(row - 1)
        first, indent = row, #whitespace
      end
    end
  end
  finish(#lines)
  return ranges, structured
end

local function collect_disabled_rows(lines)
  local rows, disabled = {}, false
  for row, line in ipairs(lines) do
    local directive = vim.trim(line):gsub('^#%s*', ''):gsub('^//[/!]*%s*', '')
    directive = directive:gsub('^<!%-%-%s*', ''):gsub('%s*%-%->$', '')
    local mode = directive:match '^fmt:%s*(%a+)' or directive:match '^reflow:%s*(%a+)'

    if mode == 'off' or directive == 'prettier-ignore-start' then
      disabled = true
    end
    rows[row] = disabled
    if mode == 'on' or directive == 'prettier-ignore-end' then
      disabled = false
    end
  end
  return rows
end

local function collect_protected_rows(lines, root, source)
  local rows, doctest = {}, false
  for row, line in ipairs(lines) do
    if line:match '^%s*$' then
      doctest = false
    elseif line:match '^%s*>>>' then
      doctest = true
    end
    rows[row] = doctest
  end

  local query = vim.treesitter.query.parse('markdown', '(html_block) @directive')
  for _, node in query:iter_captures(root, source) do
    if vim.trim(vim.treesitter.get_node_text(node, source)) == '<!-- prettier-ignore -->' then
      local following = node:next_named_sibling()
      local parent = node:parent()
      while not following and parent do
        following, parent = parent:next_named_sibling(), parent:parent()
      end
      if following and following:type() == 'section' then
        following = following:named_child(0)
      end
      if following then
        local first, _, last, column = following:range()
        for row = first + 1, last + (column > 0 and 1 or 0) do
          rows[row] = true
        end
      end
    end
  end
  return rows
end

local function reflow_prose(lines, width, scratch, block, opts, disabled_rows)
  if #lines == 0 then
    return lines
  end
  local source = table.concat(lines, '\n') .. '\n'
  local root = parse(source, 'markdown')
  local protected_rows = collect_protected_rows(lines, root, source)
  -- Paragraph nodes can include indentation belonging to the next nested list item.
  local query = vim.treesitter.query.parse('markdown', '(paragraph (inline) @paragraph)')
  local ranges, structured = {}, {}
  if block.kind == 'string' then
    ranges, structured = collect_docstring_ranges(lines)
  end
  for _, node in query:iter_captures(root, source) do
    local first, _, last, column = node:range()
    last = column == 0 and last or last + 1
    local heading = node:parent():parent():type() == 'setext_heading'
    if not heading and not structured[first + 1] and not structured[last] then
      local start = first + 1
      for row = start, last + 1 do
        if row > last or not can_reflow(lines, row, row) then
          if start < row then
            ranges[#ranges + 1] = { start, row - 1 }
          end
          start = row + 1
        end
      end
    end
  end
  table.sort(ranges, function(a, b)
    return a[1] < b[1]
  end)

  local result, position = {}, 1
  for _, range in ipairs(ranges) do
    local first, last = unpack(range)
    local offset = block.first + (block.content_offset or 0)
    local protected = false
    for row = first, last do
      protected = protected or protected_rows[row] or disabled_rows[row + offset]
    end
    if not protected and first + offset >= opts.line1 and last + offset <= opts.line2 and can_reflow(lines, first, last, range.field) then
      vim.list_extend(result, vim.list_slice(lines, position, first - 1))
      local summary_prefix = first == 1 and block.summary_prefix or nil
      vim.list_extend(result, wrap_paragraph(vim.list_slice(lines, first, last), width, range.field, scratch, summary_prefix))
      position = last + 1
    end
  end
  vim.list_extend(result, vim.list_slice(lines, position))
  return result
end

local function build_edits(lines, blocks, width, scratch, opts)
  local result = {}
  local disabled_rows = collect_disabled_rows(lines)
  for _, block in ipairs(blocks) do
    local selected = block.first < opts.line2 and block.last >= opts.line1
    if block.kind then
      selected = block.first >= opts.line1 - 1 and block.last <= opts.line2
    end
    if selected then
      local content, prefix, opening, closing = unpack_block(lines, block)
      local available = prefix and width - vim.fn.strdisplaywidth(prefix) or 0
      if content and available > 0 then
        local wrapped = reflow_prose(content, available, scratch, block, opts, disabled_rows)
        local replacement = opening
        local first_line = 1
        if block.summary_prefix and wrapped[1] then
          replacement[1] = opening[1] .. wrapped[1]
          first_line = 2
        end
        for i = first_line, #wrapped do
          local line = wrapped[i]
          replacement[#replacement + 1] = line == '' and prefix:gsub('%s+$', '') or prefix .. line
        end
        vim.list_extend(replacement, closing)
        if not vim.deep_equal(wrapped, content) then
          result[#result + 1] = { block = block, lines = replacement }
        end
      end
    end
  end
  return result
end

function M.reflow(opts)
  local width = opts.args == '' and 98 or tonumber(opts.args)
  if not width or width < 1 or width ~= math.floor(width) or width > 10000 then
    error 'Reflow: width must be an integer between 1 and 10000'
  end
  local language = vim.bo.filetype
  if language ~= 'markdown' and language ~= 'rust' and language ~= 'python' then
    error 'Reflow supports Markdown, Rust, and Python'
  end

  local buffer = vim.api.nvim_get_current_buf()
  local lines = vim.api.nvim_buf_get_lines(buffer, 0, -1, false)
  local blocks = language == 'markdown' and { { first = 0, last = #lines, prefix = '' } } or collect_blocks(lines, language)
  local scratch = vim.api.nvim_create_buf(false, true)
  vim.bo[scratch].formatoptions = 'tqn'
  -- The default also accepts a number followed by a space, mistaking years for list items.
  vim.bo[scratch].formatlistpat = [[^\s*\d\+[.)]\s\+]]
  vim.bo[scratch].comments = 'fb:*,fb:-,fb:+,n:>'
  vim.bo[scratch].formatexpr = ''
  vim.bo[scratch].formatprg = ''
  vim.bo[scratch].autoindent = true
  vim.bo[scratch].expandtab = true
  vim.bo[scratch].tabstop = vim.bo[buffer].tabstop
  local view = vim.fn.winsaveview()
  local ok, edits = pcall(build_edits, lines, blocks, width, scratch, opts)
  vim.api.nvim_buf_delete(scratch, { force = true })
  vim.fn.winrestview(view)
  if not ok then
    error(edits)
  end

  for i = #edits, 1, -1 do
    if i < #edits then
      vim.cmd.undojoin()
    end
    local edit = edits[i]
    vim.api.nvim_buf_set_lines(buffer, edit.block.first, edit.block.last, false, edit.lines)
  end
  vim.fn.winrestview(view)
end

return M
