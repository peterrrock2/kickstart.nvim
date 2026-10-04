local M = {}

local function register_environment(directory, environment)
  if not environment or environment == '' then
    return
  end

  environment = vim.fs.normalize(environment)
  local python = environment .. (vim.fn.has 'win32' == 1 and '/Scripts/python.exe' or '/bin/python')
  local source = environment .. '/share/jupyter/kernels/python3/kernel.json'
  if vim.fn.executable(python) ~= 1 or vim.fn.filereadable(source) ~= 1 then
    return
  end

  local ok, spec = pcall(function()
    return vim.json.decode(table.concat(vim.fn.readfile(source), '\n'))
  end)
  if not ok or type(spec) ~= 'table' or spec.language ~= 'python' or type(spec.argv) ~= 'table' then
    return
  end

  local label = vim.fs.basename(environment)
  if label == '.venv' or label == 'venv' then
    label = vim.fs.basename(vim.fs.dirname(environment))
  end
  local name = 'venv-' .. label:lower():gsub('[^%w_-]', '-') .. '-' .. vim.fn.sha256(environment):sub(1, 12)
  local destination = directory .. '/kernels/' .. name
  spec.argv[1] = python
  spec.display_name = 'Python (' .. label .. ': ' .. environment .. ')'

  local encoded = vim.json.encode(spec)
  local path = destination .. '/kernel.json'
  if vim.fn.filereadable(path) == 1 and table.concat(vim.fn.readfile(path), '\n') == encoded then
    return
  end

  vim.fn.mkdir(destination, 'p')
  vim.fn.writefile({ encoded }, path)
end

local function discover_environments(directory)
  local buffer_path = vim.api.nvim_buf_get_name(0)
  local start = buffer_path ~= '' and vim.fs.dirname(buffer_path) or vim.fn.getcwd()
  local environment = vim.fs.find({ '.venv', 'venv' }, { path = start, upward = true, type = 'directory' })[1]
  register_environment(directory, environment)
  register_environment(directory, vim.env.VIRTUAL_ENV)
  register_environment(directory, vim.env.CONDA_PREFIX)
end

function M.setup()
  local directory = vim.fn.tempname() .. '-molten'
  local existing = vim.env.JUPYTER_PATH
  local separator = vim.fn.has 'win32' == 1 and ';' or ':'
  -- Set this before the remote Python host starts; Jupyter reads it on each lookup.
  vim.env.JUPYTER_PATH = directory .. (existing and existing ~= '' and separator .. existing or '')

  discover_environments(directory)
  vim.api.nvim_create_autocmd({ 'BufEnter', 'DirChanged' }, {
    group = vim.api.nvim_create_augroup('molten-local-kernels', { clear = true }),
    callback = function()
      discover_environments(directory)
    end,
  })
end

return M
