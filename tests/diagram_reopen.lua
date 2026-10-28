local fn, api = vim.fn, vim.api
local root = fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.runtimepath:prepend(root)
local stage, path = vim.env.DRAW_LINE_REOPEN_STAGE, vim.env.DRAW_LINE_REOPEN_FILE
if stage then
  local diagram = require("draw-line.diagram")
  local model = require("draw-line.diagram.model")
  vim.wo.wrap = false
  vim.cmd("edit " .. fn.fnameescape(path))
  local session
  if stage == "create" then
    api.nvim_buf_set_lines(0, 0, -1, false, { "日本 é\tkeep", "", "", "", "", "", "", "", "", "", "" })
    session = assert(diagram.attach())
    assert(session:box({ 3, 2 }, { 9, 14 }) == 1)
    assert(session:box({ 5, 8 }, { 11, 20 }) == 2)
    assert(session:box({ 3, 30 }, { 9, 40 }) == 3)
    assert(session:connect(1, 3) == 4)
    assert(session:raise(2))
  else
    session = assert(diagram.load())
    local graph = assert(session:inspect())
    assert(vim.deep_equal(graph.z_order, { 1, 3, 4, 2 }))
    assert(vim.tbl_count(graph.boxes) == 3 and graph.edges[4].source == 1 and graph.edges[4].target == 3)
    assert(model.render(graph)["7:14"].owner == 2)
    local original = api.nvim_buf_get_lines(0, 0, -1, false)
    assert(session:move(2, { 15, 25 }))
    assert(model.render(session:inspect())["7:14"].owner == 1)
    assert(session:move(2, { 8, 14 }))
    assert(vim.deep_equal(api.nvim_buf_get_lines(0, 0, -1, false), original))
    vim.cmd.undo()
    assert(session:inspect().boxes[2].top == 12)
    vim.cmd.redo()
    assert(session:inspect().boxes[2].top == 5)
    assert(api.nvim_buf_get_lines(0, 0, 1, false)[1] == "日本 é\tkeep")
  end
  vim.cmd("silent write")
  assert(session:save())
  vim.cmd("qa!")
  return
end

local directory = fn.tempname()
fn.mkdir(directory, "p")
path = directory .. "/diagram.txt"
local before_stage, before_file = vim.env.DRAW_LINE_REOPEN_STAGE, vim.env.DRAW_LINE_REOPEN_FILE
vim.env.DRAW_LINE_REOPEN_FILE = path
for _, mode in ipairs({ "create", "reopen", "reopen" }) do
  vim.env.DRAW_LINE_REOPEN_STAGE = mode
  local output = fn.system({
    vim.v.progpath,
    "--headless",
    "-n",
    "-u",
    "NONE",
    "-i",
    "NONE",
    "-l",
    root .. "/tests/diagram_reopen.lua",
  })
  if vim.v.shell_error ~= 0 then
    io.stderr:write("FAIL fresh-process " .. mode .. ": " .. output .. "\nFixture: " .. directory .. "\n")
    vim.cmd("cquit 1")
  end
end
vim.env.DRAW_LINE_REOPEN_STAGE, vim.env.DRAW_LINE_REOPEN_FILE = before_stage, before_file
fn.delete(directory, "rf")
print("PASS fresh-process save/reopen: full hidden geometry, IDs, anchors, stacking, text and native undo/redo")
vim.cmd("qa!")
