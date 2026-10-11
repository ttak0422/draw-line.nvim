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

## License

[MIT](LICENSE).
