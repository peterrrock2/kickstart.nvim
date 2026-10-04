-- Run: nvim -n --clean --headless -i NONE -l tests/docstring_hover.lua
vim.opt.runtimepath:prepend(vim.fn.getcwd())
local to_markdown = require('custom.docstring_hover').to_markdown

local hover = table.concat({
  '(function) def ratio(d: Unknown) -> None',
  '',
  'For :math:`D`, see :func:`~pkg.area`, the score is',
  '',
  '.. math::',
  '    :label: ratio',
  '',
  '    \\frac{a}{b}',
  '',
  '    = c,',
  '',
  'where :math:`(0, 1]`.',
  '',
  '.. math:: x^2',
}, '\n')

local expected = {
  '```python',
  '(function) def ratio(d: Unknown) -> None',
  '```',
  '',
  'For $D$, see `pkg.area`, the score is',
  '',
  '$$',
  '\\frac{a}{b}',
  '= c,',
  '$$',
  '',
  'where $(0, 1]$.',
  '',
  '$$',
  'x^2',
  '$$',
}
local actual = to_markdown(hover)
assert(vim.deep_equal(actual, expected), vim.inspect(actual))
assert(vim.deep_equal(to_markdown '(variable) x: int', { '```python', '(variable) x: int', '```' }))
print 'PASS: RST math roles and directives become Markdown math'
