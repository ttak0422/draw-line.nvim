# draw-line.nvim

Draw straight and bent lines with automatic arrowheads, plus rectangle outlines,
in Neovim. Choose from ten built-in styles:

| Style | Line with an arrow | Corners |
| --- | --- | --- |
| `single` | `────▶` | `┌┐└┘` |
| `heavy` | `━━━━▶` | `┏┓┗┛` |
| `double` | `════▶` | `╔╗╚╝` |
| `rounded` | `────▶` | `╭╮╰╯` |
| `dashed2` | `╌╌╌╌▶` | `┌┐└┘` |
| `dashed3` | `┄┄┄┄▶` | `┌┐└┘` |
| `dashed4` | `┈┈┈┈▶` | `┌┐└┘` |
| `heavy_dashed2` | `╍╍╍╍▶` | `┏┓┗┛` |
| `heavy_dashed3` | `┅┅┅┅▶` | `┏┓┗┛` |
| `heavy_dashed4` | `┉┉┉┉▶` | `┏┓┗┛` |

Requires Neovim 0.10+ and a font that renders these Unicode glyphs in one cell.
There are no runtime dependencies or default mappings.

## Draw a line

Add the repository to your plugin manager, or add its local path directly:

```lua
vim.opt.runtimepath:prepend("/path/to/draw-line.nvim")
local draw = require("draw-line")
```

No setup is needed. From an empty line, draw to the right with a style as the
second argument:

```lua
draw.draw("l", "dashed3")
draw.draw("l", "dashed3")
```

```text
┄┄▶
```

Each call draws one edge and moves one cell. The start uses the style's straight
glyph and the free tip is an arrow: `┄▶` after one step, `┄┄▶` after two.
Use `h`, `j`, `k`, and `l` for left, down, up, and right. The style applies only
to that call; omitting it always uses `single`. There is no shared style state.

## Turn a line

Change direction to make a corner. Starting on another empty line:

```lua
draw.draw("l", "rounded")
draw.draw("l", "rounded")
draw.draw("l", "rounded")
draw.draw("j", "rounded")
draw.draw("j", "rounded")
```

```text
───╮
   │
   ▼
```

The arrow follows the free tip as you extend or turn the line. The previous
tip becomes a straight or corner in the requested style, preserving untouched
edge weights. Retracing existing linework removes the arrow until you reach
a free end again.

## Other styles and boxes

```lua
draw.draw("l", "heavy_dashed2")
draw.draw("l", "heavy_dashed2")
-- On an empty line: ╍╍▶
```

The suffix `2`, `3`, or `4` counts dashes per Unicode cell. Dashed styles use
solid corners, endpoints, tees, and crossings of the same weight. Dash phase
across cells is not tracked.

To draw a rectangle in a blank area:

```lua
draw.box({ 1, 1 }, { 3, 7 }, "double")
-- Only this rectangle uses double lines.
```

```text
╔═════╗
║     ║
╚═════╝
```

## API

All methods are on `require("draw-line")`.

| Method | Behavior |
| --- | --- |
| `draw(direction, style?)` | Draw one `h/j/k/l` edge, show an arrow at a free tip, and move one cell. Uses the named style or fixed default `single`. |
| `box({row, col}, {row, col}, style?)` | Draw a rectangle or a same-row/column stroke; preserve the cursor. |
| `box_visual(style?)` | Draw the active Visual Block outline, then enter Normal mode at its top-left corner. |

Coordinates are 1-based buffer rows and display columns. Optional draw and box
styles apply only to that call and default to `single`. Repeat `draw` calls to
extend a line. All operations return `true` on success or `nil, message` if the
edit cannot be made. Invalid arguments raise an error.
See `:help draw-line` for full behavior and error conditions.

## Experimental mouse diagram editor

An opt-in PoC edits overlapping boxes and orthogonal connectors as objects.
The full graph, original text underlay, and stacking order stay separate from
Unicode projection. The original drawing API is unchanged. Requires Neovim
0.10+ (tested on stable 0.12.6; no nightly APIs).

```lua
vim.cmd("enew")
vim.o.mouse = "a"        -- The plugin changes no editor options.
vim.wo.wrap, vim.wo.conceallevel = false, 0
_G.diagram = assert(require("draw-line.diagram").attach())
```

