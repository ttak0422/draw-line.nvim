-- A separate embedded Nvim with a real UI grid; never touches a user's server/config.
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
local uv = vim.uv
local stdin, stdout, stderr = uv.new_pipe(false), uv.new_pipe(false), uv.new_pipe(false)
local exited, errors, replies, request = false, "", {}, 0
local child = assert(uv.spawn(vim.v.progpath, {
  args = { "--embed", "-u", "NONE", "-i", "NONE", "-n" },
  stdio = { stdin, stdout, stderr },
}, function()
  exited = true
end))
local unpacker = vim.mpack.Unpacker()
stdout:read_start(function(err, data)
  assert(not err, err)
  if data then
    local pos = 1
    while pos <= #data do
      local item
      item, pos = unpacker(data, pos)
      if item and item[1] == 1 then
        replies[item[2]] = item
      end
    end
  end
end)
stderr:read_start(function(_, data)
  errors = errors .. (data or "")
end)
local function stop()
  if not exited then
    child:kill("sigterm")
    vim.wait(1000, function()
      return exited
    end)
  end
  for _, handle in ipairs({ stdin, stdout, stderr, child }) do
    if not handle:is_closing() then
      handle:close()
    end
  end
end
local function rpc(method, ...)
  request = request + 1
  local id = request
  stdin:write(vim.mpack.encode({ 0, id, method, { ... } }))
  assert(
    vim.wait(3000, function()
      return replies[id] ~= nil or exited
    end),
    "RPC timed out: " .. method .. errors
  )
  local reply = replies[id]
  replies[id] = nil
  assert(reply, "child exited: " .. errors)
  assert(reply[3] == vim.NIL, method .. ": " .. vim.inspect(reply[3]))
  return reply[4]
end
local function lua(code, ...)
  return rpc("nvim_exec_lua", code, { ... })
end
local function equal(actual, expected)
  assert(vim.deep_equal(actual, expected), "expected " .. vim.inspect(expected) .. ", got " .. vim.inspect(actual))
end
local function graph()
  return lua("return assert(_G.diagram:inspect())")
end
local function mouse(action, row, col)
  rpc("nvim_input_mouse", "left", action, "", 0, row - 1, col - 1)
  -- nvim_input_mouse queues input; separate events to avoid position coalescing.
  vim.wait(20)
  lua("return vim.fn.mode()")
  if vim.env.DRAW_LINE_MOUSE_DEBUG then
    print(
      action,
      vim.inspect(
        lua("return {vim.fn.getmousepos(), _G.diagram.gesture, vim.api.nvim_exec2('messages', {output=true})}")
      )
    )
  end
end
local function drag(row, col, to_row, to_col)
  mouse("press", row, col)
  mouse("drag", to_row, to_col)
  mouse("release", to_row, to_col)
end
local function input(keys)
  rpc("nvim_input", keys)
  vim.wait(20)
  lua("return vim.fn.mode()")
