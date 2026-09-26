-- Run: NVIM_LOG_FILE=/tmp/nvim-reflow-test.log nvim -n --clean --headless -i NONE -l tests/reflow.lua
vim.opt.runtimepath:prepend(vim.fn.getcwd())
vim.opt.runtimepath:append(vim.fn.stdpath 'data' .. '/site')
dofile 'after/plugin/reflow.lua'

local prose = 'These words explain the behavior in enough detail to require several lines at a narrow width.'
local function reflow(language, lines, command)
  vim.cmd 'enew!'
  vim.bo.filetype = language
  vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
  vim.cmd 'let &l:undolevels = &l:undolevels'
  vim.bo.textwidth = 77
  vim.bo.formatexpr = 'InvalidFormatter()'
  vim.cmd(command or 'Reflow 45')
  assert(vim.bo.textwidth == 77 and vim.bo.formatexpr == 'InvalidFormatter()', 'Buffer options changed')
  return vim.api.nvim_buf_get_lines(0, 0, -1, false)
end

local function contains(lines, text)
  assert(table.concat(lines, '\n'):find(text, 1, true), 'Missing or broken text: ' .. text)
end

local function within_width(lines, width)
  for _, line in ipairs(lines) do
    assert(vim.fn.strdisplaywidth(line) <= width, 'Overlong line: ' .. line)
  end
end

local units = {
  '[link with several words](https://example.com/a "a title")',
  '`code with several spaces`',
  '``code with `nested` backticks``',
  '$a + b + c = d$',
  '[reference text][reference label]',
  '![image text](image.png)',
}
local markdown = { '# Heading', '', prose, '', '- ' .. prose, '', '> ' .. prose, '' }
for _, unit in ipairs(units) do
  vim.list_extend(markdown, { 'Words before ' .. unit .. ' and words after it to wrap.', '' })
end
local protected = {
  '```python',
  'print("' .. prose .. '")',
  '```',
  '',
  '| Header | Value |',
  '| --- | --- |',
  '| A | ' .. prose .. ' |',
  '',
  'Header | Value',
  ':--- | ---:',
  'A | ' .. prose,
  '',
  'Hard line break here.  ',
  'This must stay on the next line.',
  '',
  '$$',
  'a + b + c = d',
  '$$',
}
vim.list_extend(markdown, protected)
local wrapped = reflow('markdown', markdown)
for _, unit in ipairs(units) do
  contains(wrapped, unit)
