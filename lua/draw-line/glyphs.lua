-- Factual orthogonal edge assignments from the Unicode Box Drawing names:
-- https://www.unicode.org/charts/PDF/U2500.pdf
-- Each row is { glyph, north, east, south, west }:
-- 0 absent, 1 light, 2 heavy, 3 double.
local definitions = {
  { "─", 0, 1, 0, 1 },
  { "━", 0, 2, 0, 2 },
  { "│", 1, 0, 1, 0 },
  { "┃", 2, 0, 2, 0 },
  { "┌", 0, 1, 1, 0 },
  { "┍", 0, 2, 1, 0 },
  { "┎", 0, 1, 2, 0 },
  { "┏", 0, 2, 2, 0 },
  { "┐", 0, 0, 1, 1 },
  { "┑", 0, 0, 1, 2 },
  { "┒", 0, 0, 2, 1 },
  { "┓", 0, 0, 2, 2 },
  { "└", 1, 1, 0, 0 },
  { "┕", 1, 2, 0, 0 },
  { "┖", 2, 1, 0, 0 },
  { "┗", 2, 2, 0, 0 },
  { "┘", 1, 0, 0, 1 },
  { "┙", 1, 0, 0, 2 },
  { "┚", 2, 0, 0, 1 },
  { "┛", 2, 0, 0, 2 },
  { "├", 1, 1, 1, 0 },
  { "┝", 1, 2, 1, 0 },
  { "┞", 2, 1, 1, 0 },
  { "┟", 1, 1, 2, 0 },
  { "┠", 2, 1, 2, 0 },
  { "┡", 2, 2, 1, 0 },
  { "┢", 1, 2, 2, 0 },
  { "┣", 2, 2, 2, 0 },
  { "┤", 1, 0, 1, 1 },
  { "┥", 1, 0, 1, 2 },
  { "┦", 2, 0, 1, 1 },
  { "┧", 1, 0, 2, 1 },
  { "┨", 2, 0, 2, 1 },
  { "┩", 2, 0, 1, 2 },
  { "┪", 1, 0, 2, 2 },
  { "┫", 2, 0, 2, 2 },
  { "┬", 0, 1, 1, 1 },
  { "┭", 0, 1, 1, 2 },
  { "┮", 0, 2, 1, 1 },
  { "┯", 0, 2, 1, 2 },
  { "┰", 0, 1, 2, 1 },
  { "┱", 0, 1, 2, 2 },
  { "┲", 0, 2, 2, 1 },
  { "┳", 0, 2, 2, 2 },
  { "┴", 1, 1, 0, 1 },
  { "┵", 1, 1, 0, 2 },
  { "┶", 1, 2, 0, 1 },
  { "┷", 1, 2, 0, 2 },
  { "┸", 2, 1, 0, 1 },
  { "┹", 2, 1, 0, 2 },
  { "┺", 2, 2, 0, 1 },
  { "┻", 2, 2, 0, 2 },
  { "┼", 1, 1, 1, 1 },
  { "┽", 1, 1, 1, 2 },
  { "┾", 1, 2, 1, 1 },
  { "┿", 1, 2, 1, 2 },
  { "╀", 2, 1, 1, 1 },
  { "╁", 1, 1, 2, 1 },
  { "╂", 2, 1, 2, 1 },
  { "╃", 2, 1, 1, 2 },
  { "╄", 2, 2, 1, 1 },
  { "╅", 1, 1, 2, 2 },
  { "╆", 1, 2, 2, 1 },
  { "╇", 2, 2, 1, 2 },
  { "╈", 1, 2, 2, 2 },
  { "╉", 2, 1, 2, 2 },
  { "╊", 2, 2, 2, 1 },
  { "╋", 2, 2, 2, 2 },
  { "╵", 1, 0, 0, 0 },
  { "╶", 0, 1, 0, 0 },
  { "╷", 0, 0, 1, 0 },
  { "╴", 0, 0, 0, 1 },
  { "╹", 2, 0, 0, 0 },
  { "╺", 0, 2, 0, 0 },
  { "╻", 0, 0, 2, 0 },
  { "╸", 0, 0, 0, 2 },
  { "╼", 0, 2, 0, 1 },
  { "╽", 1, 0, 2, 0 },
  { "╾", 0, 1, 0, 2 },
  { "╿", 2, 0, 1, 0 },
  { "═", 0, 3, 0, 3 },
  { "║", 3, 0, 3, 0 },
  { "╒", 0, 3, 1, 0 },
  { "╓", 0, 1, 3, 0 },
  { "╔", 0, 3, 3, 0 },
  { "╕", 0, 0, 1, 3 },
  { "╖", 0, 0, 3, 1 },
  { "╗", 0, 0, 3, 3 },
  { "╘", 1, 3, 0, 0 },
  { "╙", 3, 1, 0, 0 },
  { "╚", 3, 3, 0, 0 },
  { "╛", 1, 0, 0, 3 },
  { "╜", 3, 0, 0, 1 },
  { "╝", 3, 0, 0, 3 },
  { "╞", 1, 3, 1, 0 },
  { "╟", 3, 1, 3, 0 },
  { "╠", 3, 3, 3, 0 },
  { "╡", 1, 0, 1, 3 },
  { "╢", 3, 0, 3, 1 },
  { "╣", 3, 0, 3, 3 },
  { "╤", 0, 3, 1, 3 },
  { "╥", 0, 1, 3, 1 },
  { "╦", 0, 3, 3, 3 },
  { "╧", 1, 3, 0, 3 },
  { "╨", 3, 1, 0, 1 },
  { "╩", 3, 3, 0, 3 },
  { "╪", 1, 3, 1, 3 },
  { "╫", 3, 1, 3, 1 },
  { "╬", 3, 3, 3, 3 },
}
local aliases = {
  { "╭", "┌" },
  { "╮", "┐" },
  { "╯", "┘" },
  { "╰", "└" },
  { "╌", "─" },
  { "╎", "│" },
  { "┄", "─" },
  { "┆", "│" },
  { "┈", "─" },
  { "┊", "│" },
  { "╍", "━" },
  { "╏", "┃" },
  { "┅", "━" },
  { "┇", "┃" },
  { "┉", "━" },
  { "┋", "┃" },
}
local M = { by_glyph = {}, by_edges = {}, directions = { 1, 2, 4, 8 } }

