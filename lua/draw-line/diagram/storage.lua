local M = {}
local uv, fn = vim.uv, vim.fn
local model = require("draw-line.diagram.model")
local MAX_BYTES = 4 * 1024 * 1024
local serial = 0

function M.read(path)
  local stat, err, code = uv.fs_lstat(path)
  if not stat then
    if code == "ENOENT" then
      return nil
    end
    return nil, err
  end
  if stat.type ~= "file" or stat.size > MAX_BYTES then
    return nil, "expected a regular file of at most 4 MiB: " .. path
  end
  local fd
  fd, err = uv.fs_open(path, "r", 0)
  if not fd then
    return nil, err
  end
  local data
  data, err = uv.fs_read(fd, stat.size, 0)
  uv.fs_close(fd)
  return data, err
end

function M.buffer_bytes(buf)
  local bo = vim.bo[buf]
  if bo.binary then
    return nil, "binary buffers are unsupported"
  end
  if (bo.fileencoding ~= "" and bo.fileencoding ~= "utf-8") or (bo.fileformat ~= "unix" and bo.fileformat ~= "dos") then
    return nil, "persistence requires UTF-8 with unix or dos line endings"
  end
  local separator = bo.fileformat == "dos" and "\r\n" or "\n"
  local text = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), separator)
  if text:find("\0", 1, true) then
    return nil, "NUL text is unsupported"
  end
  if bo.endofline then
    text = text .. separator
  end
  if bo.bomb then
    text = "\239\187\191" .. text
  end
  return text
end

function M.display(buf)
  return { tabstop = vim.bo[buf].tabstop, vartabstop = vim.bo[buf].vartabstop, ambiwidth = vim.o.ambiwidth }
end

local function integer(n, low, high)
  return type(n) == "number" and n % 1 == 0 and n >= low and n <= high
end

