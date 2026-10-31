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
                dataframe-split
                $
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
    '(title xlabel ylabel key grid xrange yrange logscale output size commands
            facet facet-columns facet-scales))

  (define layer-options '(group color label))

  ;; kind is one of points, lines, bars, histogram, boxplot; o is an alist
  (define-record-type layer
    (fields kind df x y o))

  ;; One datablock plus the plot clause that draws it. columns is a list
  ;; of equal-length value lists, spec is the clause after the datablock
  ;; name (e.g., "using 1:2 with points ..."), and title is a key entry or #f.
  (define-record-type element
    (fields columns spec title))

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
      ;; levels, group colors, and histogram bins come from the full data
      ;; so that they are the same in every facet panel
      (let* ([layers (map with-bin-range layers)]
             [levels (category-levels who layers)]
             [group-labels (remove-duplicates
                            (apply append (map layer-group-labels layers)))]
             [group-names (remove-duplicates
                           (filter values (map (lambda (l) (opt (layer-o l) 'group #f))
                                               layers)))]
             [key-title (and (= (length group-names) 1) (car group-names))]
             [settings (layer-settings layers levels)]
             [first (car layers)]
             [xlabel (if (layer-x first) (symbol->string (layer-x first)) "")]
             [ylabel (if (layer-y first) (symbol->string (layer-y first)) "Count")]
             [elements-of (lambda (layers)
                            (apply append
                                   (map (lambda (l) (layer-elements l levels group-labels))
                                        layers)))])
        (if (opt o 'facet #f)
            (facet-script who o layers levels settings xlabel ylabel key-title
                          elements-of)
            (run-script o settings xlabel ylabel key-title
                        (elements-of layers))))))

  ;; Histogram layers record the range of their full data, so that facet
  ;; panels, which only see a subset, use the same bins.
  (define (with-bin-range l)
    (if (eq? (layer-kind l) 'histogram)
        (let ([vals (remove-na ($ (layer-df l) (layer-x l)))])
          (make-layer 'histogram (layer-df l) (layer-x l) (layer-y l)
                      (cons (cons 'bin-range (cons (apply min vals) (apply max vals)))
                            (layer-o l))))
        l))

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

  ;; Turn a layer into elements, one per group (and per box for boxplots).
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
               (make-element (list (map car rows) (map cadr rows))
                             (string-append "using 1:2 " style " " (color g))
                             (title g))))
           groups)))

  (define (bar-elements l groups ->x color title)
    (let* ([k (length groups)]
           [width (/ 0.8 k)])
      (map (lambda (g i)
             (let* ([sub (cdr g)]
                    ;; rows with a missing x are skipped (written as NaN)
                    [pos (map (lambda (v) (if (na? v) v (+ (->x v) (dodge i k width))))
                              ($ sub (layer-x l)))])
               (make-element (list pos ($ sub (layer-y l)) (map (lambda (p) width) pos))
                             (string-append "using 1:2:3 with boxes fs solid 0.85 border -1 "
                                            (color g))
                             (title g))))
           groups (iota k))))

  (define (histogram-elements l groups color title)
    (let* ([o (layer-o l)]
           [x (layer-x l)]
           [range (opt o 'bin-range #f)]
           [lo (car range)]
           [hi (cdr range)]
           [n (length (remove-na ($ (layer-df l) x)))]
           [width (inexact
                   (or (opt o 'binwidth #f)
                       (if (= lo hi)
                           1
                           (/ (- hi lo) (opt o 'bins (sturges (max n 1)))))))]
           [nbins (max 1 (exact (ceiling (/ (- hi lo) width))))]
           [fill (if (> (length groups) 1)
                     "fs transparent solid 0.5 border -1"
                     "fs solid 0.85 border -1")])
      (map (lambda (g)
             (make-element (list (map (lambda (b) (+ lo (* width (+ b 0.5)))) (iota nbins))
                                 (bin-counts (remove-na ($ (cdr g) x)) lo width nbins)
                                 (make-list nbins width))
                           (string-append "using 1:2:3 with boxes " fill " " (color g))
                           (title g)))
           groups)))

  (define (boxplot-elements l groups levels color title)
    (let* ([x (layer-x l)]
           [y (layer-y l)]
           [k (length groups)]
           [width (/ 0.6 k)])
      (apply append
             (map (lambda (g i)
                    ;; one box per category; rows with a missing x are skipped
                    (let* ([sub (cdr g)]
                           [boxes (if x
                                      (map (lambda (piece)
                                             (cons (car ($ piece x)) piece))
                                           (dataframe-split sub x))
                                      (list (cons "" sub)))]
                           [boxes (filter (lambda (b) (not (na? (car b)))) boxes)]
                           [elements
                            (filter
                             values
                             (map (lambda (b)
                                    (let ([ys (remove-na ($ (cdr b) y))])
                                      (and (pair? ys)
                                           (make-element
                                            (list ys)
                                            (format "using (~a):1:(~a) with boxplot fs solid 0.5 border -1 ~a"
                                                    (fmt (+ (index-of (->label (car b)) levels)
                                                            (dodge i k width)))
                                                    (fmt width) (color g))
                                            #f))))
                                  boxes))])
                      ;; one key entry per group, on its first box
                      (if (pair? elements)
                          (let ([e (car elements)])
                            (cons (make-element (element-columns e) (element-spec e) (title g))
                                  (cdr elements)))
                          '())))
                  groups (iota k)))))

  ;;---------------------------------------------------------------------
  ;; Script assembly.

  ;; Assemble the full script: output, layer settings, plot options,
  ;; user commands, datablocks, and the plot command.
  (define (run-script o settings default-xlabel default-ylabel key-title elements)
    (let* ([names (map (lambda (i) (format "$d~a" (+ i 1)))
                       (iota (length elements)))]
           [titles (unique-titles (map element-title elements))]
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
        (apply append (map (lambda (name e) (datablock name (element-columns e)))
                           names elements))
        (list (plot-command names elements titles '()))
        (if output '("unset output") '())))))

  (define (plot-command names elements titles extra-clauses)
    (if (and (null? elements) (null? extra-clauses))
        "plot NaN notitle"
        (string-append
         "plot "
         (join (append
                (map (lambda (name e title)
                       (format "~a ~a ~a" name (element-spec e)
                               (if title
                                   (string-append "title " (quote-string title))
                                   "notitle")))
                     names elements titles)
                extra-clauses)
               ", "))))

  ;;---------------------------------------------------------------------
  ;; Facets: one panel per value of the facet column, in a multiplot.

  (define (facet-script who o layers levels settings default-xlabel default-ylabel
                        key-title elements-of)
    (let*-values ([(facet-values panels) (facet-panels who o layers elements-of)])
      (let* ([n (length panels)]
             [scales (opt o 'facet-scales 'fixed)]
             [_ (unless (memq scales '(fixed free free-x free-y))
                  (assertion-violation
                   who "facet-scales must be 'fixed, 'free, 'free-x, or 'free-y" scales))]
             [all-elements (apply append panels)]
             [names (map (lambda (i) (format "$d~a" (+ i 1))) (iota (length all-elements)))]
             [panel-names (split-at-lengths names (map length panels))]
             [titles (unique-titles (map element-title all-elements))]
             [key-entries (filter values (map key-entry all-elements titles))]
             [key (opt o 'key (if (pair? key-entries) 'shared #f))]
             [xlabel (opt o 'xlabel default-xlabel)]
             [ylabel (opt o 'ylabel default-ylabel)]
             [layout (compute-facet-layout o n key
                                           (cons (if key-title (symbol->string key-title) "")
                                                 (filter values titles))
                                           xlabel ylabel)]
             [output (opt o 'output #f)])
        (send-script
         (append
          (apply append (map (lambda (name e) (datablock name (element-columns e)))
                             names all-elements))
          settings
          (if (opt o 'grid #f) '("set grid") '())
          (range-command "xrange" (opt o 'xrange #f))
          (range-command "yrange" (opt o 'yrange #f))
          (logscale-command (opt o 'logscale #f))
          (shared-ranges o scales levels names all-elements
                         (facet-layout-panel-width layout)
                         (facet-layout-panel-height layout))
          (opt o 'commands '())
          (if output (output-commands output (opt o 'size #f)) '())
          (list
           "unset key"
           (format "set multiplot layout ~a,~a margins ~a,~a,~a,~a spacing ~a,~a~a"
                   (facet-layout-nrow layout) (facet-layout-ncol layout)
                   (fmt (facet-layout-left layout)) (fmt (facet-layout-right layout))
                   (fmt (facet-layout-bottom layout)) (fmt (facet-layout-top layout))
                   (fmt (facet-layout-xspacing layout)) (fmt (facet-layout-yspacing layout))
                   (let ([title (opt o 'title #f)])
                     (if title (string-append " title " (quote-string title)) ""))))
          ;; the shared legend and axis labels are drawn once, with the last panel
          (apply append
                 (map (lambda (v elements names i)
                        (let ([last? (= i (- n 1))])
                          (append
                           (list (string-append "set title " (quote-string v) " offset 0,-0.5"))
                           (if last?
                               (facet-shared-commands layout key key-title xlabel ylabel)
                               '())
                           (list (plot-command names elements
                                               (map (lambda (e) #f) elements)
                                               (if (and last? key) key-entries '()))))))
                      facet-values panels panel-names (iota n)))
          (list "unset multiplot")
          (if output '("unset output") '()))))))

  ;; Returns the facet values, in order of first appearance, and a list
  ;; with each panel's elements.
  (define (facet-panels who o layers elements-of)
    (let* ([facet (opt o 'facet #f)]
           [faceted (filter (lambda (l) (dataframe-contains? (layer-df l) facet))
                            layers)]
           [_ (when (null? faceted)
                (assertion-violation who "facet column not in any layer" facet))]
           [facet-values (remove-duplicates
                          (apply append
                                 (map (lambda (l) (map ->label ($ (layer-df l) facet)))
                                      faceted)))]
           [pieces (map (lambda (l) (facet-pieces l facet)) layers)])
      (values
       facet-values
       (map (lambda (v)
              (filter (lambda (e) (pair? (car (element-columns e))))
                      (elements-of
                       (filter values (map (lambda (p) (facet-layer p v)) pieces)))))
            facet-values))))

  ;; Facet layout sizes in pixels, estimated for gnuplot's default font.
  ;; They are converted to fractions of the page for the actual page size.

  ;; gnuplot's default page size for png, svg, and interactive windows
  (define default-page-size '(640 480))

  ;; margins around the grid of panels
  (define left-margin-px 60)          ; y tic labels
  (define ylabel-width-px 20)         ; plus the shared y axis label
  (define bottom-margin-px 40)        ; x tic labels
  (define xlabel-height-px 20)        ; plus the shared x axis label
  (define top-margin-px 40)           ; titles of the first row of panels
  (define title-height-px 30)         ; plus the plot title
  (define right-margin-px 20)         ; when there is no shared legend

  ;; shared legend, right of the panels
  (define legend-gap-px 10)           ; between the panels and the legend
  (define legend-base-width-px 70)    ; line or point sample and padding
  (define legend-char-width-px 9)     ; per character of the longest label

  ;; gaps between panels
  (define panel-xspacing-px 60)       ; y tic labels of the panel to the right
  (define panel-yspacing-px 85)       ; x tic labels, plus the title of the panel below

  ;; distance from the page edge to the center of the shared axis labels
  (define axis-label-offset-px 15)

  ;; minimum space per tic mark, used to choose tic spacing for small panels
  (define xtic-spacing-px 45)
  (define ytic-spacing-px 25)

  ;; Positions are fractions of the page ("screen" coordinates in gnuplot),
  ;; except panel-width and panel-height, which are in pixels.
  (define-record-type facet-layout
    (fields nrow ncol left right bottom top xspacing yspacing
            panel-width panel-height
            key-x xlabel-y ylabel-x))

  ;; Panel margins are fixed so that panels line up; the shared legend and
  ;; axis labels go in the space around them.
  (define (compute-facet-layout o n key legend-labels xlabel ylabel)
    (let* ([ncol (opt o 'facet-columns (exact (ceiling (sqrt n))))]
           [nrow (exact (ceiling (/ n ncol)))]
           [size (or (opt o 'size #f) default-page-size)]
           [width (inexact (car size))]
           [height (inexact (cadr size))]
           [px (lambda (p) (/ p width))]
           [py (lambda (p) (/ p height))]
           [legend-chars (apply max (map string-length legend-labels))]
           [left (px (+ left-margin-px
                        (if (equal? ylabel "") 0 ylabel-width-px)))]
           [bottom (py (+ bottom-margin-px
                          (if (equal? xlabel "") 0 xlabel-height-px)))]
           [top (- 1 (py (+ top-margin-px
                            (if (opt o 'title #f) title-height-px 0))))]
           [right (- 1 (px (if (eq? key 'shared)
                               (+ legend-base-width-px
                                  (* legend-char-width-px legend-chars))
                               right-margin-px)))]
           [xspacing (px panel-xspacing-px)]
           [yspacing (py panel-yspacing-px)])
      (make-facet-layout
       nrow ncol left right bottom top xspacing yspacing
       (* width (/ (- right left (* (- ncol 1) xspacing)) ncol))
       (* height (/ (- top bottom (* (- nrow 1) yspacing)) nrow))
       (+ right (px legend-gap-px))
       (py axis-label-offset-px)
       (px axis-label-offset-px))))

  ;; Shared legend and axis labels, centered on the panels.
  (define (facet-shared-commands layout key key-title xlabel ylabel)
    (let ([left (facet-layout-left layout)]
          [right (facet-layout-right layout)]
          [bottom (facet-layout-bottom layout)]
          [top (facet-layout-top layout)])
      (append
       (facet-key-commands key key-title (facet-layout-key-x layout) top)
       (if (equal? xlabel "")
           '()
           (list (format "set label 1001 ~a at screen ~a, ~a center"
                         (quote-string xlabel)
                         (fmt (/ (+ left right) 2)) (fmt (facet-layout-xlabel-y layout)))))
       (if (equal? ylabel "")
           '()
           (list (format "set label 1002 ~a at screen ~a, ~a center rotate by 90"
                         (quote-string ylabel)
                         (fmt (facet-layout-ylabel-x layout)) (fmt (/ (+ bottom top) 2))))))))

  ;; A layer split by the facet column, as (layer . ((label . df) ...)),
  ;; or (layer . #f) if it doesn't have the facet column.
  (define (facet-pieces l facet)
    (cons l
          (and (dataframe-contains? (layer-df l) facet)
               (map (lambda (df) (cons (->label (car ($ df facet))) df))
                    (dataframe-split (layer-df l) facet)))))

  ;; The layer restricted to facet value v, or #f if it has no rows for v.
  ;; Layers without the facet column are drawn in every panel.
  (define (facet-layer pieces v)
    (let ([l (car pieces)])
      (cond [(not (cdr pieces)) l]
            [(assoc v (cdr pieces))
             => (lambda (p)
                  (make-layer (layer-kind l) (cdr p) (layer-x l) (layer-y l) (layer-o l)))]
            [else #f])))

  ;; With fixed scales, plot every panel's data together, discarding the
  ;; output, and use the resulting axis ranges for all panels. The dumb
  ;; terminal is used because the unknown terminal prints a warning.
  ;; Panels are smaller than a full plot, so the tic spacing is also set
  ;; from the shared range to fit the panel size.
  (define (shared-ranges o scales levels names elements panel-width panel-height)
    (let* ([logscale (let ([a (opt o 'logscale #f)]) (if a (symbol->string a) ""))]
           [fix-x? (and (memq scales '(fixed free-y)) (not levels))]
           [fix-y? (memq scales '(fixed free-x))]
           [tics (lambda (axis max-tics)
                   (if (string-index logscale (symbol->string axis))
                       '()
                       (list (format "set ~atics _nice_step(GPVAL_~a_MAX - GPVAL_~a_MIN, ~a)"
                                     axis (axis-name axis) (axis-name axis)
                                     (max 2 (exact (floor max-tics)))))))])
      (if (and (or fix-x? fix-y?) (pair? elements))
          (append
           (list "set terminal push"
                 "set terminal dumb"
                 (string-append "set output " (quote-string (null-device)))
                 (plot-command names elements (map (lambda (e) #f) elements) '())
                 "set output"
                 "set terminal pop"
                 ;; largest of 1, 2, or 5 times a power of 10 giving at most n steps
                 "_nice_m(s) = (s <= 1 ? 1 : s <= 2 ? 2 : s <= 5 ? 5 : 10)"
                 "_nice_p(s) = 10**floor(log10(s))"
                 "_nice_step(r, n) = _nice_m(r / n / _nice_p(r / n)) * _nice_p(r / n)")
           (if fix-x?
               (append (if (opt o 'xrange #f) '() '("set xrange [GPVAL_X_MIN:GPVAL_X_MAX]"))
                       (tics 'x (/ panel-width xtic-spacing-px)))
               '())
           (if fix-y?
               (append (if (opt o 'yrange #f) '() '("set yrange [GPVAL_Y_MIN:GPVAL_Y_MAX]"))
                       (tics 'y (/ panel-height ytic-spacing-px)))
               '()))
          '())))

  (define (axis-name axis)
    (if (eq? axis 'x) "X" "Y"))

  (define (null-device)
    (let ([m (symbol->string (machine-type))])
      (if (string-index m "nt") "NUL" "/dev/null")))

  ;; Legend entry drawn without data, in the style of an element.
  (define (key-entry e title)
    (and title
         (let* ([spec (element-spec e)]
                [style (substring spec (string-index spec "with ") (string-length spec))])
           (format "keyentry ~a title ~a"
                   (string-replace style "with boxplot" "with boxes")
                   (quote-string title)))))

  ;; The shared legend sits right of the panels; a key string instead
  ;; places the legend inside the last panel.
  (define (facet-key-commands key key-title x top)
    (cond [(eq? key 'shared)
           (append
            (list (format "set key at screen ~a, ~a left top"
                          (fmt x) (fmt top)))
            (if key-title
                (list (string-append "set key title "
                                     (quote-string (symbol->string key-title))))
                '()))]
          [else (key-commands key key-title)]))

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

  ;; Returns list of (label . df) in order of first appearance.
  ;; Ungrouped data is a single group with label #f.
  (define (split-groups df group)
    (if (not group)
        (list (cons #f df))
        (map (lambda (sub) (cons (->label (car ($ sub group))) sub))
             (dataframe-split df group))))

  (define (split-at-lengths lst lengths)
    (if (null? lengths)
        '()
        (cons (list-head lst (car lengths))
              (split-at-lengths (list-tail lst (car lengths)) (cdr lengths)))))

  (define (string-index s sub)
    (let ([n (string-length s)] [m (string-length sub)])
      (let loop ([i 0])
        (cond [(> (+ i m) n) #f]
              [(string=? (substring s i (+ i m)) sub) i]
              [else (loop (+ i 1))]))))

  (define (string-replace s old new)
    (let ([i (string-index s old)])
      (if i
          (string-append (substring s 0 i) new
                         (substring s (+ i (string-length old)) (string-length s)))
          s)))

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