local function valid_weight(weight)
  return type(weight) == "number" and weight >= 0 and weight <= 3 and weight % 1 == 0
end

function M.key(edges)
  local n, e, s, w = edges[1], edges[2], edges[4], edges[8]
  if
    (n ~= nil and not valid_weight(n))
    or (e ~= nil and not valid_weight(e))
    or (s ~= nil and not valid_weight(s))
    or (w ~= nil and not valid_weight(w))
  then
    return nil
  end
  -- Four base-4 digits; unknown or invalid weights cannot alias valid edges.
  return (n or 0) * 64 + (e or 0) * 16 + (s or 0) * 4 + (w or 0)
end

for _, definition in ipairs(definitions) do
  assert(#definition == 5, "invalid box-drawing definition")
  local glyph, edges, mask = definition[1], {}, 0
  for index, direction in ipairs(M.directions) do
    local weight = definition[index + 1]
    assert(valid_weight(weight), "invalid edge weight")
    if weight ~= 0 then
      edges[direction], mask = weight, mask + direction
    end
  end
  local key = assert(M.key(edges), "invalid canonical edge weights")
  assert(mask ~= 0 and not M.by_glyph[glyph] and not M.by_edges[key], "empty or duplicate box-drawing definition")
  M.by_glyph[glyph] = { mask = mask, edges = edges }
  M.by_edges[key] = glyph
end

-- Aliases are read as canonical edges without replacing the solid output glyph.
for _, alias in ipairs(aliases) do
  local glyph, canonical = alias[1], alias[2]
  local entry = M.by_glyph[canonical]
  local key = entry and M.key(entry.edges)
  assert(key ~= nil and M.by_edges[key] == canonical, "alias must name a canonical glyph")
  assert(not M.by_glyph[glyph], "duplicate box-drawing alias")
  M.by_glyph[glyph] = entry
end
return M
