-- Run: NVIM_LOG_FILE=/tmp/nvim-math-test.log nvim -n --clean --headless -i NONE -l tests/docstring_math.lua
vim.opt.runtimepath:prepend(vim.fn.getcwd())
vim.opt.runtimepath:append(vim.fn.getcwd() .. '/after')
vim.opt.runtimepath:append(vim.fn.stdpath('data') .. '/site')
vim.opt.runtimepath:append(vim.fn.stdpath('data') .. '/lazy/nvim-treesitter/runtime')
vim.opt.runtimepath:append(vim.fn.stdpath('data') .. '/lazy/render-markdown.nvim')

local spec = dofile 'lua/custom/plugins/render-markdown.lua'
spec.opts.file_types = spec.ft
spec.opts.debounce = 0
vim.g.render_markdown_config = spec.opts
vim.cmd 'runtime plugin/render-markdown.lua'
assert(vim.fn.executable 'utftex' == 1, 'Install utftex before running this check')
assert(#require('render-markdown.state').validate() == 0, 'Invalid renderer configuration')

local function check_math(filetype, lines, expected)
  vim.cmd.enew()
  vim.o.lines = 60
  vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
  vim.bo.filetype = filetype
  vim.api.nvim_win_set_cursor(0, { 1, 0 })

  local buffer = vim.api.nvim_get_current_buf()
  local parser = vim.treesitter.get_parser(buffer, filetype)
  parser:parse(true)
  local formulas = {}
  parser:for_each_tree(function(tree, language)
    if language:lang() == 'latex' then
      formulas[#formulas + 1] = vim.treesitter.get_node_text(tree:root(), buffer)
    end
  end)
  table.sort(formulas)
  table.sort(expected)
  assert(vim.deep_equal(formulas, expected), filetype .. ': incorrect math injection: ' .. vim.inspect(formulas))

  local namespace = vim.api.nvim_get_namespaces()['render-markdown.nvim']
  local function get_math_marks()
    return vim.api.nvim_buf_get_extmarks(buffer, namespace, 0, -1, { details = true })
  end

  assert(not require('render-markdown.state').get(buffer).enabled, 'Rendering should default to off')
  assert(#get_math_marks() == 0, 'Disabled preview has math decorations')
  vim.cmd 'RenderMarkdown buf_toggle'
  assert(vim.wait(2000, function()
    return #get_math_marks() >= #expected
  end, 10), 'Docstring formulas did not render after toggling on')

  local inline, fraction = false, false
  for _, mark in ipairs(get_math_marks()) do
    local details = mark[4]
    inline = inline or (details.virt_text and details.virt_text[1][1] == 'α' and details.conceal == '')
    fraction = fraction or (details.virt_lines and vim.inspect(details.virt_lines):find('─', 1, true))
  end
  assert(inline and fraction, 'Expected Unicode inline math and a fraction on virtual lines')
  assert(vim.deep_equal(lines, vim.api.nvim_buf_get_lines(buffer, 0, -1, false)), 'Rendering edited the source')

  vim.cmd 'RenderMarkdown buf_toggle'
  assert(vim.wait(1000, function()
    return #get_math_marks() == 0
  end, 10), 'Disabling the preview left math decorations behind')
end

check_math('python', {
  '# Leading module comment.',
  'r"""Module $\\alpha$."""',
  'assigned = """Not a docstring $not_math$."""',
  'def work():',
  '    # Leading function comment.',
  '    r"""Summary $\\beta$.',
  '',
  '    $$',
  '    \\frac{1}{x}',
  '    $$',
  '    """',
  '    """Later string $not_math$."""',
  '    return "$not_math$"',
  'class Example:',
  '    """Class $\\gamma$."""',
  '    def method(self):',
  "        r'''Method $\\delta$.'''",
  'if True:',
  '    """Not a docstring $not_math$."""',
  'def formatted():',
  '    f"""Not a docstring $not_math$."""',
  'def binary():',
  '    b"""Not a docstring $not_math$."""',
  'def concatenated():',
  '    """First""" """$not_math$"""',
}, { '$\\alpha$', '$\\beta$', '$$\n    \\frac{1}{x}\n    $$', '$\\gamma$', '$\\delta$' })

check_math('rust', {
  '// Ordinary comment $not_math$.',
  '//! Module $\\alpha$.',
  '/// Function $\\beta$.',
  '/// $$\\frac{1}{x}$$',
  'fn work() {}',
  '/** Block $\\gamma$.',
  '$$',
  '\\frac{1}{y}',
  '$$',
  '*/',
  'struct Example;',
  'mod inner {',
  '    /*! Inner $\\delta$ */',
  '    /// Method $\\epsilon$.',
  '    fn method() {}',
  '}',
  '//// Not a doc comment $not_math$.',
  '/* Ordinary block $not_math$ */',
  '/*** Not a doc comment $not_math$ */',
  'const TEXT: &str = "$not_math$";',
}, { '$\\alpha$', '$\\beta$', '$$\\frac{1}{x}$$', '$\\gamma$', '$$\n\\frac{1}{y}\n$$', '$\\delta$', '$\\epsilon$' })
print 'PASS: Python and Rust doc math, Unicode rendering, unchanged source, and preview toggle'
