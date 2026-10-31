;; Run from the repository root:  scheme --script examples/examples.ss
;; Writes example images to examples/img/

(import (chezscheme)
        (dataframe)
        (gnuplot-dataframe))

;; Simple deterministic pseudo-random numbers so the examples are reproducible
(define seed 42)
(define (runif)
  (set! seed (mod (+ (* seed 1103515245) 12345) 2147483648))
  (/ seed 2147483648.0))
(define (rnorm mu sd) ; Box-Muller
  (+ mu (* sd (sqrt (* -2 (log (runif)))) (cos (* 2 3.141592653589793 (runif))))))

(define temps
  (make-df* (month 1 2 3 4 5 6 7 8 9 10 11 12
                   1 2 3 4 5 6 7 8 9 10 11 12
                   1 2 3 4 5 6 7 8 9 10 11 12)
            (city "Davis" "Davis" "Davis" "Davis" "Davis" "Davis"
                  "Davis" "Davis" "Davis" "Davis" "Davis" "Davis"
                  "Seattle" "Seattle" "Seattle" "Seattle" "Seattle" "Seattle"
                  "Seattle" "Seattle" "Seattle" "Seattle" "Seattle" "Seattle"
                  "Chicago" "Chicago" "Chicago" "Chicago" "Chicago" "Chicago"
                  "Chicago" "Chicago" "Chicago" "Chicago" "Chicago" "Chicago")
            (temp 8 10 13 15 19 23 25 24 22 17 11 8
                  5 6 8 10 14 17 19 20 17 12 8 5
                  -5 -3 3 9 15 21 24 23 19 12 5 -2)))

(define n 200)
(define species (map (lambda (i) (list-ref '("setosa" "versicolor" "virginica") (mod i 3))) (iota n)))
(define lengths (map (lambda (s) (rnorm (cond [(string=? s "setosa") 5.0]
                                              [(string=? s "versicolor") 5.9]
                                              [else 6.6])
                                        0.45))
                     species))
(define widths (map (lambda (l) (+ (* 0.5 l) (rnorm 0 0.3))) lengths))
(define flowers
  (make-dataframe (make-slist '(species length width) (list species lengths widths))))

(plot-lines temps 'month 'temp 'group 'city 'points #t
            'title "Average monthly temperature"
            'ylabel "Temperature (°C)" 'key "top left"
            'output "examples/img/lines.png")

(plot-points flowers 'length 'width 'group 'species
             'xlabel "Sepal length" 'ylabel "Sepal width"
             'output "examples/img/points.png")

(plot-bars (dataframe-filter* temps (month) (member month '(1 4 7 10)))
           'month 'temp 'group 'city
           'title "Seasonal temperatures" 'grid #t
           'output "examples/img/bars.png")

(plot-histogram flowers 'length 'group 'species 'binwidth 0.2
                'xlabel "Sepal length"
                'output "examples/img/histogram.png")

(plot-boxplot flowers 'species 'length
              'ylabel "Sepal length"
              'output "examples/img/boxplot.png")
