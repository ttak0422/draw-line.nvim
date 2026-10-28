local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.runtimepath:prepend(root)
vim.o.swapfile = false
vim.o.hidden = true
local draw = require("draw-line")
local api, fn = vim.api, vim.fn
local passed = 0

local function stroke(direction, steps, style)
  for _ = 1, steps do
    local ok, message = draw.draw(direction, style)
    if not ok then
      return nil, message
    end
  end
  return true
end

local function equal(actual, expected)
  assert(vim.deep_equal(actual, expected), "expected " .. vim.inspect(expected) .. ", got " .. vim.inspect(actual))
end

local function feed(keys)
  api.nvim_feedkeys(api.nvim_replace_termcodes(keys, true, false, true), "xt", false)
end

local function lines()
  return api.nvim_buf_get_lines(0, 0, -1, false)
end

local function fresh(content)
  feed("<Esc>")
  vim.cmd("enew!")
  vim.bo.modifiable, vim.bo.readonly = true, false
  vim.bo.undolevels = -1
  api.nvim_buf_set_lines(0, 0, -1, false, content or { "" })
  vim.bo.undolevels = 1000
  vim.wo.virtualedit = ""
  vim.bo.tabstop, vim.bo.vartabstop = 8, ""
  vim.o.ambiwidth, vim.o.selection = "single", "inclusive"
  api.nvim_win_set_cursor(0, { 1, 0 })
end

local function snapshot()
  return { lines(), fn.getcurpos(), fn.undotree(), api.nvim_buf_get_changedtick(0) }
end

local function blocked(callback)
  local before = snapshot()
  local ok, message = callback()
  equal(ok, nil)
  assert(type(message) == "string" and message:match("draw%-line:"), vim.inspect(message))
  equal(snapshot(), before)
  return message
end

local function invalid(callback)
  local before = snapshot()
  local ok, message = pcall(callback)
  equal(ok, false)
  assert(tostring(message):match("draw%-line:"), tostring(message))
  equal(snapshot(), before)
  return tostring(message)
end

local function test(name, callback)
  fresh()
  local ok, message = xpcall(callback, debug.traceback)
  if not ok then
    io.stderr:write("FAIL " .. name .. "\n" .. message .. "\n")
    vim.cmd("cquit 1")
  end
  passed = passed + 1
  print("PASS " .. name)
end

test("built-in styles are stateless and need no setup API", function()
  equal(draw.setup, nil)
  equal(draw.set_style, nil)
  equal(draw.get_style, nil)
  equal(draw.arrow, nil)
  equal(draw.box({ 1, 1 }, { 3, 4 }, "rounded"), true)
  equal(lines(), { "╭──╮", "│  │", "╰──╯" })
  fresh()
  equal(draw.draw("l", "heavy"), true)
  equal(draw.draw("j"), true)
  equal(lines(), { "━┑", " ▼" })
  fresh()
  equal(draw.draw("l", "dashed3"), true)
  equal(draw.draw("l", "dashed3"), true)
  equal(lines(), { "┄┄▶" })
end)

test("draw accepts only direction and style and always takes one step", function()
  for _, name in ipairs({ false, 1, {}, "missing", "bad name", "dashed5" }) do
    invalid(function()
      draw.draw("l", name)
    end)
    invalid(function()
      draw.box({ 1, 1 }, { 2, 2 }, name)
    end)
    invalid(function()
      draw.box_visual(name)
    end)
  end
  for _, extra in ipairs({ false, 2, {}, { count = 3 }, { arrow = true } }) do
    invalid(function()
      draw.draw("l", "single", extra)
    end)
    invalid(function()
      draw.box({ 1, 1 }, { 2, 2 }, "single", extra)
    end)
    invalid(function()
      draw.box_visual("single", extra)
    end)
  end
  equal(stroke("l", 3, "heavy"), true)
  equal(lines(), { "━━━▶" })
  fresh()
  vim.keymap.set("n", "Q", function()
    assert(draw.draw("l", "dashed3"))
  end, { buffer = true })
  feed("5Q")
  equal(lines(), { "┄▶" })
end)

test("strokes turn into corners and close a rectangle", function()
  equal(draw.draw("l"), true)
  equal(draw.draw("l"), true)
  equal(draw.draw("j"), true)
  equal(lines(), { "──┐", "  ▼" })
  equal(api.nvim_win_get_cursor(0), { 2, 2 })
  stroke("h", 2, nil)
  draw.draw("k")
  equal(lines(), { "┌─┐", "└─┘" })
  equal(api.nvim_win_get_cursor(0), { 1, 0 })
end)

test("crossings and tees preserve connectivity across styles", function()
  fresh({ "", "" })
  api.nvim_win_set_cursor(0, { 2, 0 })
  stroke("l", 4, nil)
  vim.wo.virtualedit = "all"
  fn.setpos(".", { 0, 1, 1, 2 })
  equal(stroke("j", 2, "heavy"), true)
  equal(lines(), { "  ┃", "──╂─▶", "  ▼" })
  api.nvim_win_set_cursor(0, { 3, 2 })
  blocked(function()
    return draw.draw("l", "double")
  end)
  draw.box({ 1, 1 }, { 2, 1 }, "double")
  equal(lines()[2], "╙─╂─▶")
end)

