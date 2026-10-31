(library (gnuplot-dataframe)
  (export
   plot-layers
   layer-points
   layer-lines
   layer-bars
   layer-histogram
   layer-boxplot
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

  ;; A plot is a list of layers plus plot-level options. Each layer-*
  ;; procedure records a dataframe, columns, and layer options; plot-layers
  ;; turns the layers into one gnuplot script and sends it through a
  ;; gnuplot pipe. The plot-* procedures are shortcuts for a single layer.
  ;;
  ;; Data are written as inline datablocks ($d1 << EOD ... EOD) rather than
  ;; with gp:plot so that the script can be inspected, replotted, and saved
  ;; as a file. Categorical values are mapped to integer positions in Scheme
  ;; and labelled with explicit xtics, so datablocks only contain numbers.

  ;; When true, plotting procedures return the gnuplot script as a string
  ;; instead of running gnuplot.
  (define plot-dry-run (make-parameter #f))

  (define plot-options
    '(title xlabel ylabel key grid xrange yrange logscale output size commands))

  (define layer-options '(group color label))

  ;; kind is one of points, lines, bars, histogram, boxplot; o is an alist
  (define-record-type layer
    (fields kind df x y o))

  ;;---------------------------------------------------------------------
  ;; Layers.

  (define (layer-points df x y . opts)
    (new-layer "(layer-points df x y . opts)" 'points df x y opts
               '(pointsize pointtype)))

  (define (layer-lines df x y . opts)
    (new-layer "(layer-lines df x y . opts)" 'lines df x y opts
               '(points linewidth sort)))

  (define (layer-bars df x y . opts)
    (new-layer "(layer-bars df x y . opts)" 'bars df x y opts '()))

  (define (layer-histogram df x . opts)
    (let ([who "(layer-histogram df x . opts)"])
      (let ([l (new-layer who 'histogram df x #f opts '(bins binwidth))])
        (let ([vals (remove-na ($ df x))])
          (unless (and (pair? vals) (for-all real? vals))
            (assertion-violation who "x must be a numeric column" x)))
        l)))

  ;; x may be #f for a single box of all y values
  (define (layer-boxplot df x y . opts)
    (new-layer "(layer-boxplot df x y . opts)" 'boxplot df x y opts '()))

  (define (new-layer who kind df x y opts extra)
    (let ([o (parse-options who opts (append layer-options extra))])
      (check-columns who df (list x y (opt o 'group #f)))
      (make-layer kind df x y o)))

  ;;---------------------------------------------------------------------
  ;; Single-layer shortcuts. Options are split between the layer and plot.

  (define (plot-points df x y . opts)
    (shortcut layer-points (list df x y) opts))

  (define (plot-lines df x y . opts)
    (shortcut layer-lines (list df x y) opts))

  (define (plot-bars df x y . opts)
    (shortcut layer-bars (list df x y) opts))

  (define (plot-histogram df x . opts)
    (shortcut layer-histogram (list df x) opts))

  (define (plot-boxplot df x y . opts)
    (shortcut layer-boxplot (list df x y) opts))

  (define (shortcut make args opts)
    (let loop ([opts opts] [layer-opts '()] [plot-opts '()])
      (cond [(or (null? opts) (null? (cdr opts)))
             ;; a dangling option name is left for parse-options to report
             (apply plot-layers
                    (apply make (append args (reverse layer-opts) opts))
                    (reverse plot-opts))]
            [(memq (car opts) plot-options)
             (loop (cddr opts) layer-opts
                   (cons* (cadr opts) (car opts) plot-opts))]
            [else
             (loop (cddr opts) (cons* (cadr opts) (car opts) layer-opts)
                   plot-opts)])))

  ;;---------------------------------------------------------------------
  ;; Combining layers.

  ;; (plot-layers layer1 layer2 ... 'option value ...)
  (define (plot-layers . args)
    (let* ([who "(plot-layers layer ... . opts)"]
           [layers (take-while layer? args)]
           [o (parse-options who (list-tail args (length layers)) plot-options)])
      (when (null? layers)
        (assertion-violation who "no layers given"))
      (let* ([levels (category-levels who layers)]
             [group-labels (remove-duplicates
                            (apply append (map layer-group-labels layers)))]
             [group-names (remove-duplicates
                           (filter values (map (lambda (l) (opt (layer-o l) 'group #f))
                                               layers)))]
             [elements (apply append
                              (map (lambda (l) (layer-elements l levels group-labels))
                                   layers))]
             [first (car layers)])
        (run-script
         o
         (layer-settings layers levels)
         (if (layer-x first) (symbol->string (layer-x first)) "")
         (if (layer-y first) (symbol->string (layer-y first)) "Count")
         (and (= (length group-names) 1) (car group-names))
         elements))))

  ;; Shared x positions for categorical layers, or #f if all x are numeric.
  ;; If any layer is categorical, the x values of all layers are mapped
  ;; through the same levels so that, e.g., a line can be drawn over bars.
  (define (category-levels who layers)
    (and (exists layer-categorical? layers)
         (begin
           (when (exists (lambda (l) (eq? (layer-kind l) 'histogram)) layers)
             (assertion-violation
              who "a histogram can't be combined with a categorical x axis"))
           (remove-duplicates
            (apply append
                   (map (lambda (l)
                          (if (layer-x l)
                              (map ->label (remove-na ($ (layer-df l) (layer-x l))))
                              '("")))
                        layers))))))

  (define (layer-categorical? l)
    (or (memq (layer-kind l) '(bars boxplot))
        (not (for-all real? (remove-na ($ (layer-df l) (layer-x l)))))))

  (define (layer-group-labels l)
    (map car (split-groups (layer-df l) (opt (layer-o l) 'group #f))))

  ;; Global settings needed by the kinds of layers present.
  (define (layer-settings layers levels)
    (let ([kinds (map layer-kind layers)])
      (append
       (if levels (category-xtics levels) '())
       (if (memq 'boxplot kinds)
           '("set style boxplot outliers pointtype 7")
           '())
       (if (or (memq 'bars kinds) (memq 'histogram kinds))
           ;; leave room above the tallest bar, and start bars from zero
           ;; when nothing is negative, which autoscaling does not ensure
           (cons "set offsets 0, 0, graph 0.05, 0"
                 (if (for-all (lambda (l)
                                (for-all (lambda (v) (and (real? v) (nonnegative? v)))
                                         (if (layer-y l)
                                             (remove-na ($ (layer-df l) (layer-y l)))
                                             '())))
                              layers)
                     '("set yrange [0:*]")
                     '()))
           '()))))

  ;; An element is one datablock plus the plot clause that draws it:
  ;; (columns spec title), where title is a key entry or #f.
  (define (layer-elements l levels group-labels)
    (let* ([o (layer-o l)]
           [groups (split-groups (layer-df l) (opt o 'group #f))]
           [->x (if levels
                    (lambda (v) (if (na? v) v (index-of (->label v) levels)))
                    values)]
           [color (lambda (g)
                    (let ([c (opt o 'color #f)])
                      (if c
                          (string-append "lc rgb " (quote-string c))
                          (format "lc ~a" (+ 1 (or (index-of (car g) group-labels) 0))))))]
           [title (lambda (g) (or (car g) (opt o 'label #f)))])
      (case (layer-kind l)
        [(points lines) (xy-elements l groups ->x color title)]
        [(bars) (bar-elements l groups ->x color title)]
        [(histogram) (histogram-elements l groups color title)]
        [(boxplot) (boxplot-elements l groups levels color title)])))

  (define (xy-elements l groups ->x color title)
    (let* ([o (layer-o l)]
           [lines? (eq? (layer-kind l) 'lines)]
           [style (if lines?
                      (format "with ~a lw ~a~a"
                              (if (opt o 'points #f) "linespoints" "lines")
                              (opt o 'linewidth 2)
                              (if (opt o 'points #f) " pt 7" ""))
                      (format "with points pt ~a ps ~a"
                              (opt o 'pointtype 7) (opt o 'pointsize 1)))])
      (map (lambda (g)
             (let* ([sub (cdr g)]
                    [rows (map list (map ->x ($ sub (layer-x l))) ($ sub (layer-y l)))]
                    [rows (if (and lines? (opt o 'sort #t))
                              (sort (lambda (a b) (< (car a) (car b)))
                                    (filter (lambda (r) (not (na? (car r)))) rows))
                              rows)])
               (list (list (map car rows) (map cadr rows))
                     (string-append "using 1:2 " style " " (color g))
                     (title g))))
           groups)))

  (define (bar-elements l groups ->x color title)
    (let* ([k (length groups)]
           [width (/ 0.8 k)])
      (map (lambda (g i)
             (let* ([sub (cdr g)]
                    [pos (map (lambda (v) (+ (->x v) (dodge i k width)))
                              ($ sub (layer-x l)))])
               (list (list pos ($ sub (layer-y l)) (map (lambda (p) width) pos))
                     (string-append "using 1:2:3 with boxes fs solid 0.85 border -1 "
                                    (color g))
                     (title g))))
           groups (iota k))))

  (define (histogram-elements l groups color title)
    (let* ([o (layer-o l)]
           [x (layer-x l)]
           [vals (remove-na ($ (layer-df l) x))]
           [lo (apply min vals)]
           [hi (apply max vals)]
           [width (inexact
                   (or (opt o 'binwidth #f)
                       (if (= lo hi)
                           1
                           (/ (- hi lo) (opt o 'bins (sturges (length vals)))))))]
           [nbins (max 1 (exact (ceiling (/ (- hi lo) width))))]
           [fill (if (> (length groups) 1)
                     "fs transparent solid 0.5 border -1"
                     "fs solid 0.85 border -1")])
      (map (lambda (g)
             (list (list (map (lambda (b) (+ lo (* width (+ b 0.5)))) (iota nbins))
                         (bin-counts (remove-na ($ (cdr g) x)) lo width nbins)
                         (make-list nbins width))
                   (string-append "using 1:2:3 with boxes " fill " " (color g))
                   (title g)))
           groups)))

  (define (boxplot-elements l groups levels color title)
    (let* ([x (layer-x l)]
           [y (layer-y l)]
           [k (length groups)]
           [width (/ 0.6 k)]
           [layer-levels (if x
                             (remove-duplicates (map ->label (remove-na ($ (layer-df l) x))))
                             '(""))])
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
                                     (list
                                      (list ys)
                                      (format "using (~a):1:(~a) with boxplot fs solid 0.5 border -1 ~a"
                                              (fmt (+ (index-of level levels) (dodge i k width)))
                                              (fmt width) (color g))
                                      ;; one key entry per group
                                      (and (= j 0) (title g))))))
                            layer-levels (iota (length layer-levels))))))
                  groups (iota k)))))

  ;;---------------------------------------------------------------------
  ;; Script assembly.

  ;; Assemble the full script: output, layer settings, plot options,
  ;; user commands, datablocks, and the plot command.
  (define (run-script o settings default-xlabel default-ylabel key-title elements)
    (let* ([names (map (lambda (i) (format "$d~a" (+ i 1)))
                       (iota (length elements)))]
           [titles (unique-titles (map caddr elements))]
           [titled? (exists values titles)]
           [output (opt o 'output #f)])
      (send-script
       (append
        (if output (output-commands output (opt o 'size #f)) '())
        settings
        (label-command "title" (opt o 'title #f))
        (label-command "xlabel" (opt o 'xlabel default-xlabel))
        (label-command "ylabel" (opt o 'ylabel default-ylabel))
        (key-commands (opt o 'key (if titled? "outside right top" #f))
                      key-title)
        (if (opt o 'grid #f) '("set grid") '())
        (range-command "xrange" (opt o 'xrange #f))
        (range-command "yrange" (opt o 'yrange #f))
        (logscale-command (opt o 'logscale #f))
        (opt o 'commands '())
        (apply append (map (lambda (name e) (datablock name (car e)))
                           names elements))
        (list
         (string-append
          "plot "
          (join (map (lambda (name e title)
                       (format "~a ~a ~a" name (cadr e)
                               (if title
                                   (string-append "title " (quote-string title))
                                   "notitle")))
                     names elements titles)
                ", ")))
        (if output '("unset output") '())))))

  ;; A label gets one key entry, e.g., when points and lines share a group.
  (define (unique-titles titles)
    (let loop ([titles titles] [seen '()] [acc '()])
      (cond [(null? titles) (reverse acc)]
            [(and (car titles) (not (member (car titles) seen)))
             (loop (cdr titles) (cons (car titles) seen) (cons (car titles) acc))]
            [else (loop (cdr titles) seen (cons #f acc))])))

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

  (define (key-commands key key-title)
    (cond [(not key) '("unset key")]
          [(string? key)
           (cons (string-append "set key " key)
                 (if key-title
                     (list (string-append "set key title "
                                          (quote-string (symbol->string key-title))))
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

  (define (parse-options who opts allowed)
    (let loop ([opts opts] [acc '()])
      (cond [(null? opts) acc]
            [(null? (cdr opts))
             (assertion-violation who "options must be given as name/value pairs" opts)]
            [(not (memq (car opts) allowed))
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

  (define (take-while pred lst)
    (if (and (pair? lst) (pred (car lst)))
        (cons (car lst) (take-while pred (cdr lst)))
        '()))

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
