# Options

Options follow the columns as name/value pairs. Names are quoted symbols, and values are ordinary expressions:

```scheme
(plot-lines df 'month 'temp
            'group 'city
            'title (string-append "Temperature in " year)
            'output "temps.png")
```

An unknown option name, or a name without a value, is an error.

When [layering](layers.md), options are split between layers and the plot: layer options go to a `layer-*` procedure, and plot options go to `plot-layers`. The `plot-*` procedures accept both.

---

## Layer options

These describe the data and how it's drawn.

| Option | Value | Default |
|---|---|---|
| `'group` | column name; one series per unique value, in its own color and with a legend entry | none |
| `'color` | [color](#colors); overrides the colors from `'group` | gnuplot's color sequence |
| `'label` | legend entry for an ungrouped layer | none |

Options for specific plot types:

| Procedure | Option | Value | Default |
|---|---|---|---|
| `plot-points`, `layer-points` | `'pointsize` | positive number | `1` |
| | `'pointtype` | gnuplot point type number | `7` (filled circle) |
| `plot-lines`, `layer-lines` | `'points` | `#t` to also draw points | `#f` |
| | `'linewidth` | positive number | `2` |
| | `'pointtype`, `'pointsize` | as for points, when `'points` is `#t` | `7`, `1` |
| | `'sort` | `#f` to connect rows in data order | `#t` |
| `plot-bars`, `layer-bars` | `'fill` | [fill density](#fill-and-border) from 0 to 1, or `#f` for no fill | `0.85` |
| | `'border` | `#t` (black), `#f`, or a [color](#colors) | `#t` |
| | `'width` | total width of the bars at each category, where categories are 1 apart | `0.8` |
| `plot-histogram`, `layer-histogram` | `'bins` | number of bins | Sturges' rule, as in R's `hist` |
| | `'binwidth` | bin width; overrides `'bins` | |
| | `'fill` | [fill density](#fill-and-border) from 0 to 1, or `#f` for no fill | `0.85`, or `0.5` (transparent) when grouped |
| | `'border` | `#t` (black), `#f`, or a [color](#colors) | `#t` |
| `plot-boxplot`, `layer-boxplot` | `'fill` | [fill density](#fill-and-border) from 0 to 1, or `#f` for no fill | `0.5` |
| | `'border` | `#t` (black), `#f`, or a [color](#colors) | `#t` |
| | `'width` | total width of the boxes at each category | `0.6` |
| | `'pointtype`, `'pointsize` | style of the outlier points | `7`, `1` |

To see the available point types, run `test` in gnuplot.

An option value of the wrong kind, such as `'fill 2` or `'pointtype 1.5`, is an error.

### Fill and border

`'fill` sets how strongly bars, histogram bars, and boxes are filled with their color: `1` is the full color, and smaller values blend toward the background. When a histogram has groups, the bars overlap, so the fill is transparent instead and overlapping bars show through.

`'border` draws the outline: `#t` in black, a color, or `#f` for none. With `'fill #f 'border #f`, nothing is drawn.

```scheme
> (plot-bars df 'g 'y 'fill #f 'border "dark-red")   ; outlined bars
> (plot-boxplot flowers 'species 'length 'fill 0.2 'border "navy" 'width 0.3)
```

### Colors

`'color` and `'border` take a color name such as `"black"`, `"gray"`, or `"dark-red"`, or a hex color `"#rrggbb"` such as `"#b22222"`. gnuplot has its own list of 111 color names, which doesn't include every CSS name (e.g., `"firebrick"`); if a name isn't on the list, gnuplot prints an error and the plot isn't drawn. To see the list, run `show colornames` in gnuplot. Hex colors always work.

---

## Plot options

These describe the whole figure.

| Option | Value | Default |
|---|---|---|
| `'title` | string | none |
| `'xlabel`, `'ylabel` | string | the column name (`"Count"` for a histogram's y) |
| `'key` | legend position as a gnuplot string, or `#f` to hide it | `"outside right top"` when there are legend entries, otherwise hidden |
| `'grid` | `#t` to draw grid lines | `#f` |
| `'xrange`, `'yrange` | list of two numbers, where `#f` means autoscale, e.g., `'(0 #f)` | autoscale |
| `'logscale` | `'x`, `'y`, or `'xy` | none |
| `'output` | file name ending in `.png`, `.svg`, `.pdf`, or `.txt` (ASCII art) | open a window |
| `'size` | `'(width height)` in pixels (100 pixels per inch for pdf) | gnuplot's default |
| `'commands` | list of extra gnuplot commands; see [gnuplot Scripts](scripts.md) | `'()` |
| `'facet` | column name; one panel per unique value; see [Facets](facets.md) | none |
| `'facet-columns` | number of columns of panels | about square |
| `'facet-scales` | `'fixed`, `'free`, `'free-x`, or `'free-y` | `'fixed` |

Some useful values for `'key` are `"top left"`, `"bottom right"`, `"outside right top"`, `"outside bottom center horizontal"`, and `"top left box"`. Any position accepted by gnuplot's `set key` works.

```scheme
> (plot-points df 'x 'y 'group 'trt 'key "bottom right" 'logscale 'y
               'yrange '(1 #f) 'output "scatter.pdf" 'size '(700 500))
```