end
local ok, message = xpcall(function()
  rpc("nvim_ui_attach", 90, 28, { rgb = true, ext_linegrid = true })
  lua(
    [[
    vim.opt.runtimepath:prepend(...)
    vim.o.mouse, vim.o.mousemodel = "a", "extend"
    vim.wo.wrap, vim.wo.conceallevel, vim.wo.number, vim.wo.relativenumber = false, 0, false, false
    vim.wo.signcolumn, vim.wo.foldcolumn = "no", "0"
    vim.api.nvim_buf_set_lines(0, 0, -1, false, vim.fn["repeat"]({""}, 40))
    _G.diagram = assert(require("draw-line.diagram").attach())
  ]],
    root
  )
  drag(2, 2, 6, 8)
  equal(graph().boxes[1], { id = 1, top = 2, bottom = 6, left = 2, right = 8 })
  drag(4, 20, 8, 26)
  equal(vim.tbl_count(graph().boxes), 2)
  lua("assert(_G.diagram:set_tool('connect'))")
  mouse("press", 4, 5)
  mouse("release", 4, 5)
  mouse("press", 6, 23)
  mouse("release", 6, 23)
  equal((graph().edges[3] ~= vim.NIL and 1 or 0), 1)
  lua("assert(_G.diagram:set_tool('select'))")
  drag(5, 14, 5, 16)
  equal(graph().edges[3].waypoints[1][2], 16)
  drag(4, 5, 10, 5)
  equal(graph().boxes[1].top, 8)
  lua("vim.cmd.undo()")
  equal(graph().boxes[1].top, 2)
  lua("vim.cmd.redo()")
  equal(graph().boxes[1].top, 8)

  local before = graph()
  mouse("press", 15, 3)
  mouse("drag", 19, 10)
  lua("_G.diagram:cancel()")
  mouse("release", 19, 10)
  equal(graph(), before)
  mouse("press", 15, 3)
  lua("vim.api.nvim_input(vim.keycode('<Esc>'))")
  vim.wait(20)
  mouse("release", 19, 10)
  equal(graph(), before)
  mouse("press", 15, 3)
  rpc("nvim_ui_try_resize", 100, 30)
  mouse("release", 19, 10)
  equal(graph(), before)
  mouse("press", 15, 3)
  lua("vim.cmd('normal! 2\\x05')")
  mouse("release", 19, 10)
  equal(graph(), before)
  lua("vim.cmd('normal! gg'); vim.wo.wrap = true")
  drag(15, 3, 19, 10)
  equal(graph(), before)

  -- A fresh buffer with number/sign gutters and horizontal and vertical scrolling.
  lua([[
    _G.diagram:detach()
    vim.cmd('enew!')
    vim.wo.wrap, vim.wo.number, vim.wo.signcolumn = false, true, "yes:2"
    vim.api.nvim_buf_set_lines(0, 0, -1, false, vim.fn["repeat"]({string.rep(' ', 160)}, 70))
    _G.diagram = assert(require('draw-line.diagram').attach())
    vim.fn.winrestview({topline = 10, leftcol = 20, lnum = 10, col = 20})
  ]])
  local origin = lua("local i = vim.fn.getwininfo(vim.api.nvim_get_current_win())[1]; return i.textoff")
  drag(2, origin + 3, 6, origin + 9)
  local box = graph().boxes[1]
  equal({ box.top, box.bottom, box.left, box.right }, { 11, 15, 23, 29 })
  local count = vim.tbl_count(graph().boxes)
  drag(2, 1, 6, 6)
  equal(vim.tbl_count(graph().boxes), count)
  -- Release in another split cannot complete a gesture begun in this one.
  mouse("press", 18, origin + 3)
  lua("vim.cmd('vsplit'); vim.cmd('wincmd l')")
  mouse("release", 22, 85)
  equal(vim.tbl_count(graph().boxes), count)
  lua([[
    _G.diagram:detach()
    vim.cmd('only'); vim.cmd('enew!')
    vim.wo.number, vim.wo.signcolumn = false, "no"
    _G.diagram = assert(require('draw-line.diagram').attach())
  ]])
  drag(1, 2, 5, 8)
  equal(graph().boxes[1], { id = 1, top = 1, bottom = 5, left = 2, right = 8 })

  -- Column 1 is offscreen: extending below EOF must not rely on screenpos(..., 1).
  lua([[
    _G.diagram:detach()
    vim.cmd('enew!')
    vim.api.nvim_buf_set_lines(0, 0, -1, false, {"日本\t" .. string.rep(' ', 100) .. " tail"})
    _G.diagram = assert(require('draw-line.diagram').attach())
    vim.fn.winrestview({topline = 1, leftcol = 20, lnum = 1, col = 20})
  ]])
  equal(lua("return vim.fn.winsaveview().leftcol"), 20)
  equal(lua("return vim.fn.screenpos(0, 1, 1).row"), 0)
  drag(1, 2, 5, 8)
  equal(graph().boxes[1], { id = 1, top = 1, bottom = 5, left = 22, right = 28 })
  equal(lua("return vim.api.nvim_get_current_line():sub(1, 7)"), "日本\t")
  assert(lua("return vim.api.nvim_buf_get_lines(0, 0, 1, false)[1]:match(' tail$') ~= nil"))

  -- A final empty line and a winbar have no visible column-1 character to query.
  lua([[
    _G.diagram:detach()
    vim.cmd('enew!')
    vim.wo.winbar = 'diagram'
    vim.api.nvim_buf_set_lines(0, 0, -1, false, {string.rep(' ', 120), ''})
    _G.diagram = assert(require('draw-line.diagram').attach())
    vim.fn.winrestview({topline = 1, leftcol = 20, lnum = 1, col = 20})
  ]])
  local textrow = lua("local i = vim.fn.getwininfo(vim.api.nvim_get_current_win())[1]; return i.winrow + i.winbar")
  drag(textrow + 1, 2, textrow + 5, 8)
  equal(graph().boxes[1], { id = 1, top = 2, bottom = 6, left = 22, right = 28 })

  -- Buffer-local mappings run in the old buffer even when the click targets a different split.
  lua([[
    _G.diagram:detach()
    vim.wo.winbar = ''
    vim.cmd('enew!')
    vim.api.nvim_buf_set_lines(0, 0, -1, false, vim.fn['repeat']({''}, 30))
    vim.fn.winrestview({topline = 1, leftcol = 0, lnum = 1, col = 0})
    _G.diagram = assert(require('draw-line.diagram').attach())
    _G.diagram_win = vim.api.nvim_get_current_win()
    _G.diagram_buf = vim.api.nvim_get_current_buf()
    vim.cmd('rightbelow vsplit'); vim.cmd('enew!')
    vim.api.nvim_buf_set_lines(0, 0, -1, false, {'日 é', 'target text'})
    vim.fn.winrestview({topline = 1, leftcol = 0, lnum = 1, col = 0})
    _G.other_win = vim.api.nvim_get_current_win()
    _G.other_buf = vim.api.nvim_get_current_buf()
    vim.api.nvim_set_current_win(_G.diagram_win)
  ]])
  local target = lua("return vim.api.nvim_win_get_position(_G.other_win)")
  mouse("press", target[1] + 2, target[2] + 4)
  mouse("release", target[1] + 2, target[2] + 4)
  equal(lua("return vim.api.nvim_get_current_win() == _G.other_win"), true)
  equal(lua("return vim.api.nvim_win_get_cursor(0)"), { 2, 3 })
  equal(lua("return vim.api.nvim_buf_get_lines(0, 0, -1, false)"), { "日 é", "target text" })
  lua("vim.api.nvim_set_current_win(_G.diagram_win)")
  local empty = graph()
  local source = lua("return vim.api.nvim_win_get_position(_G.diagram_win)")
  -- A diagram drag released in another buffer cancels, without synthesizing a native press there.
  drag(source[1] + 3, source[2] + 2, target[1] + 2, target[2] + 4)
  equal(lua("return vim.api.nvim_get_current_win() == _G.diagram_win"), true)
  equal(graph(), empty)
  equal(lua("return _G.diagram.gesture == nil"), true)
  equal(lua("return vim.api.nvim_buf_get_lines(_G.other_buf, 0, -1, false)"), { "日 é", "target text" })
  drag(source[1] + 3, source[2] + 2, source[1] + 7, source[2] + 8)
  equal(vim.tbl_count(graph().boxes), 1)
  local unchanged = graph()
  -- The same diagram shown in another split also receives the native click and release.
  lua("vim.api.nvim_win_set_buf(_G.other_win, _G.diagram_buf)")
  mouse("press", target[1] + 12, target[2] + 12)
  mouse("release", target[1] + 12, target[2] + 12)
  equal(lua("return vim.api.nvim_get_current_win() == _G.other_win"), true)
  equal(graph(), unchanged)
  drag(target[1] + 15, target[2] + 2, target[1] + 19, target[2] + 8)
  equal(vim.tbl_count(graph().boxes), 2)
  -- Real mouse drawing plus a native keyboard label: one counted redo skips
  -- the recorded box-only state, so restore the model from its undo ancestry.
  lua([[
    _G.diagram:detach()
    vim.cmd('only'); vim.cmd('enew!')
    vim.api.nvim_buf_set_lines(0, 0, -1, false, vim.fn['repeat']({''}, 12))
    _G.diagram = assert(require('draw-line.diagram').attach())
  ]])
  drag(2, 2, 6, 10)
  local boxed = graph()
  lua("vim.api.nvim_win_set_cursor(0, {3, 4})")
  input("rX")
  local labeled = lua("return vim.api.nvim_buf_get_lines(0, 0, -1, false)")
  assert(labeled[3]:match("X"))
  input("2u")
  equal(vim.tbl_count(graph().boxes), 0)
  input("2<C-r>")
  equal(lua("return vim.api.nvim_buf_get_lines(0, 0, -1, false)"), labeled)
  equal(graph(), boxed)
  drag(4, 6, 9, 6)
  equal(graph().boxes[1].top, 7)
  equal(lua("return vim.api.nvim_buf_get_lines(0, 2, 3, false)[1]:sub(1, 3)"), "  X")
  print("PASS isolated UI: gestures, cancellation, scrolled EOF, split focus, batched keyboard label undo/redo")
end, debug.traceback)
stop()
if not ok then
  io.stderr:write(message .. "\n")
  vim.cmd("cquit 1")
end
vim.cmd("qa!")
