-- Run: nvim -n --clean --headless -i NONE -l tests/python_folding.lua
vim.opt.runtimepath:prepend(vim.fn.stdpath('config'))
vim.opt.runtimepath:append(vim.fn.stdpath('config') .. '/after')
vim.cmd('filetype plugin on')
local source = vim.fn.tempname() .. '.py'
local session = vim.fn.tempname() .. '.vim'
vim.fn.writefile({
  'def plot():',
  '    if level_rows:',
  '        for ax, key in zip(axes, metric_keys):',
  '            vals = [r[key] for r in level_rows if not np.isnan(r[key])]',
  '            mu = means[key]',
  '',
  '            # Keep the histogram settings together.',
  '            # Comments and blank lines remain inside the loop.',
  '            ax.hist(vals, bins=20,',
  '                    alpha=0.65,',
  '                    color=METRIC_COLORS[key], edgecolor="none")',
  '        after_loop()',
  '    after_if()',
}, source)
vim.cmd.edit(source)
vim.bo.shiftwidth = 4
assert(vim.wo.foldmethod == 'indent', 'Python ftplugin did not enable indentation folds')

-- A saved session overrides the ftplugin and can restore a partial manual fold.
vim.wo.foldmethod = 'manual'
vim.cmd('4,5fold')
local config = dofile(vim.fn.stdpath('config') .. '/lua/custom/plugins/auto-session.lua')
config.init()
vim.cmd.mksession({ session, bang = true })
vim.cmd.source(session)
assert(vim.wo.foldmethod == 'manual', 'Session did not reproduce the stale fold setting')
assert(vim.fn.foldclosedend(4) == 5, 'Session did not restore the partial fold')

-- Exercise the configured hooks after sourcing the session, as auto-session does.
for _, hook in ipairs(config.opts.post_restore_cmds) do
  hook()
end
assert(vim.wo.foldmethod == 'indent' and vim.wo.foldlevel == 99)
vim.api.nvim_win_set_cursor(0, { 4, 0 })
vim.cmd('normal! za')
assert(
  vim.fn.foldclosed(4) == 4 and vim.fn.foldclosedend(4) == 11,
  'The fold stopped before the next dedent'
)

-- Restoring a session already using indentation preserves its chosen fold level.
vim.wo.foldlevel = 1
for _, hook in ipairs(config.opts.post_restore_cmds) do
  hook()
end
assert(vim.wo.foldlevel == 1)
vim.bo.filetype = 'text'
vim.wo.foldmethod = 'manual'
for _, hook in ipairs(config.opts.post_restore_cmds) do
  hook()
end
assert(vim.wo.foldmethod == 'manual', 'Python session hook changed another filetype')
vim.fn.delete(source)
vim.fn.delete(session)
print('PASS: saved manual folds migrate to complete Python indentation blocks')
