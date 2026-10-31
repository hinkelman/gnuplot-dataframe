#!/usr/bin/env scheme-script
;; -*- mode: scheme; coding: utf-8 -*- !#
#!r6rs

(import (rnrs)
        (srfi :64 testing)
        (dataframe)
        (gnuplot-dataframe))

;; All tests inspect the generated gnuplot script, so gnuplot isn't needed.

(define df
  (make-df* (month 1 2 3 1 2 3)
            (temp 10 12.5 'na 20 21 23)
            (city "A" "A" "A" "B's" "B's" "B's")))

(define (script thunk)
  (let ([p (plot-dry-run)])
    (plot-dry-run #t)
    (let ([s (thunk)])
      (plot-dry-run p)
      s)))

(define (contains? s sub)
  (let ([n (string-length s)] [m (string-length sub)])
    (let loop ([i 0])
      (cond [(> (+ i m) n) #f]
            [(string=? (substring s i (+ i m)) sub) #t]
            [else (loop (+ i 1))]))))

;;-------------------------------------------------------------

(test-begin "xy-test")
(let ([s (script (lambda () (plot-points df 'month 'temp)))])
  (test-assert (contains? s "set xlabel 'month'\n"))
  (test-assert (contains? s "set ylabel 'temp'\n"))
  (test-assert (contains? s "unset key\n"))
  (test-assert (contains? s "$d1 << EOD\n1 10\n2 12.5\n3 NaN\n1 20\n"))
  (test-assert (contains? s "plot $d1 using 1:2 with points pt 7 ps 1 lc 1 notitle\n")))
(let ([s (script (lambda () (plot-lines df 'month 'temp 'group 'city 'title "It's")))])
  (test-assert (contains? s "set title 'It''s'\n"))
  (test-assert (contains? s "set key title 'city'\n"))
  (test-assert (contains? s "$d2 << EOD\n1 20\n2 21\n3 23\nEOD\n"))
  (test-assert (contains? s "title 'A', $d2 using 1:2 with lines lw 2 lc 2 title 'B''s'\n")))
;; lines are sorted by x unless 'sort #f
(let ([d (make-df* (x 3 1 2) (y 30 10 20))])
  (test-assert (contains? (script (lambda () (plot-lines d 'x 'y)))
                          "1 10\n2 20\n3 30\n"))
  (test-assert (contains? (script (lambda () (plot-lines d 'x 'y 'sort #f)))
                          "3 30\n1 10\n2 20\n")))
;; categorical x is mapped to positions with labelled tics
(let ([s (script (lambda () (plot-points df 'city 'temp)))])
  (test-assert (contains? s "set xtics ('A' 0, 'B''s' 1)\n"))
  (test-assert (contains? s "0 10\n0 12.5\n0 NaN\n1 20\n")))
(test-end "xy-test")

;;-------------------------------------------------------------

(test-begin "bars-test")
(let ([s (script (lambda () (plot-bars df 'city 'temp)))])
  (test-assert (contains? s "0 10 0.8\n0 12.5 0.8\n0 NaN 0.8\n1 20 0.8\n"))
  (test-assert (contains? s "set yrange [0:*]\n")))
(let ([s (script (lambda () (plot-bars (make-df* (g "a" "a" "b" "b") (h 1 2 1 2) (y 1 2 3 4))
                                       'g 'y 'group 'h)))])
  (test-assert (contains? s "$d1 << EOD\n-0.2 1 0.4\n0.8 3 0.4\nEOD\n"))
  (test-assert (contains? s "$d2 << EOD\n0.2 2 0.4\n1.2 4 0.4\nEOD\n")))
;; rows with a missing x are skipped
(test-assert (contains? (script (lambda () (plot-bars (make-df* (g "a" 'na "b") (y 1 2 3)) 'g 'y)))
                        "$d1 << EOD\n0 1 0.8\nNaN 2 0.8\n1 3 0.8\nEOD\n"))
(test-end "bars-test")

;;-------------------------------------------------------------

(test-begin "histogram-test")
(let ([s (script (lambda () (plot-histogram (make-df* (x 0 1 1 2 2 2 4)) 'x 'binwidth 1)))])
  (test-assert (contains? s "set ylabel 'Count'\n"))
  (test-assert (contains? s "$d1 << EOD\n0.5 1 1.0\n1.5 2 1.0\n2.5 3 1.0\n3.5 1 1.0\nEOD\n")))
(test-error (script (lambda () (plot-histogram df 'city))))
(test-end "histogram-test")

;;-------------------------------------------------------------

(test-begin "boxplot-test")
(let ([s (script (lambda () (plot-boxplot df 'city 'temp)))])
  (test-assert (contains? s "$d1 << EOD\n10\n12.5\nEOD\n"))
  (test-assert (contains? s "$d1 using (0):1:(0.6) with boxplot fs solid 0.5 border -1 pt 7 ps 1 lc 1 notitle, $d2 using (1):1:(0.6)")))
(let ([s (script (lambda () (plot-boxplot df #f 'temp)))])
  (test-assert (contains? s "$d1 << EOD\n10\n12.5\n20\n21\n23\nEOD\n")))
;; rows with a missing x are skipped
(let ([s (script (lambda () (plot-boxplot (make-df* (g "a" "a" 'na "b") (y 1 2 3 4)) 'g 'y)))])
  (test-assert (contains? s "set xtics ('a' 0, 'b' 1)\n"))
  (test-assert (contains? s "$d1 << EOD\n1\n2\nEOD\n$d2 << EOD\n4\nEOD\n")))
(test-end "boxplot-test")

;;-------------------------------------------------------------

(test-begin "options-test")
(let ([s (script (lambda () (plot-points df 'month 'temp
                                         'output "out.pdf" 'size '(700 500)
                                         'xrange '(0 #f) 'logscale 'y 'grid #t
                                         'commands '("set xtics 1"))))])
  (test-assert (contains? s "set terminal pdfcairo size 7in,5in\nset output 'out.pdf'\n"))
  (test-assert (contains? s "set xrange [0:*]\n"))
  (test-assert (contains? s "set logscale y\n"))
  (test-assert (contains? s "set grid\n"))
  (test-assert (contains? s "set xtics 1\n"))
  (test-assert (contains? s "unset output\n")))
(test-error (script (lambda () (plot-points df 'month 'temp 'colour "red"))))
(test-error (script (lambda () (plot-points df 'month 'temp 'title))))
(test-error (script (lambda () (plot-points df 'month 'missing))))
(test-error (script (lambda () (plot-points df 'month 'temp 'output "x.jpg"))))
(test-end "options-test")

;;-------------------------------------------------------------

(test-begin "layers-test")
;; same group in two layers shares colors and has one key entry per value
(let ([s (script (lambda () (plot-layers (layer-points df 'month 'temp 'group 'city)
                                         (layer-lines df 'month 'temp 'group 'city)
                                         'title "Both")))])
  (test-assert (contains? s "set title 'Both'\n"))
  (test-assert (contains? s "set key title 'city'\n"))
  (test-assert (contains? s "$d4 << EOD\n"))
  (test-assert (contains? s "$d1 using 1:2 with points pt 7 ps 1 lc 1 title 'A', "))
  (test-assert (contains? s "$d3 using 1:2 with lines lw 2 lc 1 notitle, "))
  (test-assert (contains? s "$d4 using 1:2 with lines lw 2 lc 2 notitle\n")))
;; ungrouped layers get a key entry from 'label, and 'color sets the color
(let ([s (script (lambda () (plot-layers (layer-points df 'month 'temp 'label "Obs")
                                         (layer-lines df 'month 'temp 'color "black"))))])
  (test-assert (contains? s "set key outside right top\n"))
  (test-assert (not (contains? s "set key title")))
  (test-assert (contains? s "lc 1 title 'Obs', $d2 using 1:2 with lines lw 2 lc rgb 'black' notitle\n")))
;; a categorical layer puts every layer on the same category positions
(let* ([means (make-df* (city "B's" "A") (avg 21 11))]
       [s (script (lambda () (plot-layers (layer-bars means 'city 'avg)
                                          (layer-points df 'city 'temp))))])
  (test-assert (contains? s "set xtics ('B''s' 0, 'A' 1)\n"))
  (test-assert (contains? s "$d1 << EOD\n0 21 0.8\n1 11 0.8\nEOD\n"))
  (test-assert (contains? s "$d2 << EOD\n1 10\n1 12.5\n1 NaN\n0 20\n"))
  (test-assert (contains? s "set xlabel 'city'\nset ylabel 'avg'\n")))
(test-error (script (lambda () (plot-layers (layer-histogram df 'temp)
                                            (layer-bars df 'city 'temp)))))
(test-error (script (lambda () (plot-layers 'title "No layers"))))
(test-error (script (lambda () (plot-layers (layer-points df 'month 'temp 'title "x")))))
(test-error (script (lambda () (plot-layers (layer-points df 'month 'temp) 'group 'city))))
(test-end "layers-test")

;;-------------------------------------------------------------

(test-begin "facet-test")
(define fdf
  (make-df* (month 1 2 1 2 1 2)
            (temp 10 12 20 21 5 6)
            (city "A" "A" "B" "B" "C" "C")
            (kind "x" "y" "x" "y" "x" "x")))
(define ref (make-df* (month 1 2) (temp 15 15)))
(let ([s (script (lambda () (plot-layers (layer-points fdf 'month 'temp 'group 'kind)
                                         (layer-lines ref 'month 'temp 'color "gray")
                                         'facet 'city 'title "T")))])
  ;; one panel per facet value in a near-square layout
  (test-assert (contains? s "set multiplot layout 2,2 margins "))
  (test-assert (contains? s " title 'T'\n"))
  (test-assert (contains? s "set title 'A' offset 0,-0.5\n"))
  (test-assert (contains? s "set title 'C' offset 0,-0.5\n"))
  (test-assert (contains? s "unset multiplot\n"))
  ;; fixed scales are measured from all panels together
  (test-assert (contains? s "set terminal dumb\n"))
  (test-assert (contains? s "set xrange [GPVAL_X_MIN:GPVAL_X_MAX]\n"))
  (test-assert (contains? s "set yrange [GPVAL_Y_MIN:GPVAL_Y_MAX]\n"))
  ;; group colors are shared across panels, and a layer without the
  ;; facet column is repeated in every panel
  (test-assert (contains? s "set title 'C' offset 0,-0.5\nset key at screen "))
  (test-assert (contains? s "plot $d7 using 1:2 with points pt 7 ps 1 lc 1 notitle, $d8 using 1:2 with lines lw 2 lc rgb 'gray' notitle, "))
  (test-assert (contains? s "$d8 << EOD\n1 15\n2 15\nEOD\n"))
  ;; one shared legend, drawn with the last panel
  (test-assert (contains? s "set key title 'kind'\n"))
  (test-assert (contains? s "keyentry with points pt 7 ps 1 lc 1 title 'x', keyentry with points pt 7 ps 1 lc 2 title 'y'\n"))
  (test-assert (contains? s "set label 1001 'month' at screen "))
  (test-assert (contains? s "set label 1002 'temp' at screen ")))
(let ([s (script (lambda () (plot-points fdf 'month 'temp 'facet 'city
                                         'facet-columns 3 'facet-scales 'free)))])
  (test-assert (contains? s "set multiplot layout 1,3 margins "))
  (test-assert (not (contains? s "GPVAL")))
  (test-assert (not (contains? s "keyentry"))))
(let ([s (script (lambda () (plot-points fdf 'month 'temp 'facet 'city 'facet-scales 'free-y)))])
  (test-assert (contains? s "set xrange [GPVAL_X_MIN:GPVAL_X_MAX]\n"))
  (test-assert (not (contains? s "set yrange [GPVAL"))))
;; a user range is kept, and a key string places the legend in the last panel
(let ([s (script (lambda () (plot-points fdf 'month 'temp 'facet 'city 'group 'kind
                                         'yrange '(0 30) 'key "top left")))])
  (test-assert (contains? s "set yrange [0:30]\n"))
  (test-assert (not (contains? s "set yrange [GPVAL")))
  (test-assert (contains? s "set key top left\n")))
;; histogram panels share the bins of the full data
(let ([s (script (lambda () (plot-histogram (make-df* (x 0 1 2 3) (g "a" "a" "b" "b"))
                                            'x 'binwidth 1 'facet 'g)))])
  (test-assert (contains? s "$d1 << EOD\n0.5 1 1.0\n1.5 1 1.0\n2.5 0 1.0\nEOD\n"))
  (test-assert (contains? s "$d2 << EOD\n0.5 0 1.0\n1.5 0 1.0\n2.5 2 1.0\nEOD\n")))
;; boxplot legend entries are drawn as boxes
(test-assert (contains? (script (lambda () (plot-boxplot fdf 'city 'temp 'group 'kind 'facet 'kind)))
                        "keyentry with boxes fs solid 0.5 border -1 lc 1 title 'x'"))
;; a faceted layer with no rows for a panel's value is left out of that panel
(let ([s (script (lambda () (plot-layers (layer-points fdf 'month 'temp)
                                         (layer-lines (make-df* (month 1 2) (temp 0 1) (city "B" "B"))
                                                      'month 'temp)
                                         'facet 'city 'facet-scales 'free)))])
  (test-assert (contains? s "set title 'A' offset 0,-0.5\nplot $d1 using 1:2 with points pt 7 ps 1 lc 1 notitle\n"))
  (test-assert (contains? s "set title 'B' offset 0,-0.5\nplot $d2 using 1:2 with points pt 7 ps 1 lc 1 notitle, $d3 using 1:2 with lines lw 2 lc 1 notitle\n")))
(test-error (script (lambda () (plot-points fdf 'month 'temp 'facet 'missing))))
(test-error (script (lambda () (plot-points fdf 'month 'temp 'facet 'city 'facet-scales 'loose))))
(test-error (script (lambda () (plot-layers (layer-points fdf 'month 'temp 'facet 'city)))))
(test-end "facet-test")

;;-------------------------------------------------------------

(test-begin "style-test")
(define sdf (make-df* (g "a" "a" "b" "b") (y 1 2 3 4) (k "p" "q" "p" "q")))
;; fill density, border color, and total width
(let ([s (script (lambda () (plot-bars sdf 'g 'y 'group 'k 'fill 0.4 'border "gray" 'width 0.6)))])
  (test-assert (contains? s "$d1 << EOD\n-0.15 1 0.3\n0.85 3 0.3\nEOD\n"))
  (test-assert (contains? s "with boxes fs solid 0.4 border lc rgb 'gray' lc 1 title 'p'")))
(test-assert (contains? (script (lambda () (plot-bars sdf 'g 'y 'fill #f 'border #f)))
                        "with boxes fs transparent solid 0 noborder lc 1 notitle"))
;; grouped histograms use transparent fill
(test-assert (contains? (script (lambda () (plot-histogram sdf 'y 'group 'g 'fill 0.3)))
                        "with boxes fs transparent solid 0.3 border -1 lc 1 title 'a'"))
;; boxplot width, fill, and outlier points; legend entries are drawn as boxes
(let ([s (script (lambda () (plot-boxplot sdf 'g 'y 'group 'k 'width 0.4 'fill 0.9
                                          'pointtype 6 'pointsize 0.5)))])
  (test-assert (contains? s "using (-0.1):1:(0.2) with boxplot fs solid 0.9 border -1 pt 6 ps 0.5 lc 1 title 'p'")))
(test-assert (contains? (script (lambda () (plot-boxplot sdf 'g 'y 'group 'k 'pointtype 6 'facet 'k)))
                        "keyentry with boxes fs solid 0.5 border -1 lc 1 title 'p'"))
;; points on lines
(test-assert (contains? (script (lambda () (plot-lines sdf 'y 'y 'points #t 'pointtype 5 'pointsize 2 'linewidth 1.5)))
                        "with linespoints lw 1.5 pt 5 ps 2 lc 1 notitle"))
;; invalid values are caught before gnuplot sees them
(test-error (script (lambda () (plot-bars sdf 'g 'y 'fill 2))))
(test-error (script (lambda () (plot-bars sdf 'g 'y 'width 0))))
(test-error (script (lambda () (plot-bars sdf 'g 'y 'border 'red))))
(test-error (script (lambda () (plot-points sdf 'y 'y 'pointtype 1.5))))
(test-error (script (lambda () (plot-points sdf 'y 'y 'color 'red))))
(test-error (script (lambda () (plot-lines sdf 'y 'y 'linewidth "thick"))))
(test-error (script (lambda () (plot-histogram sdf 'y 'bins 0))))
;; fill and width don't apply to points
(test-error (script (lambda () (plot-points sdf 'y 'y 'fill 0.5))))
(test-end "style-test")

(exit (if (zero? (test-runner-fail-count (test-runner-get))) 0 1))
