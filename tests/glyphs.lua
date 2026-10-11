return function(context)
  local draw, test, fresh, stroke = context.draw, context.test, context.fresh, context.stroke
  local equal, lines, blocked = context.equal, context.lines, context.blocked
  local api = vim.api
  local standard = require("draw-line.glyphs")
  -- Independent fixture derived from Unicode Box Drawing character names.
  local records =
    vim.json.decode(table.concat(vim.fn.readfile(context.root .. "/tests/fixtures/orthogonal-glyphs.json")))
  local expected = {}
  for _, record in ipairs(records) do
    expected[table.concat(record.edges)] = record.glyph
  end

  test("numeric edge keys distinguish every weight vector and unknown weights", function()
    local seen, count = {}, 0
    for n = 0, 3 do
      for e = 0, 3 do
        for s = 0, 3 do
          for w = 0, 3 do
            local key = standard.key({ [1] = n, [2] = e, [4] = s, [8] = w })
            assert(type(key) == "number" and key >= 0 and key <= 255 and key % 1 == 0)
            assert(not seen[key], "edge key collision")
            seen[key], count = true, count + 1
          end
        end
      end
    end
    equal(count, 256)
    equal(standard.key({}), 0)
    equal(standard.by_edges[0], nil)
    for _, direction in ipairs({ 1, 2, 4, 8 }) do
      equal(standard.key({ [direction] = false }), nil)
      equal(standard.key({ [1] = 1, [2] = 2, [4] = 3, [8] = 1, [direction] = false }), nil)
    end
  end)

  test("invalid weights cannot collide with valid keys or cause arithmetic errors", function()
    for _, direction in ipairs({ 1, 2, 4, 8 }) do
      for _, weight in ipairs({ false, true, -1, 4, 0.5, math.huge, -math.huge, 0 / 0, "1", {} }) do
        equal(standard.key({ [direction] = weight }), nil)
      end
    end
    equal(standard.key({ [1] = 0, [2] = 0, [4] = 0, [8] = 0 }), 0)
    assert(standard.key({ [2] = 4 }) ~= standard.key({ [1] = 1 }))
  end)

  test("malformed definitions and aliases fail during registration", function()
    local function rejected(first_glyph, edit, expected_message)
      local chunk = assert(loadfile(context.root .. "/lua/draw-line/glyphs.lua"))
      local injected = false
      -- Substitute declaration data in an isolated chunk without editing files or globals.
      setfenv(
        chunk,
        setmetatable({
          ipairs = function(values)
            if not injected and type(values[1]) == "table" and values[1][1] == first_glyph then
              injected = true
              edit(values)
            end
            return ipairs(values)
          end,
        }, { __index = _G })
      )
      local ok, message = pcall(chunk)
      assert(injected, "declaration fixture was not substituted")
      equal(ok, false)
      assert(tostring(message):find(expected_message, 1, true), tostring(message))
    end
    for _, weight in ipairs({ false, true, -1, 4, 0.5, math.huge, 0 / 0, "1" }) do
      rejected("─", function(definitions)
        definitions[1][2] = weight
      end, "invalid edge weight")
    end
    rejected("─", function(definitions)
      definitions[1] = { "─", 0, 0, 0, 0 }
    end, "empty or duplicate box-drawing definition")
    rejected("─", function(definitions)
      definitions[2][1] = "─"
    end, "empty or duplicate box-drawing definition")
    rejected("─", function(definitions)
      definitions[2] = { "━", 0, 1, 0, 1 }
    end, "empty or duplicate box-drawing definition")
    rejected("╭", function(aliases)
      aliases[1][2] = "missing"
    end, "alias must name a canonical glyph")
    rejected("╭", function(aliases)
      aliases[2][2] = "╭"
    end, "alias must name a canonical glyph")
    rejected("╭", function(aliases)
      aliases[2][1] = "╭"
    end, "duplicate box-drawing alias")
  end)

  test("all standard glyphs match independent Unicode weights and canonical aliases", function()
    equal(vim.tbl_count(standard.by_edges), 109)
    equal(vim.tbl_count(standard.by_glyph), 125)
    local directions = { 1, 2, 4, 8 }
    for _, record in ipairs(records) do
      local entry, mask = assert(standard.by_glyph[record.glyph]), 0
      for index, direction in ipairs(directions) do
        local weight = record.edges[index]
        equal(entry.edges[direction], weight ~= 0 and weight or nil)
        if weight ~= 0 then
          mask = mask + direction
        end
      end
      equal(entry.mask, mask)
      local key = assert(standard.key(entry.edges), "canonical glyph has unknown or invalid weights")
      equal(standard.by_edges[key], record.glyph)
    end
    for alias, canonical in pairs({
      ["╭"] = "┌",
      ["╮"] = "┐",
      ["╯"] = "┘",
      ["╰"] = "└",
      ["╌"] = "─",
      ["┄"] = "─",
      ["┈"] = "─",
      ["╎"] = "│",
      ["┆"] = "│",
      ["┊"] = "│",
      ["╍"] = "━",
      ["┅"] = "━",
      ["┉"] = "━",
      ["╏"] = "┃",
      ["┇"] = "┃",
      ["┋"] = "┃",
    }) do
      equal(standard.by_glyph[alias], standard.by_glyph[canonical])
      local key = assert(standard.key(standard.by_glyph[alias].edges), "alias has unknown or invalid weights")
      equal(standard.by_edges[key], canonical)
    end
  end)

  test("2424 departing and arriving mixed-edge cases preserve weights or reject atomically", function()
    local passed, rejected = 0, 0
    for _, record in ipairs(records) do
      local degree = 0
      for _, weight in ipairs(record.edges) do
        degree = degree + (weight ~= 0 and 1 or 0)
      end
      -- Neutral double endpoints need visible neighbors and are tested below.
      if degree > 1 then
        for weight, style in ipairs({ "single", "heavy", "double" }) do
          for direction, key in ipairs({ "k", "l", "j", "h" }) do
            for _, arriving in ipairs({ false, true }) do
              fresh({ "     ", "  " .. record.glyph .. "  ", "     " })
              local move = ({ { -1, 0, "j" }, { 0, 1, "h" }, { 1, 0, "k" }, { 0, -1, "l" } })[direction]
              local row, col = arriving and 2 + move[1] or 2, arriving and 3 + move[2] or 3
              api.nvim_win_set_cursor(0, { row, vim.fn.virtcol2col(0, row, col) - 1 })
              local step = arriving and move[3] or key
              local wanted = vim.deepcopy(record.edges)
              wanted[direction] = weight
              local glyph = expected[table.concat(wanted)]
              if glyph then
                equal(draw.draw(step, style), true)
                equal(vim.fn.strcharpart(lines()[2], 2, 1), glyph)
                passed = passed + 1
              else
                local message = blocked(function()
                  return draw.draw(step, style)
                end)
                assert(message:match("no Unicode glyph"), message)
                rejected = rejected + 1
              end
            end
          end
        end
      end
    end
    equal({ passed, rejected }, { 1544, 880 })
  end)

  test("108 endpoint cases preserve neighbor weights or reject atomically", function()
    local styles, directions = { "single", "heavy", "double" }, { "k", "l", "j", "h" }
    local opposite = { 3, 4, 1, 2 }
    local passed, rejected = 0, 0
    for old_weight, old_style in ipairs(styles) do
      for initial, initial_key in ipairs(directions) do
        for new_weight, new_style in ipairs(styles) do
          for added, added_key in ipairs(directions) do
            if added ~= opposite[initial] then
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
              api.nvim_win_set_cursor(0, { 5, 4 })
              equal(stroke(initial_key, 2, old_style), true)
              local row, col = vim.fn.line("."), vim.fn.virtcol(".")
              local wanted = { 0, 0, 0, 0 }
              wanted[opposite[initial]], wanted[added] = old_weight, new_weight
              local glyph = expected[table.concat(wanted)]
              if glyph then
                equal(draw.draw(added_key, new_style), true)
                equal(vim.fn.strcharpart(lines()[row], col - 1, 1), glyph)
                passed = passed + 1
              else
                local message = blocked(function()
                  return draw.draw(added_key, new_style)
                end)
                assert(message:match("no Unicode glyph"), message)
                rejected = rejected + 1
              end
            end
          end
        end
      end
    end
    equal({ passed, rejected }, { 76, 32 })
  end)

  test("drawing does not mutate shared standard glyph definitions", function()
    local before = vim.deepcopy(standard.by_glyph)
    equal(stroke("l", 2, "double"), true)
    equal(stroke("j", 2, nil), true)
    equal(stroke("h", 2, "rounded"), true)
    equal(standard.by_glyph, before)
    equal(standard.by_glyph, before)
  end)
end
