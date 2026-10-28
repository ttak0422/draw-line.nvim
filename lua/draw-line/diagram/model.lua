local M = {}
local glyphs = require("draw-line.glyphs")
local bit = require("bit")
local LIMIT = 500

local function point(p)
  return type(p) == "table"
    and type(p[1]) == "number"
    and type(p[2]) == "number"
    and p[1] % 1 == 0
    and p[2] % 1 == 0
    and p[1] >= 1
    and p[2] >= 1
    and p[1] <= LIMIT
    and p[2] <= LIMIT
end

function M.new()
  return { boxes = {}, edges = {}, next_id = 1 }
end

function M.center(box)
  return { math.floor((box.top + box.bottom) / 2), math.floor((box.left + box.right) / 2) }
end

function M.box(graph, a, b)
  if not point(a) or not point(b) then
    return nil, "coordinates must be integer cells from 1 to " .. LIMIT
  end
  local box = {
    id = graph.next_id,
    top = math.min(a[1], b[1]),
    bottom = math.max(a[1], b[1]),
    left = math.min(a[2], b[2]),
    right = math.max(a[2], b[2]),
  }
  if box.bottom - box.top < 2 or box.right - box.left < 2 then
    return nil, "boxes need at least 3 rows and 3 columns"
  end
  graph.boxes[box.id], graph.next_id = box, graph.next_id + 1
  return box.id
end

local function anchor(box, side)
  local p = M.center(box)
  if side == "left" or side == "right" then
    p[2] = box[side]
  else
    p[1] = box[side]
  end
  return p
end

