# gnuplot-dataframe

Plot [dataframes](https://github.com/hinkelman/dataframe) with [gnuplot](http://gnuplot.info) from Chez Scheme. Uses [gnuplot-pipe](https://github.com/hinkelman/gnuplot-pipe) to talk to gnuplot.

The API is loosely modeled on base R plotting: one procedure per plot type, column names for the data, and options for labels, legends, and output. Like `ggplot2`, a `'group` column splits the data into colored series with a legend.

## Requirements

[gnuplot](http://gnuplot.info) 5.0 or later (inline datablocks were added in 5.0). Tested with gnuplot 6.0 and Chez Scheme 10.3.

## Installation

```
$ akku install gnuplot-dataframe
```

## Quick start

```scheme
(import (dataframe)
        (gnuplot-dataframe))

(define temps
  (make-df* (month 1 2 3 4 1 2 3 4)
            (city "Davis" "Davis" "Davis" "Davis"
                  "Chicago" "Chicago" "Chicago" "Chicago")
            (temp 8 10 13 15 -5 -3 3 9)))

;; opens a gnuplot window
(plot-lines temps 'month 'temp 'group 'city 'points #t)

;; writes a file instead
(plot-lines temps 'month 'temp 'group 'city 'points #t
            'ylabel "Temperature (°C)"
            'output "temps.png")
```

The code from the original motivating example

```scheme
(gp:call/gnuplot
 (gp:send "set key top left")
 (gp:send "set xlabel 'month'")
 (gp:send "set ylabel 'Avg. temp'")
 (gp:send "set style data linespoints")
 (gp:plot (map (lambda (c) ...) (remove-duplicates ($ df 'city)))))
```

becomes

```scheme
(plot-lines df 'month 'temp 'group 'city 'points #t
            'key "top left" 'ylabel "Avg. temp")
```

See [examples/examples.ss](examples/examples.ss) for the code that made the images below.

| | |
|---|---|
| ![lines](examples/img/lines.png) | ![points](examples/img/points.png) |
| ![bars](examples/img/bars.png) | ![histogram](examples/img/histogram.png) |
| ![boxplot](examples/img/boxplot.png) | |

## Plot procedures

Columns are given as symbols. Options come after the columns as name/value pairs, e.g., `'group 'city 'title "Temperature"`. An unknown option name is an error.

| Procedure | Draws | Notes |
|---|---|---|
| `(plot-points df x y . opts)` | scatter plot | |
| `(plot-lines df x y . opts)` | line plot | rows are sorted by `x` within each group |
| `(plot-bars df x y . opts)` | bar chart of `y` at each value of `x` | `y` is plotted as given, like `geom_col`, not counted; groups are drawn side by side |
| `(plot-histogram df x . opts)` | histogram of `x` | groups overlap with transparent fill |
| `(plot-boxplot df x y . opts)` | boxplot of `y` for each value of `x` | pass `#f` for `x` for a single box; groups are drawn side by side |

If `x` holds strings (or any non-numeric values), it is treated as categorical: values are placed at evenly spaced positions in order of first appearance and labelled on the x axis. `plot-bars` and `plot-boxplot` always treat `x` as categorical.

Missing values (`'na`) are skipped. In `plot-lines`, a missing `y` breaks the line.

### Options for all plot types

| Option | Value | Default |
|---|---|---|
| `'group` | column name; one series per unique value, with a legend | none |
| `'title` | string | none |
| `'xlabel`, `'ylabel` | string | the column name (`"Count"` for a histogram's y) |
| `'key` | legend position as a gnuplot string, e.g., `"top left"`, `"bottom right"`, `"outside right top"`, or `#f` to hide it | `"outside right top"` when grouped, otherwise hidden |
| `'grid` | `#t` to draw grid lines | `#f` |
| `'xrange`, `'yrange` | list of two numbers, where `#f` means autoscale, e.g., `'(0 #f)` | autoscale |
| `'logscale` | `'x`, `'y`, or `'xy` | none |
| `'output` | file name ending in `.png`, `.svg`, `.pdf`, or `.txt` (ASCII art) | open a window |
| `'size` | `'(width height)` in pixels (100 pixels per inch for pdf) | gnuplot's default |
| `'commands` | list of extra gnuplot commands, sent just before plotting | `'()` |

### Options for specific plot types

| Procedure | Option | Value | Default |
|---|---|---|---|
| `plot-points` | `'pointsize` | number | `1` |
| | `'pointtype` | gnuplot point type number | `7` (filled circle) |
| `plot-lines` | `'points` | `#t` to also draw points | `#f` |
| | `'linewidth` | number | `2` |
| | `'sort` | `#f` to connect rows in data order | `#t` |
| `plot-histogram` | `'bins` | number of bins | Sturges' rule, as in R's `hist` |
| | `'binwidth` | bin width; overrides `'bins` | |

## Going beyond the options

Anything else gnuplot can do is available through `'commands`:

```scheme
(plot-bars df 'country 'gdp
           'commands '("set xtics rotate by 45 right"
                       "set format y '%.0f'"))
```

To see the script that a plot sends to gnuplot, set `plot-dry-run` to `#t`. The plot procedure then returns the script as a string instead of running gnuplot. This is a good way to learn gnuplot commands, or to save a script and edit it by hand.

```scheme
> (parameterize ([plot-dry-run #t])
    (display (plot-points temps 'month 'temp)))
set xlabel 'month'
set ylabel 'temp'
unset key
$d1 << EOD
1 8
...
EOD
plot $d1 using 1:2 with points pt 7 ps 1 notitle
```

## Running the tests

The tests check the generated scripts, so gnuplot is not needed to run them.

```
$ scheme --program tests/test-gnuplot-dataframe.sps
```
