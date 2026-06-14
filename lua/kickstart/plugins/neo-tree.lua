-- Neo-tree is a Neovim plugin to browse the file system
-- https://github.com/nvim-neo-tree/neo-tree.nvim

-- Snapshot of the window layout taken right before Neo-tree opens, so we can
-- restore the same horizontal ratios afterwards instead of letting Vim's
-- `equalalways` collapse everything toward equal widths.
local saved_layout = nil

-- Build a frozen copy of `winlayout()` that records each leaf's current width.
local function snapshot(node)
  if node[1] == 'leaf' then
    return { type = 'leaf', win = node[2], width = vim.api.nvim_win_get_width(node[2]) }
  end
  local children = {}
  for _, child in ipairs(node[2]) do
    children[#children + 1] = snapshot(child)
  end
  return { type = node[1], children = children }
end

-- Width a snapshot node occupied at capture time (separators included for rows).
local function node_width(node)
  if node.type == 'leaf' then
    return node.width
  elseif node.type == 'row' then
    local w = #node.children - 1 -- column separators between siblings
    for _, child in ipairs(node.children) do
      w = w + node_width(child)
    end
    return w
  else -- 'col': stacked windows all share the same width
    return node_width(node.children[1])
  end
end

-- Resize a snapshot subtree to fit `target` columns, preserving each row's
-- internal proportions.
local function resize_node(node, target)
  target = math.max(target, 1)
  if node.type == 'leaf' then
    if vim.api.nvim_win_is_valid(node.win) then
      vim.api.nvim_win_set_width(node.win, target)
    end
  elseif node.type == 'row' then
    local seps = #node.children - 1
    local content_target = target - seps
    local content_current = node_width(node) - seps
    local allocated = 0
    for i, child in ipairs(node.children) do
      local nw
      if i == #node.children then
        nw = content_target - allocated -- give the remainder to the last child
      else
        nw = math.floor(node_width(child) / content_current * content_target)
        allocated = allocated + nw
      end
      resize_node(child, nw)
    end
  else -- 'col': every child spans the full target width
    for _, child in ipairs(node.children) do
      resize_node(child, target)
    end
  end
end

return {
  'nvim-neo-tree/neo-tree.nvim',
  version = '*',
  dependencies = {
    'nvim-lua/plenary.nvim',
    'nvim-tree/nvim-web-devicons', -- not strictly required, but recommended
    'MunifTanjim/nui.nvim',
  },
  lazy = false,
  keys = {
    { '\\', ':Neotree reveal<CR>', desc = 'NeoTree reveal', silent = true },
  },
  opts = {
    -- By default neo-tree refuses to open files into a terminal window and
    -- falls back to vsplit. Remove "terminal" from the list so it will open
    -- normally into whatever window was last focused (even if it was a terminal).
    open_files_do_not_replace_types = { 'trouble', 'qf' },
    default_component_configs = {
      name = { use_git_status_colors = true },
      git_status = {
        symbols = {
          added = 'A',
          modified = 'M',
          deleted = 'D',
          renamed = 'R',
          untracked = '',
          ignored = 'I',
          unstaged = 'U',
          staged = 'S',
          conflict = 'X',
        },
        -- align = "right", -- uncomment to show badges on the right
      },
      modified = { symbol = '●', highlight = 'NeoTreeModified' },
    },

    filesystem = {
      window = {
        mappings = {
          ['\\'] = 'close_window',
        },
        position = 'right',
      },
    },

    event_handlers = {
      -- Capture the current layout just before the tree window appears.
      {
        event = 'neo_tree_window_before_open',
        handler = function()
          local layout = vim.fn.winlayout()
          -- Only worth preserving when more than one window is visible.
          if layout[1] == 'leaf' then
            saved_layout = nil
          else
            saved_layout = snapshot(layout)
          end
        end,
      },
      -- Re-apply the captured proportions to the width left over after the
      -- tree window has claimed its column.
      {
        event = 'neo_tree_window_after_open',
        handler = function(args)
          if not saved_layout then
            return
          end
          local layout = saved_layout
          saved_layout = nil
          vim.schedule(function()
            if not (args and args.winid and vim.api.nvim_win_is_valid(args.winid)) then
              return
            end
            local tree_width = vim.api.nvim_win_get_width(args.winid)
            local available = vim.o.columns - tree_width - 1 -- separator
            resize_node(layout, available)
          end)
        end,
      },
    },
  },
}
