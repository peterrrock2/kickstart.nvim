vim.opt.runtimepath:prepend(vim.fn.getcwd())

local parse = require('custom.pyproject_info')._parse_dependencies
local dependencies = parse {
  '[project]',
  'dependencies = [',
  '  "requests>=2",',
  '  "httpx[http2]~=0.27; python_version >= \'3.11\'",',
  ']',
  '[project.optional-dependencies]',
  'test = ["pytest>=8", "coverage"]',
  '[tool.poetry.dependencies]',
  'python = "^3.12"',
  'rich = "^13"',
  'local = { path = "../local" }',
  '[tool.poetry.group.dev.dependencies]',
  'ruff = "^0.5"',
  '[dependency-groups]',
  'lint = [',
  '  "mypy>=1",',
  '  { include-group = "test" },',
  ']',
}

local expected = {
  { name = 'requests', lnum = 3 },
  { name = 'httpx', lnum = 4 },
  { name = 'pytest', lnum = 7 },
  { name = 'coverage', lnum = 7 },
  { name = 'rich', lnum = 10 },
  { name = 'local', lnum = 11 },
  { name = 'ruff', lnum = 13 },
  { name = 'mypy', lnum = 16 },
}

assert(#dependencies == #expected, ('expected %d dependencies, got %d'):format(#expected, #dependencies))
for index, dependency in ipairs(dependencies) do
  assert(dependency.name == expected[index].name, ('unexpected dependency at %d'):format(index))
  assert(dependency.lnum == expected[index].lnum, ('unexpected line at %d'):format(index))
end

local special_dependencies = parse {
  '[project]',
  'dependencies = [',
  '  "pyogrio>=0.13; python_version >= \'3.14\'",',
  '  "gerrychain @ git+https://example.com/gerrychain.git",',
  ']',
}
assert(special_dependencies[1].declared == '>=0.13', 'conditional version was not parsed')
assert(special_dependencies[1].conditional, 'environment marker was not parsed')
assert(special_dependencies[2].source == 'git', 'Git dependency was not parsed')

local bufnr = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_name(bufnr, '/tmp/pyproject-info-test/pyproject.toml')
vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
  '[project]',
  'dependencies = [',
  '  "requests>=2",',
  '  "httpx>=0.27; python_version >= \'3.14\'",',
  '  "gerrychain @ git+https://example.com/gerrychain.git",',
  ']',
  '[tool.poetry.dependencies]',
  'rich = "^13"',
})

local original_system = vim.system
vim.system = function(command, _, callback)
  local is_outdated = vim.tbl_contains(command, '--outdated')
  callback {
    code = 0,
    stdout = vim.json.encode(is_outdated and {
      { name = 'requests', version = '2.31.0', latest_version = '2.32.0' },
    } or {
      { name = 'requests', version = '2.31.0' },
      { name = 'httpx', version = '0.28.0' },
      { name = 'gerrychain', version = '1.0.0' },
      { name = 'rich', version = '13.9.0' },
    }),
    stderr = '',
  }
  return {}
end

require('custom.pyproject_info').refresh(bufnr)
local namespace = vim.api.nvim_get_namespaces()['pyproject-package-info']
assert(
  vim.wait(1000, function()
    return #vim.api.nvim_buf_get_extmarks(bufnr, namespace, 0, -1, {}) == 4
  end),
  'timed out waiting for package annotations'
)
vim.system = original_system

local annotations = {}
for _, extmark in ipairs(vim.api.nvim_buf_get_extmarks(bufnr, namespace, 0, -1, { details = true })) do
  annotations[extmark[2] + 1] = extmark[4].virt_text[1][1]
end

assert(annotations[3]:match '2%.32%.0', 'latest package annotation missing')
assert(not annotations[3]:match '2%.31%.0', 'installed version should not replace the declaration')
assert(annotations[4]:match 'conditional', 'conditional package annotation missing')
assert(annotations[5]:match 'Git', 'Git package annotation missing')
assert(annotations[8]:match '%^13', 'declared up-to-date version missing')
