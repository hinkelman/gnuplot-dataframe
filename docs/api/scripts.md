# gnuplot Scripts

Each plot is sent to gnuplot as a script. These tools let you see that script, and add to it when the options don't cover what you need.

---

## `plot-dry-run`

**parameter:** when `#t`, plotting procedures return the gnuplot script as a string instead of running gnuplot. Defaults to `#f`.

This is a good way to learn gnuplot commands, or to save a script and edit it by hand.

```scheme
> (parameterize ([plot-dry-run #t])
    (display (plot-points temps 'month 'temp)))
set xlabel 'month'
set ylabel 'temp'
unset key
$d1 << EOD
1 8
2 10
3 13
4 15
1 -5
2 -3
3 3
4 9
EOD
plot $d1 using 1:2 with points pt 7 ps 1 lc 1 notitle
```

The data are written as inline datablocks (`$d1`, `$d2`, …), one for each group of each layer. Missing values are written as `NaN`, which gnuplot skips. Categorical values are written as their positions on the x axis, with the labels set by `set xtics`.

To run a saved script:

```
$ gnuplot --persist plot.gp
```

---

## `'commands`

**plot option:** a list of gnuplot commands, sent after the other settings and just before the `plot` command, so they can override them.

```scheme
> (plot-bars df 'country 'gdp
             'commands '("set xtics rotate by 45 right"
                         "set format y '%.0f'"))
```

Some useful commands:

| Command | Effect |
|---|---|
| `"set xtics rotate by 45 right"` | rotate x axis labels |
| `"set format y '%.1f'"` | format y axis numbers |
| `"set ytics 5"` | y axis tick every 5 units |
| `"set xzeroaxis"` | draw a line at y = 0 |
| `"set label 'peak' at 7, 25"` | add text at a point |
| `"set arrow from 5, 20 to 7, 24"` | add an arrow |
| `"set object rectangle from 3, -5 to 5, 30 fc rgb '#eeeeee' behind"` | shade a region |

See the [gnuplot documentation](http://gnuplot.info/documentation.html) for more.
