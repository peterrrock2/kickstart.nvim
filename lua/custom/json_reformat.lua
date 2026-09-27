local M = {}

local function next_token(source, position)
  local first = source:find('[^ \t\r\n]', position)
  if not first then
    return nil, #source + 1
  end

  if source:sub(first, first) ~= '"' then
    local token = source:match('^[^ \t\r\n%[%]{},:"]+', first) or source:sub(first, first)
    return token, first + #token
  end

  position = first + 1
  while position <= #source do
    local delimiter = source:find('[\\"]', position)
    if not delimiter then
      break
    end
    if source:sub(delimiter, delimiter) == '"' then
      return source:sub(first, delimiter), delimiter + 1
    end
    position = delimiter + 2
  end
  return source:sub(first), #source + 1
end

local function same_tokens(original, formatted)
  local before, after = 1, 1
  while true do
    local original_token, formatted_token
    original_token, before = next_token(original, before)
    formatted_token, after = next_token(formatted, after)
    if original_token ~= formatted_token then
      return false
    end
    if not original_token then
      return true
    end
  end
end

local function reformat(buffer, opts)
  local bo = vim.bo[buffer]
  if bo.buftype ~= '' or bo.readonly or not bo.modifiable or bo.modified then
    return
  end

  local count = vim.api.nvim_buf_line_count(buffer)
  if vim.api.nvim_buf_get_offset(buffer, count) > opts.max_bytes then
    return 'file exceeds the automatic formatting size limit'
  end

  local long_line = false
  for _, line in ipairs(vim.api.nvim_buf_get_lines(buffer, 0, math.min(count, opts.sample_lines), false)) do
    long_line = long_line or #line >= opts.min_line_length
  end
  if not long_line then
    return
  end

  local version = vim.system({ 'jq', '--version' }, { text = true }):wait(1000)
  local major, minor = (version.stdout or ''):match 'jq%-(%d+)%.(%d+)'
  if version.code ~= 0 or not major or tonumber(major) < 1 or (tonumber(major) == 1 and tonumber(minor) < 7) then
    return 'jq 1.7 or newer is required'
  end

  local source = table.concat(vim.api.nvim_buf_get_lines(buffer, 0, -1, false), '\n')
  local filter = 'if length == 1 then .[0] else error("expected one JSON value") end'
  local result = vim.system({ 'jq', '--monochrome-output', '--indent', '2', '--slurp', filter }, { text = true, stdin = source }):wait(opts.timeout_ms)
  if result.code ~= 0 or not result.stdout or result.stdout == '' then
    return 'jq failed or timed out; the original buffer is unchanged'
  end

  -- Identity filters can still discard duplicate keys or normalize numbers and string escapes.
  if not same_tokens(source, result.stdout) then
    return 'jq would change JSON tokens; the original buffer is unchanged'
  end

  local formatted = result.stdout:gsub('\n$', '')
  if formatted ~= source then
    vim.api.nvim_buf_set_lines(buffer, 0, -1, false, vim.split(formatted, '\n', { plain = true }))
    bo.modified = true
  end
end

function M.setup(opts)
  opts = vim.tbl_extend('force', {
    min_line_length = 2000,
    sample_lines = 20,
    max_bytes = 50 * 1024 * 1024,
    timeout_ms = 3000,
  }, opts or {})

  vim.api.nvim_create_autocmd('BufReadPost', {
    group = vim.api.nvim_create_augroup('json_reformat', { clear = true }),
    pattern = '*.json',
    callback = function(event)
      local ok, reason = pcall(reformat, event.buf, opts)
      if not ok or reason then
        vim.notify('JSON reformat skipped: ' .. tostring(reason), vim.log.levels.WARN)
      end
    end,
  })
end

return M
