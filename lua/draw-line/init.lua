local M = {}
local bit = require("bit")
local bor, band = bit.bor, bit.band
local api, fn = vim.api, vim.fn
local standard = require("draw-line.glyphs")
local arrows = { [1] = "▼", [2] = "◀", [4] = "▲", [8] = "▶" }
local arrow_entries = {}
for mask, glyph in pairs(arrows) do
  arrow_entries[glyph] = { mask = mask, edges = { [mask] = false } }
end

local function glyph_entry(glyph)
  return standard.by_glyph[glyph] or arrow_entries[glyph]
end

-- Glyph overrides use N=1, E=2, S=4, W=8 connectivity masks.
local styles = {
  single = { weight = 1 },
  heavy = { weight = 2 },
  -- Unicode has no double half-strokes; use light endpoint glyphs.
  double = { weight = 3, glyphs = { [1] = "╵", [2] = "╶", [4] = "╷", [8] = "╴" } },
  rounded = { weight = 1, glyphs = { [3] = "╰", [6] = "╭", [9] = "╯", [12] = "╮" } },
  dashed2 = { weight = 1, glyphs = { [5] = "╎", [10] = "╌" } },
  dashed3 = { weight = 1, glyphs = { [5] = "┆", [10] = "┄" } },
  dashed4 = { weight = 1, glyphs = { [5] = "┊", [10] = "┈" } },
  heavy_dashed2 = { weight = 2, glyphs = { [5] = "╏", [10] = "╍" } },
  heavy_dashed3 = { weight = 2, glyphs = { [5] = "┇", [10] = "┅" } },
  heavy_dashed4 = { weight = 2, glyphs = { [5] = "┋", [10] = "┉" } },
}
for _, style in pairs(styles) do
  style.glyphs, style.keys = style.glyphs or {}, {}
  for mask = 1, 15 do
    local edges = {}
    for _, direction in ipairs(standard.directions) do
      if band(mask, direction) ~= 0 then
        edges[direction] = style.weight
      end
    end
    local key = assert(standard.key(edges), "invalid built-in edge weights")
    style.keys[mask] = key
    style.glyphs[mask] = assert(style.glyphs[mask] or standard.by_edges[key], "missing built-in glyph")
  end
end
local MAX_CELLS, MAX_ROWS, MAX_COLUMN, MAX_PADDING = 10000, 10000, 1000000, 1000000

local function argument(condition, message)
  if not condition then
    error("draw-line: " .. message, 3)
  end
end

local function integer(value, minimum, maximum)
  return type(value) == "number" and value >= minimum and value <= maximum and value % 1 == 0
end

local function valid_glyph(glyph)
  return fn.strdisplaywidth(glyph) == 1
end

local function valid_style(style)
  for _, glyph in pairs(style.glyphs) do
    if not valid_glyph(glyph) then
      return false
    end
  end
  return true
end

local function get_style(name)
  name = name == nil and "single" or name
  argument(type(name) == "string", "style must be a built-in name")
  argument(styles[name] ~= nil, "unknown style '" .. name .. "'")
  return styles[name]
end

local function copy_edges(edges)
  return { [1] = edges[1], [2] = edges[2], [4] = edges[4], [8] = edges[8] }
end

local function coordinate(point)
  argument(type(point) == "table", "coordinates must be {row, col}")
  for key in pairs(point) do
    argument(key == 1 or key == 2, "coordinates must contain only row and col")
  end
  argument(integer(point[1], 1, 1000000000), "row must be a positive integer no greater than 1000000000")
  argument(integer(point[2], 1, MAX_COLUMN), "display column must be an integer from 1 to " .. MAX_COLUMN)
  return point[1], point[2]
end

local function add(cells, row, col, mask)
  cells[row] = cells[row] or {}
  cells[row][col] = bor(cells[row][col] or 0, mask)
end

local function segment(cells, row, col, dr, dc, steps, outward, inward)
  for step = 0, steps - 1 do
    add(cells, row + dr * step, col + dc * step, outward)
    add(cells, row + dr * (step + 1), col + dc * (step + 1), inward)
  end
end

-- Neovim's character splitting keeps composing sequences with their base.
local function clusters(line)
  return fn.split(line, "\\zs")
end

local neighbors = {
  [1] = { -1, 0, 4 },
  [2] = { 0, 1, 8 },
  [4] = { 1, 0, 1 },
  [8] = { 0, -1, 2 },
}

local function existing_edges(glyph, style, row, col, lookup)
  local entry = glyph_entry(glyph)
  local edges = entry and copy_edges(entry.edges) or {}
  -- Arrows and light double endpoints recover their weight from visible neighbors.
  if entry and neighbors[entry.mask] and edges[entry.mask] ~= 2 then
    local offset = neighbors[entry.mask]
    local adjacent = glyph_entry(lookup(row + offset[1], col + offset[2]))
    local opposite = offset[3]
    local weight = adjacent and adjacent.edges[opposite]
    if edges[entry.mask] == false then
      if not adjacent or weight == nil then
        return nil, nil, "arrow has no connected line"
      end
      if weight == false then
        weight = style.weight
      elseif weight == 1 and adjacent.mask == opposite and style.weight == 3 then
        weight = 3
      end
      edges[entry.mask] = weight
    elseif
      weight == 3
      or (adjacent and adjacent.mask == opposite and (weight == 1 or weight == false) and style.weight == 3)
    then
      edges[entry.mask] = 3
    end
  end
  return edges, entry and entry.mask or 0
