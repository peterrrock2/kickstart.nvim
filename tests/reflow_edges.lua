-- Run: NVIM_LOG_FILE=/tmp/nvim-reflow-test.log nvim -n --clean --headless -i NONE -l tests/reflow_edges.lua
vim.opt.runtimepath:prepend(vim.fn.getcwd())
vim.opt.runtimepath:append(vim.fn.stdpath 'data' .. '/site')
dofile 'after/plugin/reflow.lua'

local prose = 'These words explain the behavior in enough detail to require several lines at a narrow width.'
local failures, checks = {}, 0

local function check(name, language, input, verify, width)
  checks = checks + 1
  local ok, err = pcall(function()
    vim.cmd 'enew!'
    vim.bo.filetype = language
    vim.api.nvim_buf_set_lines(0, 0, -1, false, input)
    vim.cmd 'let &l:undolevels = &l:undolevels'
    vim.cmd('Reflow ' .. (width or 40))
    local output = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    verify(output)

    vim.cmd('Reflow ' .. (width or 40))
    assert(vim.deep_equal(output, vim.api.nvim_buf_get_lines(0, 0, -1, false)), 'second reflow changed the result')
  end)

  if not ok then
    failures[#failures + 1] = name .. ': ' .. tostring(err)
  end
end

local function contains(output, text)
  assert(table.concat(output, '\n'):find(text, 1, true), 'lost or changed: ' .. text)
end

local function preserved(name, language, input)
  check(name, language, input, function(output)
    assert(vim.deep_equal(#input == 0 and { '' } or input, output), 'protected content changed')
  end)
end

local function markdown_shape(lines)
  local root = vim.treesitter.get_string_parser(table.concat(lines, '\n') .. '\n', 'markdown'):parse()[1]:root()
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
  return shape(root)
end

check('year followed by a period inside prose', 'markdown', {
  'The source was published in',
  '1980. It supplies historical counts for all places, counties and states in the national release.',
}, function(output)
  for _, line in ipairs(output) do
    assert(not line:match '^%s', 'year introduced list indentation')
  end
  assert(output[1] == 'The source was published in 1980. It', 'ordinary prose did not reflow')
end)

for _, marker in ipairs { '#', '>', '-', '+', '*', '1.', '1)', '---', '***', '```' } do
  for width = 18, 37 do
    local input = { 'Ordinary words precede ' .. marker .. ' more ordinary words that follow it.' }
    check('new Markdown syntax ' .. marker .. ' at width ' .. width, 'markdown', input, function(output)
      assert(markdown_shape(input) == markdown_shape(output), 'wrapping created a Markdown block')
      assert(table.concat(input, ' ') == table.concat(output, ' '), 'text or spacing changed')
    end, width)
  end
end

for _, input in ipairs {
  { '> 1. ' .. prose },
  { '- [x] ' .. prose, '- [ ] ' .. prose },
  { '1. ' .. prose, '   - ' .. prose, '2. ' .. prose },
  { '> > ' .. prose },
  { '- ' .. prose, '', '  ' .. prose },
} do
  check('nested lists, checkboxes and quotes ' .. checks, 'markdown', input, function(output)
    assert(markdown_shape(input) == markdown_shape(output), 'container structure changed')
    assert(not vim.deep_equal(input, output), 'container prose did not wrap')
  end)
end

preserved('multiline inline code', 'markdown', { 'Here is `a code', 'span with spaces` followed by ' .. prose })
preserved('display math boundaries', 'markdown', { 'Introductory text.', '$$', 'x = a + b + c', '$$', prose })
preserved('multiline inline math', 'markdown', { 'Here is $a +', 'b = c$ followed by ' .. prose })
check('HTML attributes stay intact', 'markdown', {
  'Text with <span title="a title with many spaces">label</span> followed by ' .. prose,
}, function(output)
  contains(output, '<span title="a title with many spaces">')
  contains(output, 'label</span>')
end)

for _, unit in ipairs {
  '![image with spaces](image.png "title")',
  '<https://example.com/a/b/c/d/e/f>',
  '<person@example.com>',
  '`a | b`',
  '``literal ` backtick``',
  '$x + y = z$',
  'alpha\194\160beta',
  'é',
  '👩‍💻',
  vim.fn.nr2char(0xE000) .. 'literal',
} do
  check('atomic or Unicode text ' .. unit, 'markdown', { 'Before ' .. unit .. ' and after ' .. prose }, function(output)
    contains(output, unit)
    assert(not vim.deep_equal(output, { 'Before ' .. unit .. ' and after ' .. prose }), 'prose did not wrap')
  end)
end

preserved('nested link unsupported by inline parser', 'markdown', {
  'Before [nested [label] text](https://example.com/a_(b) "a title") and after ' .. prose,
})

for _, input in ipairs {
  { '# ' .. prose },
  { prose, '=================' },
  { '---', 'title: ' .. prose, '---' },
  { '+++', 'title = "' .. prose .. '"', '+++' },
  { '```python', prose, '```' },
  { '~~~', prose, '~~~' },
  { '    ' .. prose },
  { '| Header | Value |', '| --- | --- |', '| row | ' .. prose .. ' |' },
  { 'Header | Value', '--- | ---', 'row | ' .. prose },
  { '<div>', prose, '</div>' },
  { '[reference]: https://example.com/long/address "a title"' },
  { prose .. '  ', prose .. '\\' },
} do
  preserved('Markdown protected block ' .. checks, 'markdown', input)
end

preserved('prettier ignores next paragraph', 'markdown', { '<!-- prettier-ignore -->', '', prose })
preserved('prettier ignores whole list', 'markdown', { '<!-- prettier-ignore -->', '', '- ' .. prose, '- ' .. prose })
preserved('prettier ignore range', 'markdown', {
  '<!-- prettier-ignore-start -->',
  '',
  prose,
  '',
  prose,
  '',
  '<!-- prettier-ignore-end -->',
})

for _, language in ipairs { 'python', 'rust' } do
  local prefix = language == 'python' and '# ' or '// '
  preserved('format off region in ' .. language, language, { prefix .. 'fmt: off', prefix .. prose, prefix .. 'fmt: on' })
  preserved('unclosed format off in ' .. language, language, { prefix .. 'fmt: off', prefix .. prose })
end

local function docstring(body, opening)
  local lines = { 'def work():', '    ' .. (opening or '"""Summary.') }
  for _, line in ipairs(body) do
    lines[#lines + 1] = line == '' and '' or '    ' .. line
  end
  vim.list_extend(lines, { '    """', '    pass' })
  return lines
end

local doctest = docstring { '', '>>> print("Hello")', prose, '', prose }
check('doctest output without Examples heading', 'python', doctest, function(output)
  contains(output, '    >>> print("Hello")\n    ' .. prose .. '\n')
  assert(not vim.deep_equal(output, doctest), 'ordinary prose after the doctest did not reflow')
end)

for _, heading in ipairs { 'Note:', 'Notes:' } do
  local code = '            print("' .. prose .. '")'
  check('prose paragraphs and code in ' .. heading, 'python', docstring {
    '',
    heading,
    '    Keep this in mind: ' .. prose,
    '',
    '    ' .. prose,
    '',
    code:sub(5),
  }, function(output)
    contains(output, '    ' .. heading .. '\n        Keep this in mind: These words')
    contains(output, '\n\n        These words explain the behavior')
    contains(output, code)
    for _, line in ipairs(output) do
      if line ~= code then
        assert(vim.fn.strdisplaywidth(line) <= 40, 'note prose did not wrap')
        assert(not line:match '^            %S', 'note prose acquired field indentation')
      end
    end
  end)
end

check(
  'field descriptions starting on the next line',
  'python',
  docstring {
    '',
    'Args:',
    '    value:',
    '        ' .. prose,
    '    other:',
    '        ' .. prose,
  },
  function(output)
    contains(output, '        value: These words')
    contains(output, '        other: These words')
    for _, line in ipairs(output) do
      assert(vim.fn.strdisplaywidth(line) <= 40, 'field did not wrap')
    end
  end
)

preserved(
  'Sphinx fields retained as unsupported structure',
  'python',
  docstring {
    '',
    ':param value: ' .. prose,
    ':returns: ' .. prose,
  }
)
preserved(
  'code examples inside Args',
  'python',
  docstring {
    '',
    'Args:',
    '    value: Brief.',
    '',
    '        ```python',
    '        ' .. prose,
    '        ```',
  }
)
preserved(
  'field type containing a colon',
  'python',
  docstring {
    '',
    'Args:',
    '    value (Literal["a: b"]): ' .. prose,
  }
)
preserved(
  'literal block after double colon',
  'python',
  docstring {
    '',
    'Example::',
    '',
    '    ' .. prose,
  }
)

for _, input in ipairs {
  { 'value = """' .. prose .. '"""' },
  { 'def work():', '    f"""' .. prose .. '"""', '    pass' },
  { 'def work():', '    b"""' .. prose .. '"""', '    pass' },
  { '"""First""" """' .. prose .. '"""' },
  { 'x = 1  # ' .. prose },
  { 'def work():', '    """' .. prose, '    """ # noqa: D205', '    pass' },
} do
  preserved('non-prose or attached syntax in Python ' .. checks, 'python', input)
end

for _, quote in ipairs { '"""', "'''", 'r"""', "u'''" } do
  local close = quote:sub(-3)
  check('Python quote style ' .. quote, 'python', { quote .. prose .. close }, function(output)
    assert(output[1]:sub(1, #quote) == quote and output[1] ~= quote, 'opening quote moved')
    assert(output[#output] == close, 'closing quote changed')
    local root = vim.treesitter.get_string_parser(table.concat(output, '\n'), 'python'):parse()[1]:root()
    assert(not root:has_error(), 'Python syntax broke')
  end)
end

for _, marker in ipairs { '//', '///', '//!', '////' } do
  check('Rust line comment ' .. marker, 'rust', { marker .. ' ' .. prose }, function(output)
    assert(#output > 1, 'comment did not wrap')
    for _, line in ipairs(output) do
      assert(line:sub(1, #marker + 1) == marker .. ' ', 'comment kind changed')
    end
  end)
end
for _, input in ipairs {
  { '/*', prose, '*/', 'fn work() {}' },
  { '/**', ' * ' .. prose, ' *', ' * ' .. prose, ' */', 'fn work() {}' },
} do
  check('Rust block comment ' .. checks, 'rust', input, function(output)
    assert(not vim.deep_equal(output, input), 'block comment did not wrap')
    contains(output, 'fn work() {}')
    local root = vim.treesitter.get_string_parser(table.concat(output, '\n'), 'rust'):parse()[1]:root()
    assert(not root:has_error(), 'Rust syntax broke')
  end)
end
preserved('nested Rust comments', 'rust', { '/* ' .. prose, '    /* ' .. prose .. ' */', '*/', 'fn work() {}' })

for _, control in ipairs {
  { 'markdown', '<!-- prettier-ignore-start -->', '<!-- prettier-ignore-end -->', '' },
  { 'markdown', '<!-- reflow: off -->', '<!-- reflow: on -->', '' },
  { 'python', '# fmt: off', '# fmt: on', '# ' },
  { 'rust', '// reflow: off', '// reflow: on', '// ' },
} do
  local language, opening, closing, prefix = unpack(control)
  check('resume after ignore in ' .. language .. opening, language, {
    prefix .. prose,
    '',
    opening,
    prefix .. prose,
    closing,
    '',
    prefix .. prose,
  }, function(output)
    contains(output, opening .. '\n' .. prefix .. prose .. '\n' .. closing)
    assert(output[1] ~= prefix .. prose, 'preceding prose was unnecessarily skipped')
    assert(output[#output] ~= prefix .. prose, 'formatting did not resume')
  end)
end

for _, unit in ipairs {
  '[link](https://example.com/a%20b "a title")',
  '`command --flag=value`',
  '$a + b = c$',
  '<span class="long class names">',
  '👩‍💻',
  'alpha\194\160beta',
} do
  for _, width in ipairs { 1, 8, 20, 40, 98, 120 } do
    local input = { 'Some words ' .. unit .. ' followed by more words.' }
    check('width boundary ' .. width .. unit, 'markdown', input, function(output)
      contains(output, unit)
      assert(table.concat(output, ' ') == input[1], 'text changed at a width boundary')
    end, width)
  end
end

for _, input in ipairs {
  {},
  { '' },
  { '', '', '' },
  { '\t' },
  { '> ' .. prose .. '  ', '> ' .. prose .. '\\' },
  { '> ```python', '> ' .. prose, '> ```' },
  { '- Item', '', '  ```python', '  ' .. prose, '  ```' },
  { '<script>', prose, '</script>' },
} do
  preserved('empty, escaped or nested protected content ' .. checks, 'markdown', input)
end

check('escaped currency is prose', 'markdown', { 'Escaped math costs \\$5 and \\$10 for each item.' }, function(output)
  assert(table.concat(output, ' ') == 'Escaped math costs \\$5 and \\$10 for each item.', 'escaped currency changed')
end)

local saved_ambiwidth = vim.o.ambiwidth
vim.o.ambiwidth = 'double'
check('wide ambiguous characters in protected units', 'markdown', { 'Before `some code with spaces` after ' .. prose }, function(output)
  contains(output, '`some code with spaces`')
  for _, line in ipairs(output) do
    assert(vim.fn.strdisplaywidth(line) <= 40, 'display width exceeded')
  end
end)
vim.o.ambiwidth = saved_ambiwidth

check('selection, buffer state, undo and redo', 'markdown', { prose, '', prose }, function()
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { prose, '', prose })
  vim.cmd 'let &l:undolevels = &l:undolevels'
  local buffer = vim.api.nvim_get_current_buf()
  local buffers = #vim.api.nvim_list_bufs()
  vim.fn.setreg('a', 'keep this register')
  vim.bo.textwidth, vim.bo.formatprg = 73, 'must-not-run'

  vim.cmd '3,3Reflow 30'
  local result = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  assert(result[1] == prose and #result > 3, 'selection crossed its boundary')
  assert(vim.api.nvim_get_current_buf() == buffer and #vim.api.nvim_list_bufs() == buffers, 'scratch buffer leaked')
  assert(vim.bo.textwidth == 73 and vim.bo.formatprg == 'must-not-run', 'source options changed')
  assert(vim.fn.getreg 'a' == 'keep this register', 'register changed')

  vim.cmd 'undo'
  assert(vim.deep_equal(vim.api.nvim_buf_get_lines(0, 0, -1, false), { prose, '', prose }), 'undo was not atomic')
  vim.cmd 'redo'
  assert(vim.deep_equal(vim.api.nvim_buf_get_lines(0, 0, -1, false), result), 'redo did not restore reflow')
  -- Leave a result matching the outer harness's whole-buffer idempotence check.
  vim.cmd 'Reflow 40'
end)

checks = checks + 1
local parser = vim.treesitter.get_string_parser
vim.cmd 'enew!'
vim.bo.filetype = 'markdown'
vim.api.nvim_buf_set_lines(0, 0, -1, false, { prose })
local buffers_before = #vim.api.nvim_list_bufs()
vim.treesitter.get_string_parser = function()
  error 'missing parser'
end
local ok = pcall(vim.cmd, 'Reflow')
vim.treesitter.get_string_parser = parser
assert(not ok, 'missing parser was silently ignored')
assert(vim.deep_equal(vim.api.nvim_buf_get_lines(0, 0, -1, false), { prose }), 'failed operation edited the buffer')
assert(#vim.api.nvim_list_bufs() == buffers_before, 'failed operation leaked a scratch buffer')

for _, message in ipairs(failures) do
  print('FAIL: ' .. message)
end
assert(#failures == 0, ('%d / %d edge cases failed'):format(#failures, checks))
print(('PASS: %d reflow edge cases, including repeated reflow'):format(checks))
