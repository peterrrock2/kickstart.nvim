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
          timeout_ms = 500,
          lsp_format = 'never',
        }
      end
    end,
    formatters_by_ft = {
      lua = { 'stylua' },
      python = { 'ruff', 'ruff_format' },
      rust = { 'rustfmt' },
      sh = { 'shfmt' },
      bash = { 'shfmt' },
      markdown = { 'mdformat' },
      javascript = { 'prettierd', 'prettier', stop_after_first = true },
      javascriptreact = { 'prettierd', 'prettier', stop_after_first = true }, -- JSX
      typescript = { 'prettierd', 'prettier', stop_after_first = true },
      typescriptreact = { 'prettierd', 'prettier', stop_after_first = true }, -- TSX
      json = { 'prettierd', 'prettier' },
      css = { 'prettierd', 'prettier' },
      yaml = { 'prettierd', 'prettier' },
      -- Conform can also run multiple formatters sequentially
      -- python = { "isort", "black" },
      --
      -- You can use 'stop_after_first' to run the first available formatter from the list
      -- javascript = { "prettierd", "prettier", stop_after_first = true },
    },
    formatters = {
      shfmt = {
        -- indent 4, indent case/esac, simplify, indent binops, keep columns
        prepend_args = { '-i', '4', '-ci', '-sr', '-bn', '-kp' },
      },
      mdformat = { prepend_args = { '--wrap', '100' } },
      ruff_format = {
        prepend_args = { '--line-length', '100' },
      },
      ruff = {
        args = function(self, ctx)
          local has_config = #vim.fs.find(
            { 'ruff.toml', '.ruff.toml' },
            { upward = true, path = ctx.dirname }
          ) > 0
          if not has_config then
            local pyproject = vim.fs.find('pyproject.toml', { upward = true, path = ctx.dirname })[1]
            if pyproject then
              local content = vim.fn.readfile(pyproject)
              has_config = vim.iter(content):any(function(line)
                return line:match '%[tool%.ruff'
              end)
            end
          end
          local args = { 'check' }
          if not has_config then
            vim.list_extend(args, {
              '--select', 'E,W,F,I',
              '--line-length', '100',
              '--task-tags', 'TODO,FIXME,XXX,HACK,NOTE,FIX,BUG',
            })
          end
          vim.list_extend(args, { '--fix', '--force-exclude', '--stdin-filename', '$FILENAME', '-' })
          return args
        end,
      },
    },
  },
}
