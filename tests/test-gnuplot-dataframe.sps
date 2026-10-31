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
  (test-assert (contains? s "plot $d1 using 1:2 with points pt 7 ps 1 notitle\n")))
(let ([s (script (lambda () (plot-lines df 'month 'temp 'group 'city 'title "It's")))])
  (test-assert (contains? s "set title 'It''s'\n"))
  (test-assert (contains? s "set key title 'city'\n"))
  (test-assert (contains? s "$d2 << EOD\n1 20\n2 21\n3 23\nEOD\n"))
  (test-assert (contains? s "title 'A', $d2 using 1:2 with lines lw 2 title 'B''s'\n")))
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
  (test-assert (contains? s "set boxwidth 0.8 absolute\n"))
  (test-assert (contains? s "set yrange [0:*]\n")))
(let ([s (script (lambda () (plot-bars (make-df* (g "a" "a" "b" "b") (h 1 2 1 2) (y 1 2 3 4))
                                       'g 'y 'group 'h)))])
  (test-assert (contains? s "set boxwidth 0.4 absolute\n"))
  (test-assert (contains? s "$d1 << EOD\n-0.2 1\n0.8 3\nEOD\n"))
  (test-assert (contains? s "$d2 << EOD\n0.2 2\n1.2 4\nEOD\n")))
(test-end "bars-test")

;;-------------------------------------------------------------

(test-begin "histogram-test")
(let ([s (script (lambda () (plot-histogram (make-df* (x 0 1 1 2 2 2 4)) 'x 'binwidth 1)))])
  (test-assert (contains? s "set ylabel 'Count'\n"))
  (test-assert (contains? s "$d1 << EOD\n0.5 1\n1.5 2\n2.5 3\n3.5 1\nEOD\n")))
(test-error (script (lambda () (plot-histogram df 'city))))
(test-end "histogram-test")

;;-------------------------------------------------------------

(test-begin "boxplot-test")
(let ([s (script (lambda () (plot-boxplot df 'city 'temp)))])
  (test-assert (contains? s "$d1 << EOD\n10\n12.5\nEOD\n"))
  (test-assert (contains? s "$d1 using (0):1 with boxplot lc 1 notitle, $d2 using (1):1")))
(let ([s (script (lambda () (plot-boxplot df #f 'temp)))])
  (test-assert (contains? s "$d1 << EOD\n10\n12.5\n20\n21\n23\nEOD\n")))
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

(exit (if (zero? (test-runner-fail-count (test-runner-get))) 0 1))