test("box normalizes endpoints and preserves interior and cursor", function()
  fresh({ "      tail", " abc  tail", "      tail" })
  api.nvim_win_set_cursor(0, { 2, 2 })
  local before = fn.virtcol(".")
  equal(draw.box({ 3, 5 }, { 1, 1 }, "heavy"), true)
  equal(lines(), { "┏━━━┓ tail", "┃abc┃ tail", "┗━━━┛ tail" })
  equal(fn.virtcol("."), before)
  equal(api.nvim_win_get_cursor(0), { 2, 4 })
end)

test("degenerate boxes and gaps before appended rows", function()
  draw.box({ 1, 4 }, { 1, 1 })
  equal(lines(), { "╶──╴" })
  draw.box({ 4, 6 }, { 2, 6 })
  equal(lines(), { "╶──╴", "     ╷", "     │", "     ╵" })
  draw.box({ 6, 2 }, { 6, 2 }, "double")
  equal(lines()[5], "")
  equal(lines()[6], " ╬")
end)

test("Japanese, tabs, composing clusters, and emoji remain byte-identical", function()
  for _, sample in ipairs({
    { "日本   ", 5, "日本╶─╴" },
    { "\t   ", 9, "\t╶─╴" },
    { "é   ", 2, "é╶─╴" },
    { "👩‍💻   ", fn.strdisplaywidth("👩‍💻") + 1, "👩‍💻╶─╴" },
  }) do
    fresh({ sample[1] })
    equal(draw.box({ 1, sample[2] }, { 1, sample[2] + 2 }), true)
    equal(lines()[1], sample[3])
  end
  fresh({ " \t   " })
  vim.bo.vartabstop = "3,5"
  draw.box({ 1, 4 }, { 1, 6 })
  equal(lines(), { " \t╶─╴" })
  fresh({ "日本  " })
  api.nvim_win_set_cursor(0, { 1, 6 })
  draw.draw("l")
  equal(api.nvim_win_get_cursor(0), { 1, 9 })
end)

test("overlapping any cell of protected text rejects atomically", function()
  for _, text in ipairs({ "日", "\t", "é", "👩‍💻", "│́", "x" }) do
    fresh({ " " .. text .. " " })
    for col = 2, 1 + fn.strdisplaywidth(text, 1) do
      blocked(function()
        return draw.box({ 1, col }, { 1, col })
      end)
    end
  end
end)