local function simplify(points)
  local result = {}
  for _, p in ipairs(points) do
    local last = result[#result]
    if not last or not vim.deep_equal(last, p) then
      result[#result + 1] = p
    end
    while #result >= 3 do
      local a, b, c = result[#result - 2], result[#result - 1], result[#result]
      -- Only remove a collinear point when it does not reverse direction.
      if
        (a[1] == b[1] and b[1] == c[1] and (b[2] - a[2]) * (c[2] - b[2]) >= 0)
        or (a[2] == b[2] and b[2] == c[2] and (b[1] - a[1]) * (c[1] - b[1]) >= 0)
      then
        table.remove(result, #result - 1)
      else
        break
      end
    end
  end
  return result
end

function M.route(graph, edge)
  -- shortcut: side-center anchors follow terminal stubs; add obstacle routing only when the PoC needs it.
  local a = anchor(graph.boxes[edge.source], edge.source_side)
  local b = anchor(graph.boxes[edge.target], edge.target_side)
  local waypoints = vim.deepcopy(edge.waypoints)
  if edge.source_side == "left" or edge.source_side == "right" then
    waypoints[1][1] = a[1]
  else
    waypoints[1][2] = a[2]
  end
  if edge.target_side == "left" or edge.target_side == "right" then
    waypoints[#waypoints][1] = b[1]
  else
    waypoints[#waypoints][2] = b[2]
  end
  local points = { a }
  vim.list_extend(points, waypoints)
  points[#points + 1] = b
  return simplify(points)
end

function M.connect(graph, source, target)
  local a, b = graph.boxes[source], graph.boxes[target]
  if not a or not b or source == target then
    return nil, "choose two different boxes"
  end
  local from, to, waypoints
  if a.right + 3 < b.left or b.right + 3 < a.left then
    from, to = a.left < b.left and "right" or "left", a.left < b.left and "left" or "right"
    local x = math.floor((a[from] + b[to]) / 2)
    waypoints = { { M.center(a)[1], x }, { M.center(b)[1], x } }
  elseif a.bottom + 3 < b.top or b.bottom + 3 < a.top then
    from, to = a.top < b.top and "bottom" or "top", a.top < b.top and "top" or "bottom"
    local y = math.floor((a[from] + b[to]) / 2)
    waypoints = { { y, M.center(a)[2] }, { y, M.center(b)[2] } }
  else
    return nil, "boxes need a gap of at least 3 cells on one axis"
  end
  local id = graph.next_id
  graph.edges[id] = {
    id = id,
    source = source,
    target = target,
    source_side = from,
    target_side = to,
    waypoints = waypoints,
  }
  graph.next_id = id + 1
  return id
end

function M.move(graph, id, destination)
  local box = graph.boxes[id]
  if not box or not point(destination) then
    return nil, "invalid box or destination"
  end
  local center = M.center(box)
  local dr, dc = destination[1] - center[1], destination[2] - center[2]
  box.top, box.bottom = box.top + dr, box.bottom + dr
  box.left, box.right = box.left + dc, box.right + dc
  return true
end

function M.bend(graph, id, index, destination)
  local edge = graph.edges[id]
  if not edge or not point(destination) then
    return nil, "invalid edge or destination"
  end
  local points = M.route(graph, edge)
  if type(index) ~= "number" or index % 1 ~= 0 or index < 1 then
    return nil, "invalid segment"
  end
  local a, b = points[index], points[index + 1]
  if not a or not b then
    return nil, "invalid segment"
  end
  local horizontal = a[1] == b[1]
  local axis, other = horizontal and 1 or 2, horizontal and 2 or 1
  local result = {}
  for i = 1, index - 1 do
    result[#result + 1] = points[i]
  end
  local first, last = vim.deepcopy(a), vim.deepcopy(b)
  if index == 1 then
    result[#result + 1] = a
    local stub = vim.deepcopy(a)
    stub[other] = stub[other] + (b[other] > a[other] and 1 or -1)
    result[#result + 1] = stub
    first = vim.deepcopy(stub)
  end
  if index == #points - 1 then
    last[other] = last[other] + (a[other] > b[other] and 1 or -1)
  end
  first[axis], last[axis] = destination[axis], destination[axis]
  result[#result + 1], result[#result + 2] = first, last
  if index == #points - 1 then
    local stub = vim.deepcopy(last)
    stub[axis] = b[axis]
    result[#result + 1] = stub
    result[#result + 1] = b
  end
  for i = index + 2, #points do
    result[#result + 1] = points[i]
  end
  -- Retain terminal stubs so moving a box can update its attached segment.
  edge.waypoints = {}
  for i = 2, #result - 1 do
    edge.waypoints[#edge.waypoints + 1] = result[i]
  end
  return true
end

function M.handles(graph)
  local handles = {}
  for _, edge in pairs(graph.edges) do
    local points = M.route(graph, edge)
    for i = 1, #points - 1 do
      local a, b = points[i], points[i + 1]
      if math.abs(a[1] - b[1]) + math.abs(a[2] - b[2]) >= 2 then
        handles[#handles + 1] = {
          edge = edge.id,
          segment = i,
          point = { math.floor((a[1] + b[1]) / 2), math.floor((a[2] + b[2]) / 2) },
        }
      end
    end
  end
  table.sort(handles, function(a, b)
    return a.edge == b.edge and a.segment < b.segment or a.edge < b.edge
  end)
  return handles
end

function M.render(graph)
  local masks, occupied, count = {}, {}, 0
  local function add(p, direction)
    if not point(p) then
      error("diagram exceeds the 500 by 500 cell canvas")
    end
    local key = p[1] .. ":" .. p[2]
    if not masks[key] then
      count = count + 1
      if count > 10000 then
        error("diagram exceeds 10000 drawing cells")
      end
      masks[key] = { row = p[1], col = p[2], mask = 0 }
    end
    masks[key].mask = bit.bor(masks[key].mask, direction)
  end
  local function segment(a, b, edge)
    if not point(a) or not point(b) or (a[1] ~= b[1] and a[2] ~= b[2]) then
      error("connector is no longer orthogonal; undo the move or reconnect")
    end
    local dr = a[1] == b[1] and 0 or (a[1] < b[1] and 1 or -1)
    local dc = a[2] == b[2] and 0 or (a[2] < b[2] and 1 or -1)
    local outward = dr == 1 and 4 or dr == -1 and 1 or dc == 1 and 2 or 8
    local inward = dr == 1 and 1 or dr == -1 and 4 or dc == 1 and 8 or 2
    local length = math.abs(a[1] - b[1]) + math.abs(a[2] - b[2])
    for step = 0, length do
      local p = { a[1] + dr * step, a[2] + dc * step }
      if edge then
        local owner = occupied[p[1] .. ":" .. p[2]]
        if owner then
          local at_source = owner == edge.source and vim.deep_equal(p, anchor(graph.boxes[owner], edge.source_side))
          local at_target = owner == edge.target and vim.deep_equal(p, anchor(graph.boxes[owner], edge.target_side))
          if not at_source and not at_target then
            error("connector would cross a box; move a segment or the box first")
          end
        end
      end
      if step < length then
        add(p, outward)
      end
      if step > 0 then
        add(p, inward)
      end
    end
  end
  local ok, message = pcall(function()
    for _, box in pairs(graph.boxes) do
      if not point({ box.top, box.left }) or not point({ box.bottom, box.right }) then
        error("box exceeds the 500 by 500 cell canvas")
      end
      for row = box.top, box.bottom do
        for col = box.left, box.right do
          local key = row .. ":" .. col
          if occupied[key] then
            error("boxes cannot overlap or touch")
          end
          occupied[key] = box.id
        end
      end
      segment({ box.top, box.left }, { box.top, box.right })
      segment({ box.bottom, box.left }, { box.bottom, box.right })
      segment({ box.top, box.left }, { box.bottom, box.left })
      segment({ box.top, box.right }, { box.bottom, box.right })
    end
    for _, edge in pairs(graph.edges) do
      local points = M.route(graph, edge)
      for i = 1, #points - 1 do
        segment(points[i], points[i + 1], edge)
      end
    end
  end)
  if not ok then
    return nil, tostring(message):gsub("^.-:%d+: ", "")
  end
  for _, cell in pairs(masks) do
    local edges = {}
    for _, direction in ipairs(glyphs.directions) do
      if bit.band(cell.mask, direction) ~= 0 then
        edges[direction] = 1
      end
    end
    cell.glyph = glyphs.by_edges[glyphs.key(edges)]
    cell.mask = nil
  end
  return masks
end

return M
