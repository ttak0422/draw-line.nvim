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

An opt-in PoC keeps boxes and orthogonal connectors as objects during one
buffer session. The original drawing API is unchanged. Try it in a disposable
buffer with Neovim 0.10+ (tested on stable 0.12.6; no nightly APIs):

```lua
vim.cmd("enew")
vim.o.mouse = "a"        -- Enable mouse input yourself; the plugin changes no options.
vim.wo.wrap = false
vim.wo.conceallevel = 0
local diagram = assert(require("draw-line.diagram").attach())
```

- In Normal mode, drag empty space to create a rectangle of at least 3×3 cells.
  Releasing the mouse commits the change, without a live preview.
- Drag the `◆` at a box's exact center to move its outline and attached connectors.
- Run `diagram:set_tool("connect")`, then click a source box and a different
  target box. The connector uses the centers of facing sides, with a small gap
  required between boxes. Use `diagram:set_tool("select")` to resume dragging.
- Drag a `●` at a line segment's midpoint perpendicular to that segment to
  change its bend. A straight connector gains bends when its handle is dragged.
  Short segments have no handle. At a crossing with coincident handles, the
  older connector wins selection.
- Press Esc to cancel a gesture or pending connection. Each completed gesture
  is one native `u` / `<C-r>` step. Scrolling, resizing, leaving the window,
  starting Insert mode, or editing during a drag cancels it.
  Clicking another split uses Neovim's native mouse behavior to switch focus.
- `diagram:detach()` ends the session, removes its mappings and handles, and
  leaves the drawing as ordinary text. Detach before returning to freehand drawing.

The session temporarily maps Normal-mode `<LeftMouse>`, `<LeftDrag>`,
`<LeftRelease>`, and `<Esc>` in this buffer. Existing local mappings on these
keys cause attach to fail; global mappings are shadowed until detach. Mappings
replaced by the user during the session are left alone on detach.

**PoC boundaries:** a 500×500 cell canvas, at most 10,000 drawing cells, single
line style, no object resize/delete, arrows, general obstacle routing, or file
format/import. Boxes cannot overlap or share cells. Connectors may cross each
other; a visual junction does not add a graph connection. Moves that would make
a connector cross a box are rejected; adjust the bend or move in smaller steps.
The graph and undo snapshots live in memory. Saving writes plain text only;
detach, buffer wipeout, reload into a new buffer, or restarting Neovim loses
object editing. Saved linework is protected, never inferred as objects.

Use standard Neovim editing for labels (for example, Replace mode to fill blank
cells without shifting the borders). Labels stay at their buffer positions when
a box moves. Text, tabs, wide Unicode, composing characters, and unowned linework
are protected from drawing edits. Changing a drawing cell or the buffer's row
count blocks further operations until that edit is undone or the session is
detached. Other edits must leave every owned glyph at the same display cell.
Undo must be enabled. Session methods edit only their current buffer.
Native label edits inherit the diagram state on their own undo branch, including
counted undo/redo. If the needed undo ancestry is pruned, further edits are blocked.

Mouse editing needs an unfolded, left-to-right, `nowrap`, unconcealed window
without diff mode. Number/sign gutters, split windows, and horizontal/vertical
scrolling are supported. Inline virtual text and virtual lines are outside this
PoC's mouse coordinate contract. Test in a plain window first. Actual terminal
mouse reporting and font appearance have not been manually verified.

See `:help draw-line-diagram` for the session API. `make check` runs existing
drawing tests, diagram safety/undo tests, and mouse events against a separate
embedded Neovim with a UI grid; it does not connect to a running Neovim.

## License

[MIT](LICENSE).
