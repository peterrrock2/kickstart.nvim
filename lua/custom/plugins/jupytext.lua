return {
  'goerz/jupytext.nvim',
  version = '0.2.0',
  lazy = false,
  init = function()
    -- The upstream health check invokes jupytext by name rather than using opts.jupytext.
    vim.env.PATH = vim.env.PATH .. ':' .. vim.fn.stdpath 'data' .. '/python/bin'
  end,
  opts = {
    jupytext = vim.fn.stdpath 'data' .. '/python/bin/jupytext',
    format = 'md:markdown',
    -- Finish notebook conversion before Molten exports outputs into the same file.
    async_write = false,
  },
}
