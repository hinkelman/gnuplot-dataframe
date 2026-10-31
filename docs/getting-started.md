# Installation & Import

## Requirements

[gnuplot](http://gnuplot.info) 5.2.6 or later. Tested with gnuplot 6.0 and Chez Scheme 10.3.

## Installation

Clone this repository and its dependencies, [dataframe](https://github.com/hinkelman/dataframe) and [gnuplot-pipe](https://github.com/hinkelman/gnuplot-pipe):

```
$ git clone https://github.com/hinkelman/gnuplot-dataframe
$ git clone https://github.com/hinkelman/dataframe
$ git clone https://github.com/hinkelman/gnuplot-pipe
```

Then add the three directories to Chez Scheme's library path, e.g., in your shell profile:

```
$ export CHEZSCHEMELIBDIRS="/path/to/gnuplot-dataframe:/path/to/dataframe:/path/to/gnuplot-pipe:$CHEZSCHEMELIBDIRS"
```

Those libraries have dependencies of their own, which also need to be on the library path: gnuplot-pipe uses SRFI 1 and SRFI 13 (e.g., from [chez-srfi](https://github.com/arcfide/chez-srfi)), and dataframe uses `(slib format)`.

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