test("past EOL and EOF drawing with no option changes", function()
  vim.wo.virtualedit = "all"
  fn.setpos(".", { 0, 1, 1, 4 })
  stroke("j", 2, nil)
  equal(lines(), { "    │", "    │", "    ▼" })
  equal(api.nvim_win_get_cursor(0), { 3, 4 })
  equal(vim.wo.virtualedit, "all")
  fn.setpos(".", { 0, 1, #lines()[1] + 1, 3 })
  local col = fn.virtcol(".")
  draw.box({ 1, 1 }, { 1, 2 })
  equal(fn.virtcol("."), col)
  equal(fn.getcurpos()[4], 3)
end)

test("top, left, readonly, nomodifiable, and display width guards", function()
  blocked(function()
    return draw.draw("h")
  end)
  blocked(function()
    return draw.draw("k")
  end)
  vim.bo.readonly = true
  blocked(function()
    return draw.draw("l")
  end)
  vim.bo.readonly, vim.bo.modifiable = false, false
  blocked(function()
    return draw.box({ 1, 1 }, { 2, 2 })
  end)
  vim.bo.modifiable = true
  vim.o.ambiwidth = "double"
  blocked(function()
    return draw.draw("l")
  end)
end)

test("late collisions and malformed arguments do not edit or move", function()
  fresh({ "         x", "", "      X" })
  blocked(function()
    return draw.box({ 1, 1 }, { 1, 10 })
  end)
  blocked(function()
    return draw.box({ 1, 1 }, { 3, 7 })
  end)
  for _, direction in ipairs({ "up", "", false, 1 }) do
    invalid(function()
      draw.draw(direction)
    end)
  end
  for _, point in ipairs({ { 0, 1 }, { 1, 0 }, { 1.5, 1 }, { 1, 1000001 }, { 1 }, { 1, 1, 1 }, "bad" }) do
    invalid(function()
      draw.box(point, { 1, 1 })
    end)
  end
  invalid(function()
    draw.box({ 1, 1 }, { 6000, 6000 })
  end)
  blocked(function()
    return draw.box({ 20000, 1 }, { 20001, 2 })
  end)
end)

test("multirow undo and redo, with earlier changes separated", function()
  feed("iabc<Esc>")
  draw.box({ 2, 1 }, { 4, 4 })
  local expected = lines()
  vim.cmd("undo")
  equal(lines(), { "abc" })
  vim.cmd("redo")
  equal(lines(), expected)
  vim.cmd("undo")
  vim.cmd("undo")
  equal(lines(), { "" })
end)

test("repeated Lua mappings keep each drawing step separately undoable", function()
  for key, direction in pairs({ H = "h", J = "j", K = "k", L = "l" }) do
    vim.keymap.set("n", key, function()
      assert(draw.draw(direction))
    end, { buffer = true })
  end
  feed("LLJ")
  equal(lines(), { "──┐", "  ▼" })
  feed("u")
  equal(lines(), { "──▶" })
  feed("u")
  equal(lines(), { "─▶" })
  feed("u")
  equal(lines(), { "" })
  feed("<C-r><C-r>")
  equal(lines(), { "──▶" })
  feed("J")
  equal(lines(), { "─┬▶", " ▼" })
end)

test("direct calls form separate undo blocks and preserve option values", function()
  vim.go.undolevels, vim.bo.undolevels = 432, 765
  draw.draw("l")
  draw.draw("j")
  vim.cmd("undo")
  equal(lines(), { "─▶" })
  vim.cmd("undo")
  equal(lines(), { "" })
  equal(vim.go.undolevels, 432)
  equal(vim.bo.undolevels, 765)
end)

test("live Visual Block mappings in all ten styles and reversed selections", function()
  local expected = {
    single = { "┌──┐", "│  │", "└──┘" },
    heavy = { "┏━━┓", "┃  ┃", "┗━━┛" },
    double = { "╔══╗", "║  ║", "╚══╝" },
    rounded = { "╭──╮", "│  │", "╰──╯" },
    dashed2 = { "┌╌╌┐", "╎  ╎", "└╌╌┘" },
    dashed3 = { "┌┄┄┐", "┆  ┆", "└┄┄┘" },
    dashed4 = { "┌┈┈┐", "┊  ┊", "└┈┈┘" },
    heavy_dashed2 = { "┏╍╍┓", "╏  ╏", "┗╍╍┛" },
    heavy_dashed3 = { "┏┅┅┓", "┇  ┇", "┗┅┅┛" },
    heavy_dashed4 = { "┏┉┉┓", "┋  ┋", "┗┉┉┛" },
  }
  for style, box in pairs(expected) do
    for _, reversed in ipairs({ false, true }) do
      fresh({ "    ", "    ", "    " })
      vim.keymap.set("x", "Q", function()
        assert(draw.box_visual(style))
      end, { buffer = true })
      feed(reversed and "2j3l<C-v>2k3hQ" or "<C-v>2j3lQ")
      equal(lines(), box)
      equal(fn.mode(), "n")
      equal(api.nvim_win_get_cursor(0), { 1, 0 })
    end
  end
end)

test("virtual block endpoints work, stale marks and other modes reject", function()
  fresh({ "", "", "" })
  vim.wo.virtualedit = "all"
  vim.keymap.set("x", "Q", function()
    assert(draw.box_visual())
  end, { buffer = true })
  feed("2l<C-v>2j3lQ")
  equal(lines(), { "  ┌──┐", "  │  │", "  └──┘" })
  equal(api.nvim_win_get_cursor(0), { 1, 2 })
  blocked(function()
    return draw.box_visual()
  end)
  feed("v")
  blocked(function()
    return draw.box_visual()
  end)
  feed("<Esc>V")
  blocked(function()
    return draw.box_visual()
  end)
  feed("<Esc><C-v>")
  vim.o.selection = "exclusive"
  blocked(function()
    return draw.box_visual()
  end)
  feed("<Esc>")
end)

local context = {
  root = root,
  draw = draw,
  test = test,
  fresh = fresh,
  stroke = stroke,
  equal = equal,
  lines = lines,
  blocked = blocked,
  invalid = invalid,
  feed = feed,
}
dofile(root .. "/tests/mixed.lua")(context)
dofile(root .. "/tests/glyphs.lua")(context)
dofile(root .. "/tests/arrows.lua")(context)
dofile(root .. "/tests/diagram.lua")(context)
dofile(root .. "/tests/diagram_documents.lua")(context)

test("normal mappings connect to mixed-weight boxes and undo each step", function()
  fresh({ "   ╔═╗", "   ║ ║", "   ╚═╝" })
  api.nvim_win_set_cursor(0, { 2, 0 })
  vim.keymap.set("n", "L", function()
    assert(draw.draw("l"))
  end, { buffer = true })
  feed("LL")
  equal(lines(), { "   ╔═╗", "──▶║ ║", "   ╚═╝" })
  feed("L")
  equal(lines(), { "   ╔═╗", "───╢ ║", "   ╚═╝" })
  feed("u")
  equal(lines(), { "   ╔═╗", "──▶║ ║", "   ╚═╝" })
  feed("<C-r>")
  equal(lines(), { "   ╔═╗", "───╢ ║", "   ╚═╝" })
end)

vim.cmd("helptags " .. fn.fnameescape(root .. "/doc"))
print(string.format("%d tests passed on Neovim %s", passed, tostring(vim.version())))
vim.cmd("qa!")
