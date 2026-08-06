local M = {}

local namespace = vim.api.nvim_create_namespace 'pyproject-package-info'
local revisions = {}

local function normalize(name)
  return (name:lower():gsub('[-_.]+', '-'))
end

local function quoted_strings(line)
  local values = {}
  local outside = {}
  local i = 1

  while i <= #line do
    local char = line:sub(i, i)
    if char == '#' then
      break
    elseif char == '"' or char == "'" then
      local quote = char
      local value = {}
      outside[#outside + 1] = ' '
      i = i + 1

      while i <= #line do
        char = line:sub(i, i)
        if quote == '"' and char == '\\' and i < #line then
          value[#value + 1] = line:sub(i, i + 1)
          outside[#outside + 1] = '  '
          i = i + 2
        elseif char == quote then
          outside[#outside + 1] = ' '
          i = i + 1
          break
        else
          value[#value + 1] = char
          outside[#outside + 1] = ' '
          i = i + 1
        end
      end

      values[#values + 1] = table.concat(value)
    else
      outside[#outside + 1] = char
      i = i + 1
    end
  end

  return values, table.concat(outside)
end

local function add_dependency(dependencies, seen, name, declared, lnum, metadata)
  if not name or name == '' then
    return
  end

  local key = normalize(name)
  local occurrence = key .. '\0' .. lnum
  if not seen[occurrence] then
    seen[occurrence] = true
    dependencies[#dependencies + 1] = {
      name = name,
      key = key,
      declared = declared,
      lnum = lnum,
      conditional = metadata and metadata.conditional or false,
      source = metadata and metadata.source or nil,
    }
  end
end

local function add_requirement(dependencies, seen, requirement, lnum)
  local _, name_end, name = requirement:find '^%s*([%w][%w._-]*)'
  if not name then
    return
  end

  local remainder = vim.trim(requirement:sub(name_end + 1))
  if remainder:sub(1, 1) == '[' then
    local extras_end = remainder:find(']', 1, true)
    remainder = extras_end and vim.trim(remainder:sub(extras_end + 1)) or remainder
  end

  local marker_start = remainder:find(';', 1, true)
  local declared = vim.trim(marker_start and remainder:sub(1, marker_start - 1) or remainder)
  local target = declared:match '^@%s*(%S+)'
  local source = target and (target:match '^git%+' and 'git' or 'direct') or nil
  add_dependency(dependencies, seen, name, declared, lnum, {
    conditional = marker_start ~= nil,
    source = source,
  })
end

local function is_poetry_section(section)
  return section == 'tool.poetry.dependencies' or section == 'tool.poetry.dev-dependencies' or section:match '^tool%.poetry%.group%..+%.dependencies$'
end

local function parse_dependencies(lines)
  local dependencies = {}
  local seen = {}
  local section = ''
  local in_array = false

  for lnum, line in ipairs(lines) do
    local values, outside = quoted_strings(line)
    local header = outside:match '^%s*%[([^%]]+)%]%s*$'

    if header then
      section = vim.trim(header)
      in_array = false
    elseif is_poetry_section(section) then
      local bare_name = line:match '^%s*([%w_.-]+)%s*='
      local quoted_name = line:match '^%s*["\']([^"\']+)["\']%s*='
      local name = bare_name or quoted_name
      local source = outside:match '[{,]%s*path%s*=' and 'path' or outside:match '[{,]%s*git%s*=' and 'git' or outside:match '[{,]%s*url%s*=' and 'url'
      local declared = values[quoted_name and 2 or 1] or ''

      if name and normalize(name) ~= 'python' then
        add_dependency(dependencies, seen, name, declared, lnum, {
          conditional = outside:match '[{,]%s*markers%s*=' ~= nil,
          source = source,
        })
      end
    else
      local starts_array = section == 'project' and outside:match '^%s*dependencies%s*=%s*%['
        or section == 'project.optional-dependencies' and outside:match '^%s*[%w_.-]+%s*=%s*%['
        or section == 'dependency-groups' and outside:match '^%s*[%w_.-]+%s*=%s*%['
        or section == 'tool.pdm.dev-dependencies' and outside:match '^%s*[%w_.-]+%s*=%s*%['
        or section == 'tool.uv' and outside:match '^%s*dev%-dependencies%s*=%s*%['

      if starts_array then
        in_array = true
      end

      if in_array and not outside:match 'include%-group%s*=' then
        for _, value in ipairs(values) do
          add_requirement(dependencies, seen, value, lnum)
        end
      end

      if in_array and outside:find(']', 1, true) then
        in_array = false
      end
    end
  end

  return dependencies
end

local function decode_packages(result)
  if result.code ~= 0 then
    return nil, vim.trim(result.stderr or result.stdout or 'uv failed')
  end

  local ok, packages = pcall(vim.json.decode, result.stdout)
  if not ok or type(packages) ~= 'table' then
    return nil, 'uv returned invalid JSON'
  end

  local by_name = {}
  for _, package in ipairs(packages) do
    if package.name then
      by_name[normalize(package.name)] = package
    end
  end
  return by_name
end

local function render(bufnr, dependencies, installed, outdated)
  local by_line = {}

  for _, dependency in ipairs(dependencies) do
    local current = installed[dependency.key]
    local update = outdated[dependency.key]
    local text
    local highlight

    if dependency.source then
      local label = dependency.source == 'git' and 'Git dependency' or dependency.source .. ' dependency'
      text = ('|  %s '):format(label)
      highlight = 'PyprojectInfoSpecial'
    elseif dependency.conditional then
      text = '|  conditional '
      highlight = 'PyprojectInfoSpecial'
    elseif update then
      text = ('|  %s '):format(update.latest_version)
      highlight = 'PyprojectInfoOutdated'
    elseif current then
      text = ('|  %s '):format(dependency.declared ~= '' and dependency.declared or current.version)
      highlight = 'PyprojectInfoUpToDate'
    else
      text = '|  not installed '
      highlight = 'PyprojectInfoMissing'
    end

    by_line[dependency.lnum] = by_line[dependency.lnum] or {}
    table.insert(by_line[dependency.lnum], { text, highlight })
  end

  vim.api.nvim_buf_clear_namespace(bufnr, namespace, 0, -1)
  for lnum, chunks in pairs(by_line) do
    vim.api.nvim_buf_set_extmark(bufnr, namespace, lnum - 1, 0, {
      virt_text = chunks,
      virt_text_pos = 'eol',
    })
  end
end

function M.refresh(bufnr)
  bufnr = bufnr or 0
  if vim.fn.fnamemodify(vim.api.nvim_buf_get_name(bufnr), ':t') ~= 'pyproject.toml' then
    return
  end

  if vim.fn.executable 'uv' ~= 1 then
    vim.notify('uv is required for pyproject package information', vim.log.levels.ERROR)
    return
  end

  local dependencies = parse_dependencies(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false))
  if #dependencies == 0 then
    vim.api.nvim_buf_clear_namespace(bufnr, namespace, 0, -1)
    return
  end

  local cwd = vim.fs.dirname(vim.api.nvim_buf_get_name(bufnr))
  local revision = (revisions[bufnr] or 0) + 1
  local results = {}
  local completed = 0
  revisions[bufnr] = revision
  vim.api.nvim_buf_clear_namespace(bufnr, namespace, 0, -1)

  local function complete(kind, result)
    results[kind] = result
    completed = completed + 1
    if completed < 2 then
      return
    end

    vim.schedule(function()
      if revisions[bufnr] ~= revision or not vim.api.nvim_buf_is_valid(bufnr) then
        return
      end

      local installed, installed_error = decode_packages(results.installed)
      local outdated, outdated_error = decode_packages(results.outdated)
      if not installed or not outdated then
        vim.notify('Pyproject package check failed: ' .. (installed_error or outdated_error), vim.log.levels.WARN)
        return
      end

      render(bufnr, dependencies, installed, outdated)
    end)
  end

  vim.system({ 'uv', 'pip', 'list', '--format', 'json' }, { cwd = cwd, text = true }, function(result)
    complete('installed', result)
  end)
  vim.system({ 'uv', 'pip', 'list', '--outdated', '--format', 'json' }, { cwd = cwd, text = true }, function(result)
    complete('outdated', result)
  end)
end

function M.setup()
  vim.api.nvim_set_hl(0, 'PyprojectInfoUpToDate', { default = true, link = 'DiagnosticOk' })
  vim.api.nvim_set_hl(0, 'PyprojectInfoOutdated', { default = true, link = 'DiagnosticWarn' })
  vim.api.nvim_set_hl(0, 'PyprojectInfoMissing', { default = true, link = 'DiagnosticError' })
  vim.api.nvim_set_hl(0, 'PyprojectInfoSpecial', { default = true, link = 'DiagnosticInfo' })

  local group = vim.api.nvim_create_augroup('pyproject-package-info', { clear = true })
  vim.api.nvim_create_autocmd({ 'BufReadPost', 'BufWritePost' }, {
    group = group,
    pattern = 'pyproject.toml',
    callback = function(args)
      M.refresh(args.buf)
    end,
  })
  vim.api.nvim_create_user_command('PyprojectInfoRefresh', function()
    M.refresh(0)
  end, { force = true })
end

M._parse_dependencies = parse_dependencies

return M