- Drag empty space in Normal mode to create a rectangle of at least 3×3 cells.
  Release commits once; there is no live preview. To overlap an existing box,
  start the drag outside it and finish inside it, or move another box over it.
- Drag a visible `◆` box center to move the box and its attached connectors.
  Drag a `●` segment midpoint perpendicular to its line to change the bend.
- Click an object in the select tool to bring it to the front. A move or bend
  also raises that object. Other objects retain their relative order. Hit-testing
  chooses the frontmost object, and hidden handles cannot be grabbed.
- `diagram:set_tool("connect")` chooses a source and target box with two clicks.
  Facing side centers become anchors. Endpoint picking leaves their order alone;
  the new connector is frontmost. Return with `diagram:set_tool("select")`.
- Esc cancels a pending gesture or connection. Each completed operation, including
  a stacking-only change, is a native `u` / `<C-r>` step. Native label edits and
  counted undo/redo follow the correct undo branch. Missing/pruned ancestry blocks
  further editing instead of guessing a model.
- Scrolling, resizing, editing, Insert mode, or leaving the original window
  cancels a drag. Clicks into another split use native mouse navigation.
- `diagram:detach()` removes this session's mappings and handles, retaining text.

Boxes are **opaque to lower diagram geometry**, including their interiors.
Moving a front box reveals the complete lower boxes/edges again. Boxes and
connectors share one back-to-front list; moving a box updates connected geometry
but raises only the box. Crossing edges retain separate identities, and a visual
intersection never creates a graph connection.

Native text is a protected underlay, not a box label object. It remains visible
through box interiors; a contour or connector touching it is rejected. Use
standard Neovim editing, such as Replace mode within blank cells, for labels.
Labels stay at their buffer cells when boxes move. Tabs, wide/composing Unicode,
and unowned linework are protected. Editing an owned glyph, shifting its display
position, or changing the buffer row count blocks diagram operations until undone.

### Save and resume

Save the text with ordinary `:write`, then save its full object state explicitly:

```lua
assert(diagram:save()) -- Creates/updates <buffer filename>.draw-line.json
```

After reopening the text, with the same display settings:

```lua
_G.diagram = assert(require("draw-line.diagram").load())
```

The versioned JSON sidecar contains full hidden geometry, stable object IDs,
anchors, waypoints, stacking, original text underlay, and a hash of the saved text.
Carry **both files** when moving to another machine. `attach()` always starts an
empty graph; it never infers objects from existing text. `load()` requires the
matching sidecar and does not change text. Detach a live session before loading.

A missing, malformed, incompatible, or mismatched sidecar fails without restoring
or overwriting anything. Save requires an unmodified named UTF-8 text buffer whose
bytes match the file. Existing unknown sidecars, external metadata changes,
concurrent writer locks, and invalid references are rejected. Sidecar replacement
uses a flushed temporary file and atomic rename. Text `:write` and sidecar `save()`
are two separate operations: a crash between them can leave a mismatch, which
`load()` detects and refuses. If sidecar saving fails, keep the live session and
retry after addressing the error. No text rollback, automatic recovery, or external
edit merge is performed. Save As writes a new adjacent sidecar, leaving the old one.
The native undo history starts from the loaded baseline; old-session undo metadata
is not imported. Sidecars have a 4 MiB limit and must be regular files.

The session maps Normal-mode `<LeftMouse>`, `<LeftDrag>`, `<LeftRelease>`, and
`<Esc>` only in this buffer. Existing local mappings cause attach/load to fail;
global mappings are shadowed until detach. User replacements are retained.

**Other PoC boundaries:** 500×500 cells, 100 objects, 10,000 total layer cells
(including opaque interiors and hidden layers), 128 waypoints per edge, single
line style, no resize/delete, arrowheads, label transport, transparency picker,
general obstacle routing, draw.io import, or Hydra integration. Mouse editing
needs an unfolded, left-to-right, nowrap window without conceal/diff. Number/sign
gutters, splits, winbars, horizontal/vertical scroll, and EOF extension work.
Inline virtual text/virtual lines are outside the mouse coordinate contract.
Actual terminal mouse reporting, tmux, and font appearance remain unverified.

See `:help draw-line-diagram`. `make check` runs the original drawing regressions,
model/text/persistence safety tests, isolated UI mouse and keyboard events, and
fresh-process save/reopen tests. It does not connect to a running Neovim.

## License

[MIT](LICENSE).
