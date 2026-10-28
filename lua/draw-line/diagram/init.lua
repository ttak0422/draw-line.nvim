local M = {}
local api, fn = vim.api, vim.fn
local model = require("draw-line.diagram.model")
local storage = require("draw-line.diagram.storage")
local sessions = {}
local namespace = api.nvim_create_namespace("draw-line-diagram")
local keys = { "<LeftMouse>", "<LeftDrag>", "<LeftRelease>", "<Esc>" }

local function fail(message)
  return nil, "draw-line: diagram: " .. message
end

-- Map display cells without splitting tabs, wide characters, or composing clusters.
local function scan(line)
  local cells, col, byte = { blocked = {} }, 1, 0
  for _, glyph in ipairs(fn.split(line, "\\zs")) do
    local width = fn.strdisplaywidth(glyph, col - 1)
    if width == 0 then
      cells.blocked[col], cells.blocked[col - 1] = true, true
    end
    for c = col, col + math.max(width, 1) - 1 do
      cells[c] = { glyph = glyph, width = width, byte = byte, start = col }
    end
    col, byte = col + width, byte + #glyph
  end
  return cells
end

local function project(lines, old, new)
  local rows, targets, last = {}, {}, #lines
  for key, cell in pairs(old) do
    targets[key] = cell
  end
  for key, cell in pairs(new) do
    targets[key], last = cell, math.max(last, cell.row)
  end
  local edits = {}
  for key, cell in pairs(targets) do
    local row, col = cell.row, cell.col
    rows[row] = rows[row] or scan(lines[row] or "")
    local existing = rows[row][col]
    local glyph = existing and existing.glyph or " "
    if rows[row].blocked[col] or (existing and (existing.width ~= 1 or existing.start ~= col)) then
      return fail("drawing touches a tab, wide, or composing character at " .. key)
    end
    if old[key] then
      if glyph ~= old[key].glyph then
        return fail("drawing was edited at " .. key .. "; undo the edit or detach before continuing")
      end
    elseif glyph ~= " " then
      return fail("protected text or unowned linework at " .. key)
    end
    edits[row] = edits[row] or {}
    edits[row][col] = new[key] and new[key].glyph or " "
  end
  local result = vim.deepcopy(lines)
  for row = #result + 1, last do
    result[row] = ""
  end
  for row, changes in pairs(edits) do
    local out, col, limit = {}, 1, 0
    for c in pairs(changes) do
      limit = math.max(limit, c)
    end
    for _, glyph in ipairs(fn.split(result[row], "\\zs")) do
      local width = fn.strdisplaywidth(glyph, col - 1)
      out[#out + 1] = changes[col] or glyph
      col = col + width
    end
    while col <= limit do
      out[#out + 1] = changes[col] or " "
      col = col + 1
    end
    result[row] = table.concat(out)
  end
  return result
end

local function ink(cells)
  local result = {}
  for key, cell in pairs(cells) do
    if cell.glyph ~= " " then
      result[key] = cell
    end
  end
  return result
end

local function recover_underlay(current, saved)
  local restored, message = project(current, ink(saved.cells), {})
  if not restored then
    return nil, message
  end
  for row, line in ipairs(restored) do
    local original = saved.underlay[row] or ""
    local prefix = #original
    if current[row] == saved.lines[row] and #line > prefix and line:sub(prefix + 1):match("^ *$") then
      restored[row] = line:sub(1, prefix)
    end
  end
  while #restored > #saved.underlay and restored[#restored] == "" do
    table.remove(restored)
  end
  return restored
end

local function lines(buf)
  return api.nvim_buf_get_lines(buf, 0, -1, false)
end

local function sequence(buf)
  return api.nvim_buf_call(buf, function()
    return fn.undotree().seq_cur
  end)
end

local function remember(session)
  -- shortcut: undo snapshots are session-local; loading creates a new history baseline.
  session.history[sequence(session.buf)] = {
    graph = vim.deepcopy(session.graph),
    cells = vim.deepcopy(session.cells),
    underlay = vim.deepcopy(session.underlay),
    lines = lines(session.buf),
  }
end

local function ancestor_snapshot(entries, sequence_id, history, inherited)
  for _, entry in ipairs(entries) do
    -- Alternate branches share the preceding entry, not this entry's state.
    local alternate = entry.alt and ancestor_snapshot(entry.alt, sequence_id, history, inherited)
    if alternate then
      return alternate
    end
    inherited = history[entry.seq] or inherited
    if entry.seq == sequence_id then
      return inherited
    end
  end
end

local function sync(session)
  if not sessions[session.buf] or sessions[session.buf] ~= session or not api.nvim_buf_is_loaded(session.buf) then
    return fail("session is detached")
  end
  if api.nvim_get_current_buf() ~= session.buf then
    return fail("switch to the session's buffer before editing its diagram")
  end
  local current = lines(session.buf)
  local tree = fn.undotree()
  local oldest = tree.entries[1]
  while oldest and oldest.alt do
    oldest = oldest.alt[1]
  end
  -- A pruned tree has an unknown base; do not assume the diagram was empty.
  local base = oldest and oldest.seq == 1 and session.history[0] or nil
  local saved = session.history[tree.seq_cur] or ancestor_snapshot(tree.entries, tree.seq_cur, session.history, base)
  if not saved then
    return fail("diagram undo history is unavailable; detach before continuing")
  end
  if #current ~= #saved.lines then
    return fail("buffer row count changed; undo the edit or detach before continuing")
  end
  local underlay, message = recover_underlay(current, saved)
  if not underlay then
    return nil, message
  end
  session.graph, session.cells = vim.deepcopy(saved.graph), vim.deepcopy(saved.cells)
  session.underlay = underlay
  return true
end

local function decorate(session)
  api.nvim_buf_clear_namespace(session.buf, namespace, 0, -1)
  local marks = model.handles(session.graph)
  for _, box in pairs(session.graph.boxes) do
    marks[#marks + 1] = { point = model.center(box), box = box.id }
  end
  for _, mark in ipairs(marks) do
    local p = mark.point
    local line = api.nvim_buf_get_lines(session.buf, p[1] - 1, p[1], false)[1]
    local cell = line and scan(line)[p[2]]
    -- Labels retain their normal appearance; the exact center still acts as a handle.
    local owner = session.cells[p[1] .. ":" .. p[2]]
    if
      owner
      and owner.owner == (mark.edge or mark.box)
      and cell
      and cell.width == 1
      and (mark.edge or cell.glyph == " ")
    then
      api.nvim_buf_set_extmark(session.buf, namespace, p[1] - 1, cell.byte, {
        virt_text = { { mark.edge and "●" or "◆", "Special" } },
        virt_text_pos = "overlay",
        hl_mode = "combine",
      })
    end
  end
end

local function commit(session, mutate)
  local ok, message = sync(session)
  if not ok then
    return nil, message
  end
  if not vim.bo[session.buf].modifiable or vim.bo[session.buf].readonly then
    return fail("buffer must be modifiable and not readonly")
  end
  local undo = vim.bo[session.buf].undolevels
  if (undo == -123456 and vim.go.undolevels or undo) < 1 then
    return fail("native undo must be enabled")
  end
  local graph = vim.deepcopy(session.graph)
  local value
  value, message = mutate(graph)
  if not value then
    return fail(message)
  end
  local cells
  cells, message = model.render(graph)
  if not cells then
    return fail(message)
  end
  for _, cell in pairs(cells) do
    if fn.strdisplaywidth(cell.glyph) ~= 1 then
      return fail("drawing glyphs must occupy one display cell")
    end
  end
  local before = lines(session.buf)
  local after
  after, message = project(session.underlay, {}, ink(cells))
  if not after then
    return nil, message
  end
  if vim.deep_equal(before, after) then
    if vim.deep_equal(graph, session.graph) then
      return value
    end
  end
  remember(session)
  local first, last_before, last_after = 1, #before, #after
  while first <= #before and first <= #after and before[first] == after[first] do
    first = first + 1
  end
  while last_before >= first and last_after >= first and before[last_before] == after[last_after] do
    last_before, last_after = last_before - 1, last_after - 1
  end
  if first > #before and first > #after then
    first, last_before, last_after = 1, 1, 1
  end
  -- One release is one undo block, including all connected edges.
  vim.go.undolevels = vim.go.undolevels
  ok, message =
    pcall(api.nvim_buf_set_lines, session.buf, first - 1, last_before, false, vim.list_slice(after, first, last_after))
  if not ok then
    return fail(tostring(message))
  end
  session.graph, session.cells = graph, cells
  remember(session)
  decorate(session)
  return value
end

local function view(win)
  return api.nvim_win_call(win, function()
    local v = fn.winsaveview()
    return {
      v.topline,
      v.leftcol,
      v.skipcol,
      api.nvim_win_get_width(win),
      api.nvim_win_get_height(win),
      fn.getwininfo(win)[1].textoff,
      api.nvim_win_get_position(win),
    }
  end)
end

local function mouse_point(session)
  local mouse = fn.getmousepos()
  local win = mouse.winid
  if win == 0 or not api.nvim_win_is_valid(win) or api.nvim_win_get_buf(win) ~= session.buf then
    return nil
  end
  local position = api.nvim_win_get_position(win)
  local info = fn.getwininfo(win)[1]
  -- Screen columns include number/sign/fold gutters; use the actual text origin.
  local col = mouse.screencol - position[2] - info.textoff
  local textrow = mouse.screenrow - info.winrow - info.winbar + 1
  if
    col < 1
    or col > api.nvim_win_get_width(win) - info.textoff
    or mouse.line < 1
    or textrow < 1
    or textrow > info.height
  then
    return nil
  end
  local supported = api.nvim_win_call(win, function()
    for line = info.topline, info.botline do
      if fn.foldclosed(line) ~= -1 then
        return false
      end
    end
    return not vim.wo.wrap and not vim.wo.rightleft and vim.wo.conceallevel == 0 and not vim.wo.diff
  end)
  if not supported then
    return nil
  end
  -- In an unfolded nowrap window, rows include blank space below EOF, even
  -- when horizontal scrolling makes screenpos(..., 1) unavailable.
  local row = info.topline + textrow - 1
  local v = view(win)
  return { row, col + v[2] }, win, v
end

local function object_at(session, p)
  local cell = session.cells[p[1] .. ":" .. p[2]]
  return cell and cell.owner
end

local function report(ok, message)
  if not ok then
    vim.notify(message, vim.log.levels.WARN)
  end
end

local function saved_text(buf)
  local path = api.nvim_buf_get_name(buf)
  if path == "" or vim.bo[buf].buftype ~= "" or vim.bo[buf].modified then
    return fail("write this named, ordinary buffer before saving or loading its sidecar")
  end
  local text, message = storage.buffer_bytes(buf)
  if not text then
    return fail(message)
  end
  local actual
  actual, message = storage.read(path)
  if actual and not vim.bo[buf].endofline and vim.bo[buf].fixendofline then
    local separator = vim.bo[buf].fileformat == "dos" and "\r\n" or "\n"
    if actual == text .. separator then
      text = actual
    end
  end
  if not actual or actual ~= text then
    return fail(message or "file differs from this buffer; reload or write it explicitly first")
  end
  return text, path
end

--- Opt-in, buffer-local diagram editing. Existing text is never adopted as objects.
function M.attach()
  local buf = api.nvim_get_current_buf()
  if sessions[buf] then
    return fail("buffer already has a diagram session")
  end
  if #lines(buf) > 500 then
    return fail("PoC supports buffers of at most 500 rows")
  end
  for _, mapping in ipairs(api.nvim_buf_get_keymap(buf, "n")) do
    for _, key in ipairs(keys) do
      if
        api.nvim_replace_termcodes(mapping.lhs, true, true, true) == api.nvim_replace_termcodes(key, true, true, true)
      then
        return fail("buffer-local mapping already exists for " .. key)
      end
    end
  end
  local session = { buf = buf, graph = model.new(), cells = {}, underlay = lines(buf), history = {}, tool = "select" }
  sessions[buf] = session

  function session:cancel()
    self.gesture, self.source = nil, nil
    return true
  end

  function session:set_tool(tool)
    if tool ~= "select" and tool ~= "connect" then
      return fail("tool must be select or connect")
    end
    self:cancel()
    self.tool = tool
    return true
  end

  function session:box(a, b)
    return commit(self, function(graph)
      return model.box(graph, a, b)
    end)
  end

  function session:connect(source, target)
    return commit(self, function(graph)
      return model.connect(graph, source, target)
    end)
  end

  function session:move(id, destination)
    return commit(self, function(graph)
      return model.move(graph, id, destination)
    end)
  end

  function session:bend(id, segment, destination)
    return commit(self, function(graph)
      return model.bend(graph, id, segment, destination)
    end)
  end

  function session:raise(id)
    return commit(self, function(graph)
      return model.raise(graph, id)
    end)
  end

  function session:save()
    local ok, message = sync(self)
    if not ok then
      return nil, message
    end
    local text, path = saved_text(self.buf)
    if not text then
      return nil, path
    end
    local data, document = storage.encode(self, text)
    if not data then
      return fail(document)
    end
    local sidecar = path .. ".draw-line.json"
    local expected = self.saved and self.saved.path == sidecar and self.saved.hash or false
    ok, message = storage.atomic_write(sidecar, data, expected)
    if not ok then
      return fail(message)
    end
    self.saved =
      { path = sidecar, hash = fn.sha256(data), document_id = document.document_id, revision = document.revision }
    return true, sidecar
  end

  function session:inspect()
    local ok, message = sync(self)
    if not ok then
      return nil, message
    end
    decorate(self)
    return vim.deepcopy(self.graph)
  end

  function session:mouse(action)
    local p, win, viewport = mouse_point(self)
    if action == "press" then
      self.gesture = nil
      local ok, message = sync(self)
      if not ok then
        return nil, message
      end
      if not p then
        self:cancel()
        return fail("mouse needs an unfolded, nowrap, unconcealed text area")
      end
      local selected = object_at(self, p)
      if self.tool == "connect" then
        local id = selected and self.graph.boxes[selected] and selected
        if not id then
          self:cancel()
          return fail("click a source box, then a target box")
        end
        if self.source then
          local source = self.source
          self.source = nil
          return self:connect(source, id)
        end
        self.source = id
        return true
      end
      local gesture =
        { start = p, win = win, view = viewport, tick = api.nvim_buf_get_changedtick(self.buf), selected = selected }
      local box = selected and self.graph.boxes[selected]
      if box and vim.deep_equal(model.center(box), p) then
        gesture.box = selected
      elseif selected and self.graph.edges[selected] then
        for _, handle in ipairs(model.handles(self.graph)) do
          if handle.edge == selected and vim.deep_equal(handle.point, p) then
            gesture.handle = handle
            break
          end
        end
      end
      self.gesture = gesture
      decorate(self)
      return true
    end
    local gesture = self.gesture
    if not gesture then
      return true
    end
    if
      not p
      or win ~= gesture.win
      or not vim.deep_equal(viewport, gesture.view)
      or api.nvim_buf_get_changedtick(self.buf) ~= gesture.tick
    then
      self:cancel()
      return true
    end
    if action == "drag" then
      return true
    end
    self.gesture = nil
    if vim.deep_equal(p, gesture.start) then
      if gesture.selected then
        return self:raise(gesture.selected)
      end
      return true
    end
    if gesture.box then
      return self:move(gesture.box, p)
    elseif gesture.handle then
      return self:bend(gesture.handle.edge, gesture.handle.segment, p)
    elseif gesture.selected then
      return fail("drag the selected object's visible center or segment handle")
    end
    return self:box(gesture.start, p)
  end

  local callbacks, native_mouse = {}, false
  for key, action in pairs({ ["<LeftMouse>"] = "press", ["<LeftDrag>"] = "drag", ["<LeftRelease>"] = "release" }) do
    callbacks[key] = function()
      if action == "press" then
        local mouse = fn.getmousepos()
        native_mouse = mouse.winid ~= api.nvim_get_current_win() or mouse.line == 0
        if native_mouse then
          session:cancel()
        end
      end
      if native_mouse then
        if action == "release" then
          native_mouse = false
        end
        -- Replay the native mouse action with its original position, without remapping.
        vim.cmd("normal! " .. api.nvim_replace_termcodes(key, true, false, true))
        return
      end
      report(session:mouse(action))
    end
  end
  callbacks["<Esc>"] = function()
    native_mouse = false
    session:cancel()
  end
  for key, callback in pairs(callbacks) do
    vim.keymap.set("n", key, callback, { buffer = buf, desc = "draw-line diagram PoC" })
  end
  local group = api.nvim_create_augroup("DrawLineDiagram" .. buf, { clear = true })
  api.nvim_create_autocmd({ "BufLeave", "BufWinLeave", "InsertEnter" }, {
    group = group,
    buffer = buf,
    callback = function()
      session:cancel()
    end,
  })
  api.nvim_create_autocmd({ "WinLeave", "VimResized", "WinScrolled" }, {
    group = group,
    callback = function()
      session:cancel()
    end,
  })
  api.nvim_create_autocmd("TextChanged", {
    group = group,
    buffer = buf,
    callback = function()
      session:cancel()
      if sync(session) then
        decorate(session)
      else
        api.nvim_buf_clear_namespace(buf, namespace, 0, -1)
      end
    end,
  })

  function session:detach()
    if sessions[buf] ~= self then
      return true
    end
    self:cancel()
    sessions[buf] = nil
    api.nvim_del_augroup_by_id(group)
    if api.nvim_buf_is_valid(buf) then
      api.nvim_buf_clear_namespace(buf, namespace, 0, -1)
      for key, callback in pairs(callbacks) do
        local mapping = api.nvim_buf_call(buf, function()
          return fn.maparg(key, "n", false, true)
        end)
        if mapping.callback == callback then
          vim.keymap.del("n", key, { buffer = buf })
        end
      end
    end
    return true
  end

  api.nvim_create_autocmd("BufWipeout", {
    group = group,
    buffer = buf,
    callback = function()
      session:detach()
    end,
  })
  remember(session)
  return session
end

--- Explicitly restore a matching sidecar; no text or files are changed by loading.
function M.load()
  local buf = api.nvim_get_current_buf()
  if sessions[buf] then
    return fail("detach the current session before loading")
  end
  local text, path = saved_text(buf)
  if not text then
    return nil, path
  end
  local sidecar = path .. ".draw-line.json"
  local data, message = storage.read(sidecar)
  if not data then
    return fail(message or "sidecar is missing; existing text will not be inferred as objects")
  end
  local document, cells = storage.decode(data)
  if not document then
    return fail(cells)
  end
  if document.text_hash ~= fn.sha256(text) then
    return fail("text hash differs from the sidecar")
  end
  if not vim.deep_equal(document.display, storage.display(buf)) then
    return fail("sidecar display settings differ")
  end
  for _, cell in pairs(cells) do
    if fn.strdisplaywidth(cell.glyph) ~= 1 then
      return fail("drawing glyphs must occupy one display cell")
    end
  end
  local projected
  projected, message = project(document.underlay, {}, ink(cells))
  if not projected then
    return nil, message
  end
  if not vim.deep_equal(projected, lines(buf)) then
    return fail("sidecar projection does not match this buffer")
  end
  local session
  session, message = M.attach()
  if not session then
    return nil, message
  end
  session.graph, session.cells, session.underlay = document.graph, cells, document.underlay
  session.saved =
    { path = sidecar, hash = fn.sha256(data), document_id = document.document_id, revision = document.revision }
  session.history = {}
  remember(session)
  decorate(session)
  return session
end

return M
