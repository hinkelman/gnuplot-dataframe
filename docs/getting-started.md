# Installation & Import

## Requirements

[gnuplot](http://gnuplot.info) 5.2.6 or later. Tested with gnuplot 6.0 and Chez Scheme 10.3.

`gnuplot-dataframe` depends on [dataframe](https://hinkelman.github.io/dataframe) and [gnuplot-pipe](https://github.com/hinkelman/gnuplot-pipe), which Akku installs automatically.

## Installation

```
$ akku install gnuplot-dataframe
```

For more information on getting started with [Akku](https://akkuscm.org/), see this [blog post](https://www.travishinkelman.com/posts/getting-started-with-akku-package-manager-for-scheme/).

## Import

```scheme
(import (dataframe)
        (gnuplot-dataframe))
```

## Windows and files

By default, each plot opens in a new gnuplot window. To write a file instead, pass `'output` with a file name ending in `.png`, `.svg`, `.pdf`, or `.txt`:

```scheme
(plot-points df 'x 'y 'output "scatter.png")
```

The `.txt` format draws the plot as ASCII art, which is handy in a terminal or over SSH.
