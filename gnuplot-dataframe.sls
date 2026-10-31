(library (gnuplot-dataframe)
  (export
   plot-points
   plot-lines
   plot-bars
   plot-histogram
   plot-boxplot
   plot-dry-run)

  (import (chezscheme)
          (only (dataframe)
                dataframe?
                dataframe-dim
                dataframe-contains?
                dataframe-values
                na?
                remove-duplicates)
          (prefix (gnuplot-pipe) gp:))

  ;; Each plot-* procedure builds a gnuplot script as a list of command
  ;; strings and sends it through a gnuplot pipe. Data are written as
  ;; inline datablocks ($d1 << EOD ... EOD) rather than with gp:plot so
  ;; that the script can be inspected, replotted, and saved as a file.
  ;; Categorical values are mapped to integer positions in Scheme and
  ;; labelled with explicit xtics, so datablocks only contain numbers.

  ;; When true, plot-* procedures return the gnuplot script as a string
  ;; instead of running gnuplot.
  (define plot-dry-run (make-parameter #f))

  (define common-options
    '(group title xlabel ylabel key grid xrange yrange logscale
            output size commands))

  ;;---------------------------------------------------------------------
  ;; Public procedures.

  (define (plot-points df x y . opts)
    (let* ([who "(plot-points df x y . opts)"]
           [o (parse-options who opts '(pointsize pointtype))]
           [style (format "with points pt ~a ps ~a"
                          (opt o 'pointtype 7) (opt o 'pointsize 1))])
      (xy-plot who df x y o style #f)))

  (define (plot-lines df x y . opts)
    (let* ([who "(plot-lines df x y . opts)"]
           [o (parse-options who opts '(points linewidth sort))]
           [style (format "with ~a lw ~a~a"
                          (if (opt o 'points #f) "linespoints" "lines")
                          (opt o 'linewidth 2)
                          (if (opt o 'points #f) " pt 7" ""))])
      (xy-plot who df x y o style (opt o 'sort #t))))

  (define (plot-bars df x y . opts)
    (let* ([who "(plot-bars df x y . opts)"]
           [o (parse-options who opts '())])
      (check-columns who df (list x y (opt o 'group #f)))
      (let* ([levels (map ->label (remove-duplicates ($ df x)))]
             [groups (split-groups df (opt o 'group #f))]
             [k (length groups)]
             [width (/ 0.8 k)]
             [ys (remove-na ($ df y))])
        (run-script
         o
         (append
          (list "set style fill solid 0.85 border -1"
                (format "set boxwidth ~a absolute" (fmt width))
                "set offsets 0, 0, graph 0.05, 0")
          (category-xtics levels)
          ;; bars should start from zero, which autoscaling does not ensure
          (if (and (not (opt o 'yrange #f)) (for-all (lambda (v) (and (real? v) (nonnegative? v))) ys))
              '("set yrange [0:*]")
              '()))
         (symbol->string x) (symbol->string y)
         (map (lambda (g i)
                (let* ([sub (cdr g)]
                       [pos (map (lambda (v) (+ (index-of (->label v) levels)
                                                (dodge i k width)))
                                 ($ sub x))])
                  (make-layer (list pos ($ sub y))
                              (format "using 1:2 with boxes lc ~a" (+ i 1))
                              (car g))))
              groups (iota k))))))

  (define (plot-histogram df x . opts)
    (let* ([who "(plot-histogram df x . opts)"]
           [o (parse-options who opts '(bins binwidth))])
      (check-columns who df (list x (opt o 'group #f)))
      (let* ([vals (remove-na ($ df x))]
             [_ (unless (and (pair? vals) (for-all real? vals))
                  (assertion-violation who "x must be a numeric column"))]
             [lo (apply min vals)]
             [hi (apply max vals)]
             [width (inexact
                     (or (opt o 'binwidth #f)
                         (if (= lo hi)
                             1
                             (/ (- hi lo)
                                (opt o 'bins (sturges (length vals)))))))]
             [nbins (max 1 (exact (ceiling (/ (- hi lo) width))))]
             [groups (split-groups df (opt o 'group #f))])
        (run-script
         o
         (list (if (> (length groups) 1)
                   "set style fill transparent solid 0.5 border -1"
                   "set style fill solid 0.85 border -1")
               (format "set boxwidth ~a absolute" (fmt width))
               "set offsets 0, 0, graph 0.05, 0"
               "set yrange [0:*]")
         (symbol->string x) "Count"
         (map (lambda (g i)
                (let ([counts (bin-counts (remove-na ($ (cdr g) x))
                                          lo width nbins)])
                  (make-layer (list (map (lambda (b) (+ lo (* width (+ b 0.5))))
                                         (iota nbins))
                                    counts)
                              (format "using 1:2 with boxes lc ~a" (+ i 1))
                              (car g))))
              groups (iota (length groups)))))))

  ;; x may be #f for a single box of all y values
  (define (plot-boxplot df x y . opts)
    (let* ([who "(plot-boxplot df x y . opts)"]
           [o (parse-options who opts '())])
      (check-columns who df (list x y (opt o 'group #f)))
      (let* ([levels (if x (map ->label (remove-duplicates ($ df x))) '(""))]
             [groups (split-groups df (opt o 'group #f))]
             [k (length groups)]
             [width (/ 0.6 k)])
        (run-script
         o
         (append
          (list "set style fill solid 0.5 border -1"
                "set style boxplot outliers pointtype 7"
                (format "set boxwidth ~a absolute" (fmt width)))
          (if x (category-xtics levels) '("set xtics ('' 0)" "set xrange [-1:1]")))
         (if x (symbol->string x) "") (symbol->string y)
         (apply append
                (map (lambda (g i)
                       (let ([sub (cdr g)])
                         (filter
                          values
                          (map (lambda (level j)
                                 (let ([ys (remove-na
                                            (if x
                                                (select-where ($ sub y) ($ sub x)
                                                              (lambda (v) (string=? (->label v) level)))
                                                ($ sub y)))])
                                   (and (pair? ys)
                                        (make-layer
                                         (list ys)
                                         (format "using (~a):1 with boxplot lc ~a"
                                                 (fmt (+ j (dodge i k width))) (+ i 1))
                                         ;; one key entry per group
                                         (and (= j 0) (car g))))))
                               levels (iota (length levels))))))
                     groups (iota k)))))))

  ;;---------------------------------------------------------------------
  ;; Shared plot construction.

  ;; A layer is one datablock plus the plot clause that draws it.
  (define (make-layer columns spec title)
    (list columns spec title))

  (define (xy-plot who df x y o style sort?)
    (check-columns who df (list x y (opt o 'group #f)))
    (let* ([xvals ($ df x)]
           [categorical? (not (for-all real? (remove-na xvals)))]
           [levels (and categorical? (map ->label (remove-duplicates xvals)))]
           [->x (if categorical?
                    (lambda (v) (if (na? v) v (index-of (->label v) levels)))
                    values)])
      (run-script
       o
       (if categorical? (category-xtics levels) '())
       (symbol->string x) (symbol->string y)
       (map (lambda (g)
              (let* ([rows (map list (map ->x ($ (cdr g) x)) ($ (cdr g) y))]
                     [rows (if sort?
                               (sort (lambda (a b) (< (car a) (car b)))
                                     (filter (lambda (r) (not (na? (car r)))) rows))
                               rows)])
                (make-layer (list (map car rows) (map cadr rows))
                            (string-append "using 1:2 " style)
                            (car g))))
            (split-groups df (opt o 'group #f))))))

  ;; Assemble the full script: output, plot-specific settings, common
  ;; settings, user commands, datablocks, and the plot command.
  (define (run-script o settings default-xlabel default-ylabel layers)
    (let* ([grouped? (opt o 'group #f)]
           [names (map (lambda (i) (format "$d~a" (+ i 1)))
                       (iota (length layers)))]
           [output (opt o 'output #f)])
      (send-script
       (append
        (if output (output-commands output (opt o 'size #f)) '())
        settings
        (label-command "title" (opt o 'title #f))
        (label-command "xlabel" (opt o 'xlabel default-xlabel))
        (label-command "ylabel" (opt o 'ylabel default-ylabel))
        (key-commands (opt o 'key (if grouped? "outside right top" #f))
                      grouped?)
        (if (opt o 'grid #f) '("set grid") '())
        (range-command "xrange" (opt o 'xrange #f))
        (range-command "yrange" (opt o 'yrange #f))
        (logscale-command (opt o 'logscale #f))
        (opt o 'commands '())
        (apply append (map (lambda (name layer) (datablock name (car layer)))
                           names layers))
        (list
         (string-append
          "plot "
          (join (map (lambda (name layer)
                       (let ([title (caddr layer)])
                         (format "~a ~a ~a" name (cadr layer)
                                 (if (and grouped? title)
                                     (string-append "title " (quote-string title))
                                     "notitle"))))
                     names layers)
                ", ")))
        (if output '("unset output") '())))))

  (define (send-script script)
    (if (plot-dry-run)
        (apply string-append (map (lambda (s) (string-append s "\n")) script))
        (gp:call/gnuplot
         (for-each gp:send script))))

  (define (datablock name columns)
    (append
     (list (string-append name " << EOD"))
     (apply map (lambda row (join (map fmt row) " ")) columns)
     (list "EOD")))

  (define (output-commands file size)
    (let* ([ext (path-extension file)]
           [size-str
            (lambda (scale unit)
              (if size
                  (format " size ~a~a,~a~a"
                          (fmt (/ (car size) scale)) unit
                          (fmt (/ (cadr size) scale)) unit)
                  ""))]
           [terminal
            (cond [(string=? ext "png") (string-append "pngcairo" (size-str 1 ""))]
                  [(string=? ext "svg") (string-append "svg" (size-str 1 ""))]
                  ;; pdf sizes are given in pixels at 100 per inch
                  [(string=? ext "pdf") (string-append "pdfcairo" (size-str 100 "in"))]
                  [(string=? ext "txt") "dumb"]
                  [else (assertion-violation
                         "output" "Extension must be png, pdf, svg or txt" file)])])
      (list (string-append "set terminal " terminal)
            (string-append "set output " (quote-string file)))))

  (define (category-xtics levels)
    (list (string-append
           "set xtics ("
           (join (map (lambda (level i) (format "~a ~a" (quote-string level) i))
                      levels (iota (length levels)))
                 ", ")
           ")")
          (format "set xrange [-0.5:~a]" (fmt (- (length levels) 0.5)))))

  (define (label-command name value)
    (if value
        (list (format "set ~a ~a" name (quote-string value)))
        '()))

  (define (key-commands key grouped?)
    (cond [(not key) '("unset key")]
          [(string? key)
           (cons (string-append "set key " key)
                 (if grouped?
                     (list (string-append "set key title "
                                          (quote-string (symbol->string grouped?))))
                     '()))]
          [else (assertion-violation "key" "key must be a string or #f" key)]))

  (define (range-command name range)
    (if range
        (list (format "set ~a [~a:~a]" name
                      (range-bound (car range)) (range-bound (cadr range))))
        '()))

  (define (range-bound v)
    (if (real? v) (fmt v) "*"))

  (define (logscale-command axes)
    (if axes
        (list (string-append "set logscale " (symbol->string axes)))
        '()))

  ;;---------------------------------------------------------------------
  ;; Options are passed as a property list, e.g., 'group 'city 'title "Temp".

  (define (parse-options who opts extra)
    (let loop ([opts opts] [acc '()])
      (cond [(null? opts) acc]
            [(null? (cdr opts))
             (assertion-violation who "options must be given as name/value pairs" opts)]
            [(not (memq (car opts) (append common-options extra)))
             (assertion-violation who "unknown option" (car opts))]
            [else (loop (cddr opts) (cons (cons (car opts) (cadr opts)) acc))])))

  (define (opt o name default)
    (let ([p (assq name o)])
      (if p (cdr p) default)))

  ;;---------------------------------------------------------------------
  ;; Helpers.

  (define (check-columns who df names)
    (unless (dataframe? df)
      (assertion-violation who "df is not a dataframe"))
    (unless (> (car (dataframe-dim df)) 0)
      (assertion-violation who "df has zero rows"))
    (for-each (lambda (name)
                (when (and name (not (dataframe-contains? df name)))
                  (assertion-violation who "column not in df" name)))
              names))

  ;; Returns list of (label . df-subset) in order of first appearance.
  ;; Ungrouped data is a single group with label #f.
  (define (split-groups df group)
    (if (not group)
        (list (cons #f df))
        (let* ([gvals ($ df group)]
               [levels (remove-duplicates gvals)])
          (map (lambda (level)
                 (cons (->label level)
                       (subset-rows df (map (lambda (v) (equal? v level)) gvals))))
               levels))))

  ;; A group subset is a procedure from column name to values, which is
  ;; all the plotting code needs; $ accepts it or a dataframe.
  (define (subset-rows df keep)
    (lambda (name) (select-where ($ df name) keep values)))

  (define ($ df name)
    (if (procedure? df) (df name) (dataframe-values df name)))

  (define (select-where vals keys pred)
    (let loop ([vals vals] [keys keys] [acc '()])
      (cond [(null? vals) (reverse acc)]
            [(pred (car keys)) (loop (cdr vals) (cdr keys) (cons (car vals) acc))]
            [else (loop (cdr vals) (cdr keys) acc)])))

  (define (bin-counts vals lo width nbins)
    (let ([counts (make-vector nbins 0)])
      (for-each (lambda (v)
                  (let ([b (min (- nbins 1)
                                (exact (floor (/ (- v lo) width))))])
                    (vector-set! counts b (+ 1 (vector-ref counts b)))))
                vals)
      (vector->list counts)))

  ;; Sturges' rule, the default in R's hist()
  (define (sturges n)
    (exact (ceiling (+ 1 (log n 2)))))

  ;; offset of group i (of k) within a category of total width k * width
  (define (dodge i k width)
    (* width (- i (/ (- k 1) 2))))

  (define (index-of x lst)
    (let loop ([lst lst] [i 0])
      (cond [(null? lst) #f]
            [(equal? x (car lst)) i]
            [else (loop (cdr lst) (+ i 1))])))

  (define (remove-na lst)
    (filter (lambda (x) (not (na? x))) lst))

  (define (->label v)
    (cond [(string? v) v]
          [(na? v) "NA"]
          [else (format "~a" v)]))

  ;; Format a value for gnuplot; missing and non-finite values become NaN,
  ;; which gnuplot treats as undefined (and breaks lines).
  (define (fmt v)
    (cond [(and (real? v) (exact? v) (integer? v)) (number->string v)]
          [(and (real? v) (finite? (inexact v))) (number->string (inexact v))]
          [else "NaN"]))

  ;; gnuplot single-quoted string; a single quote is escaped by doubling
  (define (quote-string s)
    (let ([out (open-output-string)])
      (write-char #\' out)
      (string-for-each (lambda (c)
                         (when (char=? c #\') (write-char #\' out))
                         (write-char c out))
                       s)
      (write-char #\' out)
      (get-output-string out)))

  (define (join strs sep)
    (if (null? strs)
        ""
        (fold-left (lambda (acc s) (string-append acc sep s)) (car strs) (cdr strs))))

  )