end

-- tip is true at draw's destination, false at its source, and nil for boxes.
local function resolve(glyph, mask, style, row, col, lookup, tip)
  local edges, old_mask, message = existing_edges(glyph, style, row, col, lookup)
  if not edges then
    return nil, message
  end
  local full_start = (old_mask == 5 and edges[1] == edges[4]) or (old_mask == 10 and edges[2] == edges[8])
  -- A full straight can be an open start; retain only its reciprocal edge.
  if full_start then
    local connected = 0
    for direction, offset in pairs(neighbors) do
      if edges[direction] then
        local adjacent = glyph_entry(lookup(row + offset[1], col + offset[2]))
        if adjacent and adjacent.edges[offset[3]] ~= nil then
          connected = bor(connected, direction)
        end
      end
    end
    if neighbors[connected] then
      edges, old_mask = { [connected] = edges[connected] }, connected
    end
  end
  local merged = bor(old_mask, mask)
  for _, direction in ipairs(standard.directions) do
    if band(mask, direction) ~= 0 then
      edges[direction] = style.weight
    end
  end
  local key = standard.key(edges)
  if key == nil then
    return nil, "invalid edge weights"
  end
  local resolved = key == style.keys[merged] and style.glyphs[merged] or standard.by_edges[key]
  if not resolved then
    return nil, "no Unicode glyph represents these edge weights (heavy/double or single/double transition)"
  end
  -- Only a destination with one connected edge is a free tip.
  if tip and arrows[merged] then
    resolved = arrows[merged]
  elseif tip == false and arrows[merged] and (old_mask == 0 or full_start) then
    resolved = style.glyphs[bor(merged, neighbors[merged][3])]
  end
  if not valid_glyph(resolved) then
    return nil, "resolved glyph is not width 1 with the current display settings"
  end
  return resolved
end

