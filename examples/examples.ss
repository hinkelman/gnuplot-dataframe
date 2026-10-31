;; Run from the repository root:  scheme --script examples/examples.ss
;; Writes example images to docs/img/ (used by the README and docs site)

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
            'output "docs/img/lines.png")

(plot-points flowers 'length 'width 'group 'species
             'xlabel "Sepal length" 'ylabel "Sepal width"
             'output "docs/img/points.png")

(plot-bars (dataframe-filter* temps (month) (member month '(1 4 7 10)))
           'month 'temp 'group 'city
           'title "Seasonal temperatures" 'grid #t
           'output "docs/img/bars.png")

(plot-histogram flowers 'length 'group 'species 'binwidth 0.2
                'xlabel "Sepal length"
                'output "docs/img/histogram.png")

(plot-boxplot flowers 'species 'length
              'ylabel "Sepal length"
              'output "docs/img/boxplot.png")

;; Layers ---------------------------------------------------------------

;; least-squares line through each species, drawn over the points
(define (fit-line df)
  (let* ([xs ($ df 'length)]
         [ys ($ df 'width)]
         [mx (mean xs)]
         [my (mean ys)]
         [slope (/ (sum (map (lambda (x y) (* (- x mx) (- y my))) xs ys))
                   (sum (map (lambda (x) (expt (- x mx) 2)) xs)))]
         [x-ends (list (apply min xs) (apply max xs))])
    (make-dataframe
     (make-slist '(species length width)
                 (list (list (car ($ df 'species)) (car ($ df 'species)))
                       x-ends
                       (map (lambda (x) (+ my (* slope (- x mx)))) x-ends))))))

(define fits (dataframe-bind-all (map fit-line (dataframe-split flowers 'species))))

(plot-layers (layer-points flowers 'length 'width 'group 'species)
             (layer-lines fits 'length 'width 'group 'species)
             'xlabel "Sepal length" 'ylabel "Sepal width"
             'output "docs/img/layers-fit.png")

(define species-means
  (dataframe-aggregate* flowers (species) (avg (length) (mean length))))

(plot-layers (layer-boxplot flowers 'species 'length)
             (layer-points species-means 'species 'avg
                           'color "black" 'pointtype 9 'pointsize 1.5
                           'label "Mean")
             'ylabel "Sepal length"
             'output "docs/img/layers-boxplot.png")

;; Facets ---------------------------------------------------------------

(plot-layers (layer-points flowers 'length 'width 'group 'species)
             (layer-lines fits 'length 'width 'group 'species)
             'facet 'species
             'xlabel "Sepal length" 'ylabel "Sepal width"
             'output "docs/img/facet-layers.png")

(plot-histogram flowers 'length 'facet 'species 'facet-columns 1 'binwidth 0.2
                'xlabel "Sepal length"
                'output "docs/img/facet-histogram.png")
