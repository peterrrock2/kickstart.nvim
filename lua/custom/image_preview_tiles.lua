local M = {}
local editor_tty

local function graphics()
  return require('image/backends/kitty/helpers')
end

function M.release(tile, tty)
  if tile.image_id then
    graphics().write_graphics({
      action = 'd',
      display_delete = 'I',
      image_id = tile.image_id,
      quiet = 2,
      tty = tty,
    })
    tile.image_id = nil
  end
end

local function erase_placements(placements, tty)
  for _, placement in ipairs(placements or {}) do
    graphics().write_graphics({
      action = 'd',
      display_delete = 'i',
      image_id = placement.image_id,
      placement_id = placement.placement_id,
      quiet = 2,
      tty = tty,
    })
  end
end

local function get_clear_tty()
  local tty
  if editor_tty then
    local tmux = require('image/utils').tmux
    tty = tmux.is_tmux and tmux.get_pane_tty() or nil
    if tty == editor_tty then
      tty = nil
    end
  end
  return tty
end

function M.release_image(image)
  editor_tty = editor_tty or require('image/utils').term.get_tty()
  M.release({ image_id = image.internal_id }, get_clear_tty())
end

function M.hide(view)
  local tty = get_clear_tty()
  erase_placements(view.placements, tty)
  view.placements = nil
  if view.cache then
    for _, tile in pairs(view.cache.tiles) do
      M.release(tile, tty)
    end
  end
end

local function upload(tile, image)
  if tile.image_id then
    return
  end
  -- Clone the registered preview to allocate an id without probing each tile's metadata.
  local image_id = assert(require('image').from_file(image.original_path)).internal_id
  editor_tty = editor_tty or require('image/utils').term.get_tty()
  local remote = vim.env.SSH_CLIENT ~= nil or vim.env.SSH_TTY ~= nil
  graphics().write_graphics({
    action = 't',
    image_id = image_id,
    transmit_format = 100,
    transmit_medium = remote and 'd' or 'f',
    tty = remote and editor_tty or nil,
    display_cursor_policy = 1,
    quiet = 2,
  }, tile.path)
  tile.image_id = image_id
end

local function build_placement(tile, plan, image, x, y, term, generation)
  local left = math.max(tile.x, plan.x, plan.x + (image.bounds.left - x) * term.cell_width)
  local top = math.max(tile.y, plan.y, plan.y + (image.bounds.top - y) * term.cell_height)
  local right = math.min(
    tile.x + tile.width,
    plan.x + plan.width,
    plan.x + (image.bounds.right - x) * term.cell_width
  )
  local bottom = math.min(
    tile.y + tile.height,
    plan.y + plan.height,
    plan.y + (image.bounds.bottom - y + 1) * term.cell_height
  )
  if right <= left or bottom <= top then
    return
  end

  local screen_x, screen_y = left - plan.x, top - plan.y
  return {
    action = 'p',
    image_id = tile.image_id,
    placement_id = generation,
    display_x = left - tile.x,
    display_y = top - tile.y,
    display_width = right - left,
    display_height = bottom - top,
    display_x_offset = screen_x % term.cell_width,
    display_y_offset = screen_y % term.cell_height,
    -- New placements sit above the preceding view until all of them are ready.
    display_zindex = math.min(-1, -1000000000 + generation),
    display_cursor_policy = 1,
    quiet = 2,
  },
    x + math.floor(screen_x / term.cell_width) + 1,
    y + math.floor(screen_y / term.cell_height) + 1
end

function M.draw(image, view, plan, x, y)
  local term = assert(require('image/utils').term.get_size())
  view.generation = (view.generation or 0) + 1
  local placements = {}
  local ok, err = pcall(function()
    for _, tile in ipairs(plan.tiles) do
      upload(tile, image)
    end
    for _, tile in ipairs(plan.tiles) do
      local placement, column, row = build_placement(tile, plan, image, x, y, term, view.generation)
      if placement then
        placements[#placements + 1] = placement
        graphics().write_graphics_at(placement, column, row)
      end
    end
  end)
  if not ok then
    erase_placements(placements)
    error(err, 0)
  end

  erase_placements(view.placements)
  view.placements = placements
end

return M
