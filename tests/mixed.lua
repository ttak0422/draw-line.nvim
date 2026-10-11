return function(context)
  local draw, test, fresh, stroke = context.draw, context.test, context.fresh, context.stroke
  local equal, lines, blocked = context.equal, context.lines, context.blocked
  local api, fn = vim.api, vim.fn

  local function at(row, col)
    vim.wo.virtualedit = "all"
    local line = api.nvim_buf_get_lines(0, row - 1, row, false)[1]
    local byte = col > fn.strdisplaywidth(line) and #line + 1 or fn.virtcol2col(0, row, col)
    fn.setpos(".", { 0, row, byte, col - fn.strdisplaywidth(line:sub(1, byte - 1)) - 1 })
  end

  test("single and double branches preserve each untouched direction", function()
    for _, sample in ipairs({
      { "║", "single", "l", " ╟▶" },
      { "║", "single", "h", "◀╢" },
      { "│", "double", "l", " ╞▶" },
      { "│", "double", "h", "◀╡" },
      { "║", "double", "l", " ╠▶" },
      { "║", "double", "h", "◀╣" },
    }) do
      fresh({ " " .. sample[1] })
      at(1, 2)
      equal(draw.draw(sample[3], sample[2]), true)
      equal(lines(), { sample[4] })
    end
  end)

  test("crossings are independent of drawing order across built-in styles", function()
    for _, sample in ipairs({
      { "single", "double", "╪" },
      { "double", "single", "╫" },
      { "single", "heavy", "┿" },
      { "heavy", "single", "╂" },
      { "rounded", "heavy_dashed3", "┿" },
      { "heavy_dashed4", "dashed2", "╂" },
      { "double", "dashed4", "╫" },
      { "dashed3", "double", "╪" },
    }) do
      for _, horizontal_first in ipairs({ true, false }) do
        fresh({ "", "", "" })
        local function vertical()
          equal(draw.box({ 1, 3 }, { 3, 3 }, sample[1]), true)
        end
        local function horizontal()
          equal(draw.box({ 2, 1 }, { 2, 5 }, sample[2]), true)
        end
        if horizontal_first then
          horizontal()
          vertical()
        else
          vertical()
          horizontal()
        end
        equal(fn.strcharpart(lines()[2], 2, 1), sample[3])
      end
    end
  end)

  test("all single-double corners and mixed glyphs can be resumed", function()
    for _, sample in ipairs({
      { "╷", "l", "double", "╒" },
      { "╷", "h", "double", "╕" },
      { "╵", "l", "double", "╘" },
      { "╵", "h", "double", "╛" },
      { "╶", "j", "double", "╓" },
      { "╴", "j", "double", "╖" },
      { "╶", "k", "double", "╙" },
      { "╴", "k", "double", "╜" },
    }) do
      fresh({ "", " " .. sample[1], "" })
      at(2, 2)
      equal(draw.draw(sample[2], sample[3]), true)
      equal(fn.strcharpart(lines()[2], 1, 1), sample[4])
    end
    for _, sample in ipairs({
      { "╟", "h", "single", "╫" },
      { "╢", "l", "single", "╫" },
      { "╞", "h", "double", "╪" },
      { "╡", "l", "double", "╪" },
      { "╫", "l", "single", "╫" },
      { "╪", "l", "double", "╪" },
      { "╒", "k", "single", "╞" },
      { "╓", "k", "double", "╟" },
      { "╟", "j", "double", "╟" },
      { "╞", "j", "single", "╞" },
    }) do
      fresh({ "", " " .. sample[1], "" })
      at(2, 2)
      equal(draw.draw(sample[2], sample[3]), true)
      equal(fn.strcharpart(lines()[2], 1, 1), sample[4])
    end
  end)

  test("all three weights support stepwise rectangles and double endpoint recovery", function()
    for style, expected in pairs({
      single = { "┌─┐", "│ │", "└─┘" },
      heavy = { "┏━┓", "┃ ┃", "┗━┛" },
      double = { "╔═╗", "║ ║", "╚═╝" },
    }) do
      fresh()
      for direction in ("lljjhhkk"):gmatch(".") do
        equal(draw.draw(direction, style), true)
      end
      equal(lines(), expected)
    end
    fresh()
    draw.draw("l", "double")
    draw.draw("j", "double")
    equal(lines(), { "═╗", " ▼" })
    vim.cmd("undo")
    equal(lines(), { "═▶" })
    vim.cmd("redo")
    at(2, 2)
    draw.draw("h", "double")
    draw.draw("k", "double")
    equal(lines(), { "╔╗", "╚╝" })
    fresh({ "╶═╴" })
    at(1, 3)
    draw.draw("j")
    equal(lines(), { "╶═╕", "  ▼" })
    fresh({ "╶╴" })
    at(1, 2)
    draw.draw("j")
    equal(lines(), { "╶┐", " ▼" })
  end)

  test("light-heavy branches, transitions, and asymmetric junctions preserve weights", function()
    for _, sample in ipairs({
      { "│", "heavy", "l", "┝" },
      { "┃", "single", "l", "┠" },
      { "─", "heavy", "l", "╼" },
      { "─", "heavy", "h", "╾" },
      { "│", "heavy", "j", "╽" },
      { "│", "heavy", "k", "╿" },
      { "┝", "heavy", "k", "┡" },
      { "┠", "single", "k", "┟" },
      { "┿", "heavy", "k", "╇" },
      { "╂", "heavy", "h", "╉" },
    }) do
      fresh({ "", " " .. sample[1], "" })
      at(2, 2)
      equal(draw.draw(sample[3], sample[2]), true)
      equal(fn.strcharpart(lines()[2], 1, 1), sample[4])
    end
  end)

  test("short light endpoints use only visible context and the selected style", function()
    for _, sample in ipairs({
      { "╶╴", "double", "╶╗" },
      { "╶╴", "single", "╶┐" },
      { "╶═╴", "single", "╶═╕" },
      { " ╴", "double", " ╖" },
    }) do
      fresh({ sample[1] })
      at(1, fn.strdisplaywidth(sample[1]))
      equal(draw.draw("j", sample[2]), true)
      equal(lines()[1], sample[3])
    end
  end)

  test("box overrides, partial redraw, full redraw, and reload preserve weights", function()
    draw.box({ 1, 1 }, { 3, 5 }, "double")
    at(2, 5)
    stroke("l", 2, nil)
    equal(lines(), { "╔═══╗", "║   ╟─▶", "╚═══╝" })

    local saved = lines()
    vim.cmd("undo")
    equal(lines(), { "╔═══╗", "║   ╟▶", "╚═══╝" })
    vim.cmd("undo")
    equal(lines(), { "╔═══╗", "║   ║", "╚═══╝" })
    vim.cmd("redo")
    vim.cmd("redo")
    equal(lines(), saved)
    fresh(saved)
    at(2, 5)
    stroke("l", 2, nil)
    equal(lines(), saved)
    fresh({ " ╬" })
    draw.box({ 1, 1 }, { 1, 3 }, "single")
    equal(lines(), { "╶╫╴" })
    draw.box({ 1, 2 }, { 1, 2 }, "heavy")
    equal(lines(), { "╶╋╴" })
  end)

  test("unrepresentable transitions fail atomically, including late cells", function()
    for _, sample in ipairs({
      { "║", "heavy", "l" },
      { "┃", "double", "l" },
      { "─", "double", "l" },
      { "═", "single", "l" },
      { "╫", "single", "j" },
    }) do
      fresh({ sample[1] })
      local message = blocked(function()
        return draw.draw(sample[3], sample[2])
      end)
      assert(message:match("no Unicode glyph") and message:match("row 1, display column 1"), message)
    end
    fresh({ "    ║" })
    local message = blocked(function()
      return draw.box({ 1, 1 }, { 1, 6 }, "heavy")
    end)
    assert(message:match("no Unicode glyph") and message:match("row 1, display column 5"), message)
  end)

  test("six dashed built-ins keep their straights and use solid junctions", function()
    for _, sample in ipairs({
      { "dashed2", "╌", "╎", false },
      { "dashed3", "┄", "┆", false },
      { "dashed4", "┈", "┊", false },
      { "heavy_dashed2", "╍", "╏", true },
      { "heavy_dashed3", "┅", "┇", true },
      { "heavy_dashed4", "┉", "┋", true },
    }) do
      local name, horizontal, vertical, heavy = unpack(sample)
      fresh()
      equal(draw.box({ 1, 1 }, { 3, 4 }, name), true)

      equal(lines(), {
        (heavy and "┏" or "┌") .. horizontal:rep(2) .. (heavy and "┓" or "┐"),
        vertical .. "  " .. vertical,
        (heavy and "┗" or "└") .. horizontal:rep(2) .. (heavy and "┛" or "┘"),
      })

      at(2, 4)
      equal(stroke("l", 2, name), true)
      equal(lines()[2], vertical .. "  " .. (heavy and "┣" or "├") .. horizontal .. "▶")
      at(2, 4)
      equal(stroke("l", 2, nil), true)
      equal(lines()[2], vertical .. "  " .. (heavy and "┠" or "├") .. "─▶")
      fresh()
      equal(draw.box({ 1, 3 }, { 5, 3 }, name), true)
      equal(draw.box({ 3, 1 }, { 3, 5 }, name), true)
      equal(
        lines()[3],
        (heavy and "╺" or "╶")
          .. horizontal
          .. (heavy and "╋" or "┼")
          .. horizontal
          .. (heavy and "╸" or "╴")
      )
      fresh({ heavy and "║" or "═" })
      local message = blocked(function()
        return draw.draw("l", name)
      end)
      assert(message:match("no Unicode glyph"), message)
    end
  end)

  test("rounded built-in keeps corners and canonical mixed junctions", function()
    for _, step in ipairs({ { "l", 3 }, { "j", 2 }, { "h", 3 }, { "k", 2 } }) do
      equal(stroke(step[1], step[2], "rounded"), true)
    end
    equal(lines(), { "╭──╮", "│  │", "╰──╯" })
    fresh({ "║" })
    equal(stroke("l", 2, "rounded"), true)
    equal(lines(), { "╟─▶" })
    equal(draw.draw("j", "rounded"), true)
    equal(lines(), { "╟─╮", "  ▼" })
  end)

  test("standard glyphs remain recognized without configuration and other symbols stay protected", function()
    fresh({ "╭──╮", "╎  ╎", "╰──╯" })
    at(2, 4)
    equal(draw.draw("l"), true)
    equal(lines()[2], "╎  ├▶")
    for _, text in ipairs({ "▶", "A", "+" }) do
      fresh({ text })
      blocked(function()
        return draw.draw("l")
      end)
    end
  end)
end
