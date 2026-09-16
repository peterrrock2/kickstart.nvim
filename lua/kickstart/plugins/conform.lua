local function pyproject_root(dirname, tool)
  return vim.fs.root(dirname, function(name, path)
    if name ~= 'pyproject.toml' then
      return false
    end
    for _, line in ipairs(vim.fn.readfile(vim.fs.joinpath(path, name))) do
      if line:match('^%s*%[tool%.' .. tool .. '[%.%]]') then
        return true
      end
    end
    return false
  end)
end

local function python_formatters(bufnr)
  local dirname = vim.fs.dirname(vim.api.nvim_buf_get_name(bufnr))
  local formatters = {}
  if pyproject_root(dirname, 'isort') then
    table.insert(formatters, 'isort')
  end
  if pyproject_root(dirname, 'black') then
    table.insert(formatters, 'black')
  end
  return #formatters > 0 and formatters or { 'ruff', 'ruff_format' }
end

local function from_venv(command)
  return function(self, ctx)
    local find = require('conform.util').find_executable
    return find({ '.venv/bin/' .. command, '.venv/Scripts/' .. command .. '.exe' }, command)(self, ctx)
  end
end

local function prettier_override(bufnr)
  local dirname = vim.fs.dirname(vim.api.nvim_buf_get_name(bufnr))
  if vim.fn.executable 'bun' ~= 1 or not vim.fs.root(dirname, { 'bun.lock', 'bun.lockb' }) then
    return nil
  end
  local node_modules = vim.fs.find('node_modules', {
    upward = true,
    path = dirname,
    type = 'directory',
    limit = math.huge,
  })
  for _, directory in ipairs(node_modules) do
    local entrypoint = vim.fs.joinpath(directory, 'prettier', 'bin', 'prettier.cjs')
    if vim.fn.filereadable(entrypoint) == 1 then
      return { command = 'bun', prepend_args = { entrypoint } }
    end
  end
end

local prettier_formatters = { 'prettier', 'prettierd', stop_after_first = true }

return { -- Autoformat
  'stevearc/conform.nvim',
  event = { 'BufWritePre' },
  cmd = { 'ConformInfo' },
  keys = {
    {
      '<leader>f',
      function()
        require('conform').format { async = true, lsp_format = 'never' }
      end,
      mode = '',
      desc = '[F]ormat buffer',
    },
  },
  opts = {
    notify_on_error = false,
    format_on_save = function(bufnr)
      -- Disable "format_on_save lsp_fallback" for languages that don't
      -- have a well standardized coding style. You can add additional
      -- languages here or re-enable it for the disabled ones.
      local disable_filetypes = { c = true, cpp = true }
      if disable_filetypes[vim.bo[bufnr].filetype] then
        return nil
      else
        return {
          timeout_ms = 5000,
          lsp_format = 'never',
        }
      end
    end,
    formatters_by_ft = {
      lua = { 'stylua' },
      python = python_formatters,
      rust = { 'rustfmt' },
      sh = { 'shfmt' },
      bash = { 'shfmt' },
      go = { 'goimports' },
      markdown = prettier_formatters,
      javascript = prettier_formatters,
      javascriptreact = prettier_formatters, -- JSX
      typescript = prettier_formatters,
      typescriptreact = prettier_formatters, -- TSX
      json = prettier_formatters,
      css = prettier_formatters,
      yaml = prettier_formatters,
    },
    formatters = {
      prettier = prettier_override,
      black = {
        command = from_venv 'black',
        cwd = function(_, ctx)
          return pyproject_root(ctx.dirname, 'black')
        end,
      },
      isort = {
        command = from_venv 'isort',
        args = { '--stdout', '--filename', '$FILENAME', '-' },
        cwd = function(_, ctx)
          return pyproject_root(ctx.dirname, 'isort')
        end,
      },
      shfmt = {
        -- indent 4, indent case/esac, simplify, indent binops, keep columns
        prepend_args = { '-i', '4', '-ci', '-sr', '-bn', '-kp' },
      },
      mdformat = { prepend_args = { '--wrap', '100' } },
      ruff_format = {
        args = function(self, ctx)
          local has_config = vim.fs.root(ctx.dirname, { 'ruff.toml', '.ruff.toml' }) or pyproject_root(ctx.dirname, 'ruff')
          local args = { 'format' }
          if not has_config then
            vim.list_extend(args, { '--line-length', '100' })
          end
          vim.list_extend(args, { '--force-exclude', '--stdin-filename', '$FILENAME', '-' })
          return args
        end,
      },
      ruff = {
        args = function(self, ctx)
          local has_config = vim.fs.root(ctx.dirname, { 'ruff.toml', '.ruff.toml' }) or pyproject_root(ctx.dirname, 'ruff')
          local args = { 'check' }
          if not has_config then
            vim.list_extend(args, {
              '--select',
              'E,W,F,I',
              '--line-length',
              '100',
              '--task-tags',
              'TODO,FIXME,XXX,HACK,NOTE,FIX,BUG',
            })
          end
          vim.list_extend(args, { '--fix', '--force-exclude', '--stdin-filename', '$FILENAME', '-' })
          return args
        end,
      },
    },
  },
}
