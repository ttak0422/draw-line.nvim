return function(context)
  local draw, test, fresh, stroke = context.draw, context.test, context.fresh, context.stroke
  local equal, lines, blocked, feed = context.equal, context.lines, context.blocked, context.feed
  local api, fn = vim.api, vim.fn
  local styles = {
    single = { "─", "│", "┌", "┐", "└", "┘", "╶", "╴", "╷", "╵" },
    heavy = { "━", "┃", "┏", "┓", "┗", "┛", "╺", "╸", "╻", "╹" },
    double = { "═", "║", "╔", "╗", "╚", "╝", "╶", "╴", "╷", "╵" },
    rounded = { "─", "│", "╭", "╮", "╰", "╯", "╶", "╴", "╷", "╵" },
    dashed2 = { "╌", "╎", "┌", "┐", "└", "┘", "╶", "╴", "╷", "╵" },
    dashed3 = { "┄", "┆", "┌", "┐", "└", "┘", "╶", "╴", "╷", "╵" },
    dashed4 = { "┈", "┊", "┌", "┐", "└", "┘", "╶", "╴", "╷", "╵" },
    heavy_dashed2 = { "╍", "╏", "┏", "┓", "┗", "┛", "╺", "╸", "╻", "╹" },
    heavy_dashed3 = { "┅", "┇", "┏", "┓", "┗", "┛", "╺", "╸", "╻", "╹" },
    heavy_dashed4 = { "┉", "┋", "┏", "┓", "┗", "┛", "╺", "╸", "╻", "╹" },
  }
  local moves = {
    h = { 0, -1, "◀", "k", 5 },
    j = { 1, 0, "▼", "h", 6 },
    k = { -1, 0, "▲", "l", 3 },
    l = { 0, 1, "▶", "j", 4 },
  }
  local function at(row, col)
    api.nvim_win_set_cursor(0, { row, fn.virtcol2col(0, row, col) - 1 })
  end
  local function cell(row, col)
    return fn.strcharpart(lines()[row], col - 1, 1)
  end
  local function blank()
    fresh({
      "         ",
      "         ",
      "         ",
      "         ",
      "         ",
      "         ",
      "         ",
      "         ",
      "         ",
    })
  end

  test("automatic arrows move and turn in every style and direction", function()
    for style, glyphs in pairs(styles) do
      for key, move in pairs(moves) do
        blank()
        at(5, 5)
        for step = 1, 3 do
          equal(draw.draw(key, style), true)
          equal(cell(5 + move[1] * step, 5 + move[2] * step), move[3])
          equal({ fn.line("."), fn.virtcol(".") }, { 5 + move[1] * step, 5 + move[2] * step })
          equal(cell(5, 5), glyphs[move[1] == 0 and 1 or 2])
          if step > 1 then
            equal(cell(5 + move[1] * (step - 1), 5 + move[2] * (step - 1)), glyphs[move[1] == 0 and 1 or 2])
          end
        end
        local row, col = fn.line("."), fn.virtcol(".")
        local turn = moves[move[4]]
        equal(draw.draw(move[4], style), true)
        equal(cell(row, col), glyphs[move[5]])
        equal(cell(row + turn[1], col + turn[2]), turn[3])
      end
    end
  end)

  test("new starts use full style glyphs on empty lines in all four directions", function()
    for style, glyphs in pairs(styles) do
      for key, move in pairs(moves) do
        fresh({ "", "", "", "", "", "", "", "", "" })
        vim.wo.virtualedit = "all"
        fn.setpos(".", { 0, 5, 1, 4 })
        equal(draw.draw(key, style), true)
        equal(cell(5, 5), glyphs[move[1] == 0 and 1 or 2])
        equal(cell(5 + move[1], 5 + move[2]), move[3])
      end
    end
  end)

  test("full starts survive reload and redraw and turn without false branches", function()
    for style, glyphs in pairs(styles) do
      fresh()
      equal(stroke("l", 3, style), true)
      local saved = lines()
      fresh(saved)
      local before = { fn.undotree(), api.nvim_buf_get_changedtick(0) }
      equal(stroke("l", 3, style), true)
      equal(lines(), saved)
      equal({ fn.undotree(), api.nvim_buf_get_changedtick(0) }, before)
      at(1, 1)
      equal(draw.draw("j", style), true)
      equal(lines(), { glyphs[3] .. glyphs[1]:rep(2) .. "▶", "▼" })
      fresh()
      for key in ("lljjhhkk"):gmatch(".") do
        equal(draw.draw(key, style), true)
      end
      equal(
        lines(),
        { glyphs[3] .. glyphs[1] .. glyphs[4], glyphs[2] .. " " .. glyphs[2], glyphs[5] .. glyphs[1] .. glyphs[6] }
      )
    end
    fresh()
    equal(draw.draw("l", "double"), true)
    equal(draw.draw("j", "single"), true)
    equal(lines(), { "═╕", " ▼" })
    fresh({ "═▶" })
    at(1, 2)
    blocked(function()
      return draw.draw("j", "heavy")
    end)
  end)

  test("existing half endpoints and untouched diagrams are not converted", function()
    fresh({ "╶╴  ", "    ", "╺╸  " })
    at(2, 1)
    equal(draw.draw("l", "double"), true)
    equal(lines(), { "╶╴  ", "═▶  ", "╺╸  " })
    for _, sample in ipairs({
      { "╶╴", "single", "╶▶" },
      { "╺╸", "heavy", "╺▶" },
      { "╶═╴", "double", "╶═╴" },
    }) do
      fresh({ sample[1] })
      equal(draw.draw("l", sample[2]), true)
      equal(lines(), { sample[3] })
    end
    fresh()
    equal(draw.box({ 1, 1 }, { 1, 3 }, "double"), true)
    equal(lines(), { "╶═╴" })
    fresh({ "│─▶" })
    at(1, 2)
    equal(draw.draw("j"), true)
    equal(lines(), { "│┌▶", " ▼" })
    fresh({ "──▶" })
    at(1, 2)
    equal(draw.draw("j"), true)
    equal(lines(), { "─┬▶", " ▼" })
  end)

  test("retracing hides the arrow on existing linework and restores it at the free end", function()
    for style, glyphs in pairs(styles) do
      fresh()
      equal(stroke("l", 3, style), true)
      equal(lines(), { glyphs[1]:rep(3) .. "▶" })
      equal(draw.draw("h", style), true)
      equal(lines(), { glyphs[1]:rep(3) .. glyphs[8] })
      equal(stroke("h", 2, style), true)
      equal(lines(), { "◀" .. glyphs[1]:rep(2) .. glyphs[8] })
    end
    fresh()
    equal(draw.draw("l", "double"), true)
    equal(draw.draw("h", "double"), true)
    equal(lines(), { "◀╴" })
  end)

  test("arriving at box edges joins all four directions without arrowheads", function()
    for style in pairs(styles) do
      local heavy = style == "heavy" or style:match("^heavy_")
      local joints = style == "double" and { "╠", "╣", "╦", "╩" }
        or heavy and { "┣", "┫", "┳", "┻" }
        or { "├", "┤", "┬", "┴" }
      for _, sample in ipairs({
        { "l", 5, 1, 3, 5, 4, joints[2] },
        { "h", 5, 9, 2, 5, 7, joints[1] },
        { "j", 1, 5, 2, 3, 5, joints[4] },
        { "k", 9, 5, 2, 7, 5, joints[3] },
      }) do
        blank()
        equal(draw.box({ 3, 4 }, { 7, 7 }, style), true)
        at(sample[2], sample[3])
        equal(stroke(sample[1], sample[4] - 1, style), true)
        equal(cell(fn.line("."), fn.virtcol(".")), moves[sample[1]][3])
        equal(draw.draw(sample[1], style), true)
        equal(cell(sample[5], sample[6]), sample[7])
      end
    end
    fresh({ "   ╔══╗", "   ║  ║", "   ╚══╝" })
    at(2, 1)
    equal(stroke("l", 3), true)
    equal(lines(), { "   ╔══╗", "───╢  ║", "   ╚══╝" })
  end)

  test("proximity alone does not connect a tip or suppress its arrow", function()
    fresh({ "   │" })
    equal(stroke("l", 2), true)
    equal(lines(), { "──▶│" })
    equal(draw.draw("l"), true)
    equal(lines(), { "───┤" })
    fresh({ " │ ", "   " })
    at(2, 1)
    equal(draw.draw("l"), true)
    equal(lines(), { " │ ", "─▶ " })
    fresh({ "╶◀" })
    at(1, 2)
    blocked(function()
      return draw.draw("j")
    end)
  end)

  test("connecting to arrows merges their visible directions and weights", function()
    for _, sample in ipairs({
      { { "╶▶◀╴" }, 1, 2, "l", "single", { "╶──╴" } },
      { { " ╷", "╶▶" }, 1, 2, "j", "single", { " ╷", "╶┘" } },
      { { " ╷", "◀╴" }, 1, 2, "j", "single", { " ╷", "◀┘" } },
      { { "╶┅▶" }, 1, 3, "j", "single", { "╶┅┑", "  ▼" } },
      { { "╶═▶" }, 1, 3, "j", "single", { "╶═╕", "  ▼" } },
      { { "╶─▶" }, 1, 3, "j", "rounded", { "╶─╮", "  ▼" } },
      { { "╶▶", " ╵" }, 2, 2, "k", "heavy", { "╶┒", " ╹" } },
      { { "◀▶" }, 1, 2, "j", "double", { "◀╗", " ▼" } },
    }) do
      fresh(sample[1])
      at(sample[2], sample[3])
      equal(draw.draw(sample[4], sample[5]), true)
      equal(lines(), sample[6])
    end
    fresh({ "     ", "╶──▶ ", "     " })
    equal(draw.box({ 1, 4 }, { 3, 4 }), true)
    equal(lines(), { "   ╷ ", "╶──┤ ", "   ╵ " })
  end)

  test("automatic arrows preserve atomic failures and display width guards", function()
    for _, sample in ipairs({
      { { "╶═▶" }, 1, 3, "j", "heavy" },
      { { "╶━▶" }, 1, 3, "j", "double" },
      { { "╶═▶" }, 1, 3, "l", "single" },
      { { "╶▶║" }, 1, 2, "l", "heavy" },
      { { "╶▶X" }, 1, 2, "l", "single" },
      { { "╶▶日" }, 1, 2, "l", "single" },
      { { "▶" }, 1, 1, "j", "single" },
    }) do
      fresh(sample[1])
      at(sample[2], sample[3])
      blocked(function()
        return draw.draw(sample[4], sample[5])
      end)
    end
    for _, line in ipairs({ "", "  " }) do
      fresh({ line })
      fn.setcellwidths({ { 0x25B6, 0x25B6, 2 } })
      blocked(function()
        return draw.draw("l")
      end)
      fn.setcellwidths({})
    end
  end)

  test("arrows, bends and box connections share each step's undo block", function()
    equal(draw.box({ 1, 4 }, { 3, 6 }), true)
    at(2, 1)
    local states = {
      { "   ┌─┐", "─▶ │ │", "   └─┘" },
      { "   ┌─┐", "──▶│ │", "   └─┘" },
      { "   ┌─┐", "───┤ │", "   └─┘" },
    }
    for _, expected in ipairs(states) do
      equal(draw.draw("l"), true)
      equal(lines(), expected)
    end
    feed("u")
    equal(lines(), states[2])
    feed("u")
    equal(lines(), states[1])
    feed("<C-r><C-r>")
    equal(lines(), states[3])
    fresh()
    equal(stroke("l", 3, "rounded"), true)
    equal(stroke("j", 2, "rounded"), true)
    equal(lines(), { "───╮", "   │", "   ▼" })
    feed("u")
    equal(lines(), { "───╮", "   ▼" })
    feed("u")
    equal(lines(), { "───▶" })
    feed("<C-r><C-r>")
    equal(lines(), { "───╮", "   │", "   ▼" })
    fresh({ "日\t" })
    vim.wo.virtualedit = "all"
    fn.setpos(".", { 0, 1, #lines()[1] + 1, 0 })
    equal(stroke("l", 3), true)
    equal(lines(), { "日\t───▶" })
  end)
end