end
contains(wrapped, table.concat(protected, '\n'))
contains(wrapped, '- These words explain')
contains(wrapped, '> These words explain')
assert(#wrapped > #markdown, 'Markdown was not wrapped')
vim.cmd 'Reflow 45'
assert(vim.deep_equal(wrapped, vim.api.nvim_buf_get_lines(0, 0, -1, false)), 'Markdown is not idempotent')
vim.cmd 'undo'
assert(vim.deep_equal(markdown, vim.api.nvim_buf_get_lines(0, 0, -1, false)), 'Undo did not restore the complete file')

local contents = {
  '- [Choosing the data](#choosing-the-data)',
  '- [Editing raw inputs](#editing-raw-inputs)',
  '  - [Local names and source filenames](#local-names-and-source-filenames)',
  '- [Following the code](#following-the-code)',
}
for _, language in ipairs { 'markdown', 'python', 'rust' } do
  local prefix = ({ markdown = '', python = '# ', rust = '/// ' })[language]
  local input = vim.tbl_map(function(line)
    return prefix .. line
  end, contents)
  local output = reflow(language, input, 'Reflow')
  assert(vim.deep_equal(input, output), language .. ': nested list entries changed or duplicated')
end

local reference_paragraph = {
  'The four Excel reference tables come from Census [Population Division Working Paper',
  '56][working-paper-56], published in 2002. The years in their local names identify the populations',
  'described, not the publication year; all four use 100-percent census counts. Their table numbers',
  'retain the direct connection to the source publication. The builders keep the original URLs beside',
  'these local names.',
}
wrapped = reflow('markdown', reference_paragraph, 'Reflow')
contains(wrapped, '[Population Division Working Paper 56][working-paper-56]')
within_width(wrapped, 98)
assert(table.concat(wrapped, ' ') == table.concat(reference_paragraph, ' '), 'Reference paragraph content changed')
vim.cmd 'Reflow'
assert(vim.deep_equal(wrapped, vim.api.nvim_buf_get_lines(0, 0, -1, false)), 'Multiline reference reflow is not idempotent')

local state_comparisons = {
  'State comparisons follow the same principle as the modern tables: counts for smaller units must',
  "sum to their state's counts. This applies to all source count columns and derived study counts for",
  '1980 counties and every supported level below the state in 1990. Processing loads the national',
  'NHGIS state tables before reading the smaller areas, comparing their total, non-Hispanic White,',
  'and non-Hispanic Black counts with',
  '[Census Working Paper 56](https://www.census.gov/library/working-papers/2002/demo/POP-twps0056.html),',
  'Table E-3 for 1980 and Table E-1 for 1990. As with the modern references, these are separate',
  'publications of Census counts rather than independent counts of residents.',
  'The state tables are then reused for these comparisons and saved as the national state outputs,',
  'without reading their archives again.',
}
for _, language in ipairs { 'markdown', 'python', 'rust' } do
  local prefix = ({ markdown = '', python = '# ', rust = '/// ' })[language]
  local input = vim.tbl_map(function(line)
    return prefix .. line
  end, state_comparisons)
  local output = reflow(language, input, 'Reflow')
  local paragraphs = {}
  for _, line in ipairs(output) do
    assert(line:sub(1, #prefix) == prefix, 'Reflow changed a comment prefix')
    local text = line:sub(#prefix + 1)
    assert(not text:match '^%s', 'A year in prose introduced numbered-list indentation')
    if text ~= state_comparisons[6] then
      within_width({ line }, 98)
    end
    paragraphs[#paragraphs + 1] = text
  end
  assert(table.concat(paragraphs, ' ') == table.concat(state_comparisons, ' '), 'Year-containing prose changed')
  contains(output, prefix .. state_comparisons[6])
  vim.cmd 'Reflow'
  assert(vim.deep_equal(output, vim.api.nvim_buf_get_lines(0, 0, -1, false)), 'Year-containing prose is not idempotent')
end

for _, marker in ipairs { '1. ', '1) ' } do
  wrapped = reflow('markdown', { marker .. prose })
  assert(wrapped[1]:sub(1, #marker) == marker, 'Ordered-list marker changed')
  assert(#wrapped > 1, 'Ordered list was not wrapped')
  for row = 2, #wrapped do
    assert(wrapped[row]:match '^   %S', 'Ordered-list continuation lost its indentation')
  end
  within_width(wrapped, 45)
end

for _, case in ipairs {
  { 'markdown', '', '' },
  { 'markdown', '- ', '  ' },
  { 'markdown', '> ', '> ' },
  { 'markdown', '> > ', '> > ' },
  { 'python', '# ', '# ' },
  { 'rust', '/// ', '/// ' },
} do
  for _, destination in ipairs { '[working-paper-56]', '(https://example.com/working-paper-56)' } do
    local input = {
      case[2] .. 'See [Population Division Working Paper',
      case[3] .. '56]' .. destination .. ' for details.',
    }
    local output = reflow(case[1], input, 'Reflow')
    assert(
      vim.deep_equal(output, { case[2] .. 'See [Population Division Working Paper 56]' .. destination .. ' for details.' }),
      'Multiline link text or its surrounding list/comment/quote prefix changed'
    )
  end
end

local python = {
  'def work(x):',
  '    """' .. prose,
  '',
  '    Args:',
  '        x (str | None): ' .. prose,
  '',
  '    Returns:',
  '        int: ' .. prose,
  '',
  '    Examples:',
  '        >>> print("' .. prose .. '")',
  '    """',
  '    value = """' .. prose .. '"""',
  '    # ' .. prose,
  '    # noqa: this directive must remain exactly as written regardless of width',
  '    return value  # ' .. prose,
}
wrapped = reflow('python', python)
contains(wrapped, '        x (str | None): These words explain\n            the behavior')
contains(wrapped, '        int: These words explain the behavior\n            in enough detail')
contains(wrapped, '    # These words explain the behavior in\n    # enough detail')
for _, row in ipairs { 11, 13, 15, 16 } do
  contains(wrapped, python[row])
end
vim.cmd 'Reflow 45'
assert(vim.deep_equal(wrapped, vim.api.nvim_buf_get_lines(0, 0, -1, false)), 'Python is not idempotent')
local parsed = vim.treesitter.get_string_parser(table.concat(wrapped, '\n'), 'python'):parse()[1]:root()
assert(not parsed:has_error(), 'Reflow broke Python syntax')

local published_boundaries = {
  'def build():',
  '    """Build selected TIGER boundaries and the supporting published data.',
  '',
  '    Args:',
  '        directories (RawDataSubdirectories): Folder settings relative to the raw-data root.',
  '        geography_requests (tuple[GeographyRequest, ...]): Shared node and definition selections.',
  '        study_area_type (StudyAreaType): county needs no metro workbook; the other modes require it.',
  '',
  '    Returns:',
  '        list[PublicFileRequest]: Boundaries and reference tables, plus original STF1A records',
  '            for 1980 tract/BNA matching.',
  '    """',
  '    pass',
}
wrapped = reflow('python', published_boundaries, 'Reflow')
assert(wrapped[2] == published_boundaries[2], 'Reflow moved a fitting summary away from its opening quotes')
within_width(wrapped, 98)
contains(wrapped, published_boundaries[5])
contains(wrapped, published_boundaries[6])
contains(wrapped, '        study_area_type (StudyAreaType): county needs no metro workbook; the other modes require\n            it.')
contains(wrapped, '        list[PublicFileRequest]: Boundaries and reference tables, plus original STF1A records for\n            1980 tract/BNA matching.')
vim.cmd 'Reflow'
assert(vim.deep_equal(wrapped, vim.api.nvim_buf_get_lines(0, 0, -1, false)), 'Docstring quote placement is not idempotent')

local numpy = {
  'def work(x):',
  '    """Summary.',
  '',
  '    Parameters',
  '    ----------',
  '    x : str',
  '        ' .. prose,
  '',
  '    Returns',
  '    -------',
  '    int',
  '        ' .. prose,
  '    """',
  '    pass',
}
wrapped = reflow('python', numpy)
within_width(wrapped, 45)
contains(wrapped, '    x : str\n        These words')
contains(wrapped, '    int\n        These words')
local single = reflow('python', { '"""' .. string.rep('word ', 18) .. 'end."""' })
within_width(single, 45)
assert(#single > 1, 'Single-line docstring was not wrapped')
assert(single[1]:sub(1, 3) == '"""' and single[1] ~= '"""', 'Wrapping a long summary moved its opening quotes')
wrapped = reflow('python', { '"""Summary.', '', 'Args:', '    value (str | None): ' .. prose, '"""' }, 'Reflow 20')
contains(wrapped, '    value (str | None):')

local doc_table = {
  '"""Summary.',
  '',
  'Args:',
  '    value: ' .. prose,
  '',
  '        Header | Value',
  '        --- | ---',
  '        A | ' .. prose,
  '',
  '        print("' .. prose .. '")',
  '"""',
}
wrapped = reflow('python', doc_table)
contains(wrapped, table.concat(vim.list_slice(doc_table, 6, 8), '\n'))
contains(wrapped, doc_table[10])

for _, language in ipairs { 'python', 'rust' } do
  local prefix = language == 'python' and '# ' or '/// '
  local table_comment = {}
  for _, line in ipairs { prose, '', 'Header | Value', '--- | ---', 'A | ' .. prose } do
    table_comment[#table_comment + 1] = prefix .. line
  end
  wrapped = reflow(language, table_comment)
  contains(wrapped, table.concat(vim.list_slice(table_comment, 3), '\n'))
  wrapped = reflow(language, { prefix .. 'Words before ' .. table.concat(units, ' and ') .. ' and after.' })
  for _, unit in ipairs(units) do
    contains(wrapped, unit)
  end
end

local rust = {
  '//! ' .. prose,
  '/// ' .. prose,
  '// ' .. prose,
  'fn work() { let text = "' .. prose .. '"; }',
  '/**',
  ' * ' .. prose,
  ' */',
  '/* ' .. prose .. ' */',
  '//// ' .. prose,
  '/*** ' .. prose .. ' */',
}
wrapped = reflow('rust', rust)
contains(wrapped, rust[4])
for _, prefix in ipairs { '//! ', '/// ', '// ', ' * ', ' ' } do
  contains(wrapped, prefix .. 'These words explain')
end
contains(wrapped, '//// These words explain')
contains(wrapped, '/***\n')
parsed = vim.treesitter.get_string_parser(table.concat(wrapped, '\n'), 'rust'):parse()[1]:root()
assert(not parsed:has_error(), 'Reflow broke Rust syntax')
vim.cmd 'undo'
assert(vim.deep_equal(rust, vim.api.nvim_buf_get_lines(0, 0, -1, false)), 'Multiple comments need multiple undos')

wrapped = reflow('markdown', { prose, '', prose }, '3,3Reflow 45')
assert(wrapped[1] == prose and #wrapped > 3, 'Range changed the wrong paragraph')
wrapped = reflow('python', { '# ' .. prose, '', '# ' .. prose }, '3,3Reflow 45')
assert(wrapped[1] == '# ' .. prose and #wrapped > 3, 'Range changed the wrong comment')
wrapped = reflow('markdown', { string.rep('a', 96) .. ' bb' }, 'Reflow')
within_width(wrapped, 98)
assert(#wrapped == 2, 'Default width is not 98')
for _, width in ipairs { '0', '-1', 'no', '1.5' } do
  assert(not pcall(vim.cmd, 'Reflow ' .. width), 'Invalid width accepted: ' .. width)
end
local broken = { 'def broken(:', '    # ' .. prose }
assert(not pcall(reflow, 'python', broken), 'Invalid source was reformatted')
assert(vim.deep_equal(broken, vim.api.nvim_buf_get_lines(0, 0, -1, false)), 'Failed reflow changed the source')
print 'PASS: prose reflow preserves syntax, structured fields, inline units, ranges, and undo'