local function replace(line, targets, style, row, lookup, destination)
  local result, col, last, padding = {}, 1, 0, 0
  local tip_row = destination and row == destination[1]
  for target in pairs(targets) do
    last = math.max(last, target)
  end
  for _, glyph in ipairs(clusters(line)) do
    local width = fn.strdisplaywidth(glyph, col - 1)
    local mask = targets[col]
    for cell = col, col + width - 1 do
      if targets[cell] and (width ~= 1 or (glyph ~= " " and not glyph_entry(glyph))) then
        return nil, "collision at row " .. row .. ", display column " .. cell
      end
    end
    if width == 0 and (targets[col] or targets[col - 1]) then
      return nil, "zero-width text beside drawing at row " .. row
    end
    if mask then
      local message
      glyph, message = resolve(glyph, mask, style, row, col, lookup, tip_row and col == destination[2])
      if not glyph then
        return nil, message .. " at row " .. row .. ", display column " .. col
      end
    end
    result[#result + 1] = glyph
    col = col + width
  end
  for cell = col, last do
    local glyph, message = " "
    if targets[cell] then
      glyph, message = resolve(glyph, targets[cell], style, row, cell, lookup, tip_row and cell == destination[2])
      if not glyph then
        return nil, message .. " at row " .. row .. ", display column " .. cell
      end
    end
    result[#result + 1] = glyph
    padding = padding + 1
  end
  return table.concat(result), nil, padding
end

local function cursor_at(row, col, want)
  local line = api.nvim_buf_get_lines(0, row - 1, row, false)[1]
  local byte, display = 1, 1
  for _, glyph in ipairs(clusters(line)) do
    local width = fn.strdisplaywidth(glyph, display - 1)
    if display + width > col then
      fn.setpos(".", { 0, row, byte, col - display, want or col })
      return
    end
    byte, display = byte + #glyph, display + width
  end
  fn.setpos(".", { 0, row, byte, col - display, want or col })
end

local function apply(cells, style, destination)
  if not vim.bo.modifiable then
    return nil, "draw-line: buffer is not modifiable"
  end
  if vim.bo.readonly then
    return nil, "draw-line: buffer is readonly"
  end
  if not valid_style(style) then
    return nil, "draw-line: selected style is not width 1 with the current display settings"
  end
  local first, last = math.huge, 0
  for row in pairs(cells) do
    first, last = math.min(first, row), math.max(last, row)
  end
  if last == 0 then
    return true
  end
  local line_count = api.nvim_buf_line_count(0)
  local rows = {}
  local function lookup(row, col)
    if row < 1 or row > line_count or col < 1 then
      return " "
    end
    if not rows[row] then
      local display_cells, display = {}, 1
      local line = api.nvim_buf_get_lines(0, row - 1, row, false)[1]
      for _, glyph in ipairs(clusters(line)) do
        local width = fn.strdisplaywidth(glyph, display - 1)
        if width == 1 then
          display_cells[display] = glyph
        end
        display = display + width
      end
      rows[row] = display_cells
    end
    return rows[row][col] or " "
  end
  if last - math.min(first, line_count + 1) + 1 > MAX_ROWS then
    return nil, "draw-line: operation spans or appends more than " .. MAX_ROWS .. " rows"
  end
  first = math.min(first, line_count + 1)
  local original = api.nvim_buf_get_lines(0, first - 1, math.min(last, line_count), false)
  local replacement, padding, changed = {}, 0, last > line_count
  for row = first, last do
    local line = original[row - first + 1] or ""
    if cells[row] then
      local message, extra
      line, message, extra = replace(line, cells[row], style, row, lookup, destination)
      if not line then
        return nil, "draw-line: " .. message
      end
      padding = padding + extra
      if padding > MAX_PADDING then
        return nil, "draw-line: operation needs more than " .. MAX_PADDING .. " padding cells"
      end
    end
    replacement[#replacement + 1] = line
    changed = changed or line ~= original[row - first + 1]
  end
  local saved = fn.getcurpos()
  local cursor_col = fn.virtcol(".", true)[1]
  if changed then
    -- Closing the undo block does not change the global or local option value.
    vim.go.undolevels = vim.go.undolevels
    local ok, message = pcall(api.nvim_buf_set_lines, 0, first - 1, math.min(last, line_count), false, replacement)
    if not ok then
      return nil, "draw-line: " .. message
    end
  end
  if destination then
    cursor_at(destination[1], destination[2])
  else
    cursor_at(saved[2], cursor_col, saved[5])
  end
  return true
end

local directions = {
  h = { 0, -1, 8, 2 },
  j = { 1, 0, 4, 1 },
  k = { -1, 0, 1, 4 },
  l = { 0, 1, 2, 8 },
}

--- Draw one edge, put an arrow on its free tip, and move to the destination.
function M.draw(direction, name, ...)
  argument(type(direction) == "string" and directions[direction] ~= nil, "direction must be h, j, k or l")
  argument(select("#", ...) == 0, "draw expects only direction and optional style")
  local style = get_style(name)
  local row, col = fn.line("."), fn.virtcol(".", true)[1]
  local move = directions[direction]
  local finish = { row + move[1], col + move[2] }
  if finish[1] < 1 or finish[2] < 1 or finish[2] > MAX_COLUMN then
    return nil, "draw-line: drawing would cross a buffer boundary or column limit"
  end
  local cells = {}
  segment(cells, row, col, move[1], move[2], 1, move[3], move[4])
  return apply(cells, style, finish)
end

--- Draw an inclusive perimeter, preserving the cursor's display position.
function M.box(start, finish, name, ...)
  argument(select("#", ...) == 0, "box expects two coordinates and optional style")
  local row1, col1 = coordinate(start)
  local row2, col2 = coordinate(finish)
  local style = get_style(name)
  row1, row2 = math.min(row1, row2), math.max(row1, row2)
  col1, col2 = math.min(col1, col2), math.max(col1, col2)
  local height, width = row2 - row1 + 1, col2 - col1 + 1
  local size = height == 1 and width or width == 1 and height or 2 * (height + width) - 4
  argument(size <= MAX_CELLS, "box perimeter exceeds " .. MAX_CELLS .. " cells")
  local cells = {}
  if width == 1 and height == 1 then
    add(cells, row1, col1, 15)
  elseif height == 1 then
    segment(cells, row1, col1, 0, 1, width - 1, 2, 8)
  elseif width == 1 then
    segment(cells, row1, col1, 1, 0, height - 1, 4, 1)
  else
    segment(cells, row1, col1, 0, 1, width - 1, 2, 8)
    segment(cells, row2, col1, 0, 1, width - 1, 2, 8)
    segment(cells, row1, col1, 1, 0, height - 1, 4, 1)
    segment(cells, row1, col2, 1, 0, height - 1, 4, 1)
  end
  return apply(cells, style)
end

--- Use the live Visual Block endpoints; successful calls leave Normal mode at the top left.
function M.box_visual(name, ...)
  argument(select("#", ...) == 0, "box_visual expects only an optional style")
  get_style(name)
  if fn.mode() ~= "\22" then
    return nil, "draw-line: box_visual requires an active Visual Block selection"
  end
  if vim.o.selection ~= "inclusive" then
    return nil, "draw-line: box_visual requires selection=inclusive"
  end
  if fn.getcurpos()[5] == vim.v.maxcol then
    return nil, "draw-line: block selections ending with $ are unsupported; select a fixed column"
  end
  local start = { fn.line("v"), fn.virtcol("v", true)[1] }
  local finish = { fn.line("."), fn.virtcol(".", true)[1] }
  local ok, message = M.box(start, finish, name)
  if ok then
    vim.cmd("normal! \27")
    cursor_at(math.min(start[1], finish[1]), math.min(start[2], finish[2]))
  end
  return ok, message
end

return M
