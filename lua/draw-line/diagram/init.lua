local M = {}
local api, fn = vim.api, vim.fn
local model = require("draw-line.diagram.model")
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

local function lines(buf)
  return api.nvim_buf_get_lines(buf, 0, -1, false)
end

local function sequence(buf)
  return api.nvim_buf_call(buf, function()
    return fn.undotree().seq_cur
  end)
end

local function remember(session)
  -- shortcut: undo snapshots live for one buffer session; persistence needs a versioned graph format.
  session.history[sequence(session.buf)] = {
    graph = vim.deepcopy(session.graph),
    cells = vim.deepcopy(session.cells),
    lines = lines(session.buf),
  }
end

local function sync(session)
  if not sessions[session.buf] or sessions[session.buf] ~= session or not api.nvim_buf_is_loaded(session.buf) then
    return fail("session is detached")
  end
  if api.nvim_get_current_buf() ~= session.buf then
    return fail("switch to the session's buffer before editing its diagram")
  end
  local current = lines(session.buf)
  local saved = session.history[sequence(session.buf)]
  if saved and vim.deep_equal(current, saved.lines) then
    session.graph, session.cells = vim.deepcopy(saved.graph), vim.deepcopy(saved.cells)
    session.row_count = #current
  elseif #current ~= session.row_count then
    return fail("buffer row count changed; undo the edit or detach before continuing")
  end
  local ok, message = project(current, session.cells, session.cells)
  if not ok then
    return nil, message
  end
  return true
end

local function decorate(session)
  api.nvim_buf_clear_namespace(session.buf, namespace, 0, -1)
  local marks = model.handles(session.graph)
  for _, box in pairs(session.graph.boxes) do
    marks[#marks + 1] = { point = model.center(box) }
  end
  for _, mark in ipairs(marks) do
    local p = mark.point
    local line = api.nvim_buf_get_lines(session.buf, p[1] - 1, p[1], false)[1]
    local cell = line and scan(line)[p[2]]
    -- Labels retain their normal appearance; the exact center still acts as a handle.
    if cell and cell.width == 1 and (mark.edge or cell.glyph == " ") then
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
  after, message = project(before, session.cells, cells)
  if not after then
    return nil, message
  end
  if vim.deep_equal(before, after) then
    return fail("operation has no visible change")
  end
  remember(session)
  local first, last_before, last_after = 1, #before, #after
  while before[first] == after[first] do
    first = first + 1
  end
  while last_before >= first and last_after >= first and before[last_before] == after[last_after] do
    last_before, last_after = last_before - 1, last_after - 1
  end
  -- One release is one undo block, including all connected edges.
  vim.go.undolevels = vim.go.undolevels
  ok, message =
    pcall(api.nvim_buf_set_lines, session.buf, first - 1, last_before, false, vim.list_slice(after, first, last_after))
  if not ok then
    return fail(tostring(message))
  end
  session.graph, session.cells, session.row_count = graph, cells, #after
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
  local row = mouse.line
  if col < 1 or col > api.nvim_win_get_width(win) - info.textoff or row < 1 then
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
  if row == api.nvim_buf_line_count(session.buf) then
    local last = fn.screenpos(win, row, 1)
    if last.row > 0 and mouse.screenrow > last.row then
      row = row + mouse.screenrow - last.row
    end
  end
  local v = view(win)
  return { row, col + v[2] }, win, v
end

local function box_at(graph, p, center_only)
  for _, box in pairs(graph.boxes) do
    if
      (center_only and vim.deep_equal(model.center(box), p))
      or (not center_only and p[1] >= box.top and p[1] <= box.bottom and p[2] >= box.left and p[2] <= box.right)
    then
      return box.id
    end
  end
end

local function report(ok, message)
  if not ok then
    vim.notify(message, vim.log.levels.WARN)
  end
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
  local session = { buf = buf, graph = model.new(), cells = {}, history = {}, row_count = #lines(buf), tool = "select" }
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
      if self.tool == "connect" then
        local id = box_at(self.graph, p)
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
      local gesture = { start = p, win = win, view = viewport, tick = api.nvim_buf_get_changedtick(self.buf) }
      gesture.box = box_at(self.graph, p, true)
      if not gesture.box then
        for _, handle in ipairs(model.handles(self.graph)) do
          if vim.deep_equal(handle.point, p) then
            gesture.handle = handle
            break
          end
        end
      end
      if not gesture.box and not gesture.handle and box_at(self.graph, p) then
        return fail("drag a box's exact center handle to move it")
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
      return fail("gesture cancelled after leaving its window, scrolling, resizing, or editing")
    end
    if action == "drag" then
      return true
    end
    self.gesture = nil
    if vim.deep_equal(p, gesture.start) then
      return true
    end
    if gesture.box then
      return self:move(gesture.box, p)
    elseif gesture.handle then
      return self:bend(gesture.handle.edge, gesture.handle.segment, p)
    end
    return self:box(gesture.start, p)
  end

  local callbacks = {}
  for key, action in pairs({ ["<LeftMouse>"] = "press", ["<LeftDrag>"] = "drag", ["<LeftRelease>"] = "release" }) do
    callbacks[key] = function()
      report(session:mouse(action))
    end
  end
  callbacks["<Esc>"] = function()
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

return M