local function list(value, limit)
  assert(type(value) == "table" and vim.islist(value) and #value <= limit, "invalid or oversized list")
  return value
end

local function valid_point(p)
  list(p, 2)
  assert(#p == 2 and integer(p[1], 1, 500) and integer(p[2], 1, 500), "invalid waypoint")
  return { p[1], p[2] }
end

local function restore(document)
  assert(type(document) == "table" and document.schema_version == 1, "unknown sidecar schema version")
  local identity = document.document_id
  assert(type(identity) == "string" and identity:match("^[a-f0-9]+$") and #identity == 64, "invalid document ID")
  assert(integer(document.revision, 1, 1000000000), "invalid revision")
  assert(
    type(document.text_hash) == "string" and #document.text_hash == 64 and document.text_hash:match("^[a-f0-9]+$"),
    "invalid text hash"
  )
  local display = document.display
  assert(type(display) == "table" and integer(display.tabstop, 1, 999), "invalid display settings")
  assert(type(display.vartabstop) == "string" and #display.vartabstop <= 128, "invalid tab stops")
  assert(display.ambiwidth == "single" or display.ambiwidth == "double", "invalid ambiguous width")
  list(document.underlay, 500)
  assert(#document.underlay >= 1, "empty underlay")
  for _, line in ipairs(document.underlay) do
    assert(
      type(line) == "string" and not line:find("\n", 1, true) and not line:find("\0", 1, true),
      "invalid underlay line"
    )
  end
  local source, graph, ids, largest = document.graph, model.new(), {}, 0
  assert(type(source) == "table", "missing graph")
  local function id(object)
    assert(
      type(object) == "table" and integer(object.id, 1, 999999999) and not ids[object.id],
      "invalid or duplicate object ID"
    )
    ids[object.id], largest = true, math.max(largest, object.id)
  end
  local boxes, edges = list(source.boxes, 100), list(source.edges, 100)
  assert(#boxes + #edges <= 100, "more than 100 objects")
  for _, box in ipairs(boxes) do
    id(box)
    valid_point({ box.top, box.left })
    valid_point({ box.bottom, box.right })
    assert(box.bottom - box.top >= 2 and box.right - box.left >= 2, "invalid box dimensions")
    graph.boxes[box.id] = { id = box.id, top = box.top, bottom = box.bottom, left = box.left, right = box.right }
  end
  local sides = { left = true, right = true, top = true, bottom = true }
  for _, edge in ipairs(edges) do
    id(edge)
    assert(graph.boxes[edge.source] and graph.boxes[edge.target] and edge.source ~= edge.target, "invalid edge anchors")
    assert(sides[edge.source_side] and sides[edge.target_side], "invalid anchor sides")
    local waypoints = {}
    assert(#list(edge.waypoints, 128) >= 2, "missing terminal waypoints")
    for _, p in ipairs(edge.waypoints) do
      waypoints[#waypoints + 1] = valid_point(p)
    end
    graph.edges[edge.id] = {
      id = edge.id,
      source = edge.source,
      target = edge.target,
      source_side = edge.source_side,
      target_side = edge.target_side,
      waypoints = waypoints,
    }
  end
  assert(integer(source.next_id, largest + 1, 1000000000), "invalid next ID")
  graph.next_id = source.next_id
  for _, object in ipairs(list(source.z_order, 100)) do
    assert(ids[object], "missing or repeated z-order object")
    ids[object] = nil
    graph.z_order[#graph.z_order + 1] = object
  end
  assert(next(ids) == nil, "incomplete z-order")
  local cells, message = model.render(graph)
  assert(cells, message)
  return {
    graph = graph,
    underlay = vim.deepcopy(document.underlay),
    display = display,
    document_id = document.document_id,
    revision = document.revision,
    text_hash = document.text_hash,
  },
    cells
end

function M.decode(data)
  local ok, document, cells = pcall(function()
    return restore(vim.json.decode(data))
  end)
  if not ok then
    return nil, "invalid sidecar: " .. tostring(document)
  end
  return document, cells
end

function M.encode(session, text)
  local graph = { boxes = {}, edges = {}, next_id = session.graph.next_id, z_order = session.graph.z_order }
  for _, id in ipairs(session.graph.z_order) do
    local object = session.graph.boxes[id] or session.graph.edges[id]
    local group = session.graph.boxes[id] and graph.boxes or graph.edges
    group[#group + 1] = object
  end
  local saved = session.saved or {}
  local document = {
    schema_version = 1,
    document_id = saved.document_id or fn.sha256(tostring(uv.hrtime()) .. tostring(uv.os_getpid())),
    revision = (saved.revision or 0) + 1,
    text_hash = fn.sha256(text),
    display = M.display(session.buf),
    graph = graph,
    underlay = session.underlay,
  }
  local data = vim.json.encode(document)
  if #data > MAX_BYTES then
    return nil, "sidecar exceeds 4 MiB"
  end
  local restored, message = M.decode(data)
  if not restored then
    return nil, message
  end
  return data, restored
end

function M.atomic_write(path, data, expected_hash)
  local lock, err = uv.fs_open(path .. ".lock", "wx", 384)
  if not lock then
    return nil, "sidecar is locked: " .. tostring(err)
  end
  serial = serial + 1
  local temporary = path .. ".tmp-" .. uv.os_getpid() .. "-" .. serial
  local fd, created
  local ok, message = pcall(function()
    local current, read_error = M.read(path)
    assert(not read_error, read_error)
    assert((current and fn.sha256(current) or false) == expected_hash, "sidecar changed or already exists")
    fd, err = uv.fs_open(temporary, "wx", 384)
    assert(fd, err)
    created = true
    local offset = 0
    while offset < #data do
      local written, write_error = uv.fs_write(fd, data:sub(offset + 1), offset)
      assert(written and written > 0, write_error or "short write")
      offset = offset + written
    end
    local flushed, flush_error = uv.fs_fsync(fd)
    assert(flushed, flush_error)
    uv.fs_close(fd)
    fd = nil
    current, read_error = M.read(path)
    assert(not read_error, read_error)
    assert((current and fn.sha256(current) or false) == expected_hash, "sidecar changed during save")
    local renamed, rename_error = uv.fs_rename(temporary, path)
    assert(renamed, rename_error)
    created = false
  end)
  if fd then
    uv.fs_close(fd)
  end
  if created then
    uv.fs_unlink(temporary)
  end
  uv.fs_close(lock)
  uv.fs_unlink(path .. ".lock")
  if not ok then
    return nil, tostring(message)
  end
  return true
end

return M
