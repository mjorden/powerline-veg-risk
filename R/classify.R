# Random-forest point classifier with spatially blocked cross-validation.
#
# Neighbouring LiDAR points share neighbourhoods (and therefore near-identical
# eigen features), so random k-fold CV leaks information between train and
# test folds and overstates accuracy. Folds are assigned by square spatial
# block instead; `cv_point_classifier()` reports both schemes so the gap is
# visible.
#
# Everything seeded here is also independent of point order: blocks are
# numbered by their position, and points are sorted by coordinate before any
# subsample is drawn, so re-ordering the tiles reproduces the same folds,
# the same training set and the same model.

#' Assign points to spatial blocks and CV folds
#'
#' With labels on the table, blocks are dealt to folds class by class,
#' rarest class first: the blocks that hold a class are taken largest first
#' and each goes to the fold that so far has the fewest points of that
#' class. A rare class that sits in a handful of blocks (conductor returns
#' along one stretch of line) is then spread over as many folds as it has
#' blocks, instead of landing wherever a shuffle puts it; a purely random
#' deal once left 76% of a site's wire points in one fold and none in
#' another (#63). Blocks that hold only the commonest class are dealt at
#' random, keeping the folds' block counts level. Blocks stay whole, so
#' this does not leak neighbours between folds.
#'
#' @param feat A features table with `X`, `Y`.
#' @param crs CRS of the coordinates; defaults to the one recorded by
#'   [point_features()] and must agree with it when both are given.
#' @param block_m Block edge length in metres.
#' @param n_folds Number of folds.
#' @param seed RNG seed for fold assignment.
#' @param stratify Deal blocks to folds by class presence (see above).
#'   Defaults to `TRUE` when `feat` has a `label` column with more than one
#'   class; `FALSE` gives the purely random deal.
#' @return `feat` with integer columns `block` and `fold`. Block ids are
#'   numbered by position (west to east, then south to north), so they do
#'   not depend on row order.
#' @export
assign_blocks <- function(feat, crs = NULL, block_m = 100, n_folds = 5, seed = 1, stratify = NULL) {
  feat <- data.table::copy(as_point_table(feat))
  crs <- feat_crs(feat, crs)
  m <- crs_m_per_unit(crs)
  b <- block_m / m
  cells <- data.table::data.table(bx = floor(feat$X / b), by = floor(feat$Y / b))
  feat[, block := data.table::frankv(cells, ties.method = "dense")]
  n_blocks <- max(feat$block)
  if (n_blocks < n_folds) rlang::abort("Fewer spatial blocks than folds; reduce `block_m`.")
  has_classes <- "label" %in% names(feat) && length(unique(stats::na.omit(feat$label))) > 1
  if (is.null(stratify)) stratify <- has_classes
  if (stratify && !has_classes) rlang::abort("`stratify = TRUE` needs a `label` column with more than one class.")
  fold_of_block <- if (stratify) {
    stratified_folds(table(block = factor(feat$block, levels = seq_len(n_blocks)),
                           label = droplevels(feat$label)), n_folds, seed)
  } else {
    withr::with_seed(seed, sample(rep_len(seq_len(n_folds), n_blocks)))
  }
  feat[, fold := fold_of_block[block]]
  feat[]
}

# Deal blocks to folds by class presence. `counts` is a blocks x classes
# table of labelled points. Classes are taken rarest first (fewest points);
# the commonest class is not stratified, its blocks are dealt at random to
# the folds with the fewest blocks. Ties are broken by the seeded shuffle,
# never by row order.
stratified_folds <- function(counts, n_folds, seed) {
  counts <- unclass(counts)
  n_blocks <- nrow(counts)
  withr::with_seed(seed, {
    tie <- sample(n_folds)            # fold preference when everything else ties
    shuffle <- sample(n_blocks)       # order of the blocks left to chance
  })
  fold <- rep(NA_integer_, n_blocks)
  load <- matrix(0, n_folds, ncol(counts))
  n_in <- integer(n_folds)
  classes <- order(colSums(counts))
  for (cl in classes[-length(classes)]) {
    todo <- which(is.na(fold) & counts[, cl] > 0)
    todo <- todo[order(-counts[todo, cl], todo)]
    for (b in todo) {
      f <- order(load[, cl], n_in, tie)[1]
      fold[b] <- f
      load[f, ] <- load[f, ] + counts[b, ]
      n_in[f] <- n_in[f] + 1L
    }
  }
  for (b in shuffle[is.na(fold[shuffle])]) {
    f <- order(n_in, tie)[1]
    fold[b] <- f
    n_in[f] <- n_in[f] + 1L
  }
  fold
}

#' Train a random-forest point classifier
#'
#' Vegetation is subsampled to at most `n_per_class` points (it outnumbers
#' the other classes by orders of magnitude); every class is then weighted by
#' the inverse of its training frequency through ranger's `case.weights`, so
#' bootstrap samples are approximately class-balanced. A forest trained that
#' way estimates class posteriors under *equal* priors; the true label
#' prevalence is stored on the model (`$prior`) and [classify_probs()]
#' re-weights posteriors by it, so decisions are made at the site's real
#' class mix rather than flooding the rare classes with false positives.
#'
#' Predictors are the columns [point_features()] recorded (its `features`
#' attribute) minus `drop_features`; a label, a fold id, a joined column or
#' a previous model's `pred` / `p_*` output is never used as a predictor.
#'
#' @param feat Labelled features (from [weak_labels()]).
#' @param n_per_class Maximum training points per class.
#' @param num_trees,mtry Passed to [ranger::ranger()].
#' @param drop_features Feature columns to exclude (for ablation).
#' @param seed RNG seed.
#' @return A `ranger` model (probability forest) with `$prior` (label
#'   prevalence) and `$features` (the predictor names).
#' @export
train_point_classifier <- function(feat, n_per_class = 20000, num_trees = 300,
                                   mtry = NULL, drop_features = NULL, seed = 1) {
  feat <- as_point_table(feat)
  vars <- feature_columns(feat, drop_features)
  train <- capped_sample(feat[!is.na(label)], n_per_class, seed)
  train[, label := droplevels(label)]
  freq <- table(train$label)
  fit <- ranger::ranger(
    x = as.data.frame(train[, vars, with = FALSE]),
    y = train$label,
    case.weights = as.numeric(1 / freq[as.character(train$label)]),
    probability = TRUE, num.trees = num_trees, mtry = mtry,
    importance = "permutation", seed = seed, num.threads = NULL
  )
  # Prevalence among labelled points. Abstained near-line candidates (enriched
  # for wire) are excluded, so the wire prior is, if anything, too low.
  fit$prior <- prop.table(table(droplevels(feat$label[!is.na(feat$label)])))
  fit$features <- vars
  fit
}

#' Prior-corrected class probabilities
#'
#' @param model A model from [train_point_classifier()].
#' @param feat Features table.
#' @return Matrix of class probabilities at the training-set prevalence.
#' @export
classify_probs <- function(model, feat) {
  prior_correct(raw_probs(model, feat), model)
}

# The forest's own class probabilities (equal priors).
raw_probs <- function(model, feat) {
  feat <- as_point_table(feat)
  vars <- model$forest$independent.variable.names
  missing <- setdiff(vars, names(feat))
  if (length(missing)) {
    rlang::abort(sprintf("`feat` lacks predictor column(s) the model was trained on: %s",
                         paste(missing, collapse = ", ")))
  }
  stats::predict(model, as.data.frame(feat[, vars, with = FALSE]))$predictions
}

prior_correct <- function(p, model) {
  p <- sweep(p, 2, as.numeric(model$prior[colnames(p)]), `*`)
  p / rowSums(p)
}

#' Cross-validate the point classifier: spatial blocks vs random folds
#'
#' Every held-out non-vegetation point is scored; vegetation is scored on a
#' random `eval_veg_frac` sample and up-weighted by its inverse, so precision
#' is estimated at the site's real class prevalence. Two threshold-free
#' summaries are added: per-class average precision (area under the
#' precision-recall curve; compare it with `prevalence`, its no-skill value)
#' and balanced accuracy (mean per-class recall of the argmax decision).
#'
#' The pooled figures put the held-out points of every fold in one table,
#' although each fold was scored by its own model. A rare class can sit
#' almost entirely in one fold, and the pooled average precision is then
#' that fold's result with the others as noise. `fold_metrics` reports each
#' fold on its own, and `metrics` carries the spread (`ap_fold_min`,
#' `ap_fold_median`, `ap_fold_max`) over the folds that hold at least
#' `min_fold_n` points of the class on both the training and the held-out
#' side (`n_folds_scored`). Read a pooled figure together with its spread
#' and with how many folds stand behind it (#63).
#'
#' @param feat Labelled features with `fold` (from [assign_blocks()]).
#' @param eval_veg_frac Fraction of held-out vegetation points scored.
#' @param random Also run random k-fold CV for comparison.
#' @param min_fold_n A fold counts towards a class's spread only with at
#'   least this many points of the class in training and held out.
#' @param oof Also return the spatial out-of-fold prediction of *every* row
#'   of `feat`, labelled or not: each point is classified by the model that
#'   never saw its block. That is the prediction to score against an
#'   independent reference; scoring the final model on the points it was
#'   trained on is in-sample.
#' @inheritParams train_point_classifier
#' @return A list with `metrics` (one row per scheme and class: `n`
#'   estimated held-out points, `prevalence`, `precision`, `recall`, `f1`,
#'   `avg_precision`, all pooled over folds, then `n_folds_scored`,
#'   `ap_fold_min`, `ap_fold_median`, `ap_fold_max`), `fold_metrics` (one
#'   row per scheme, fold and class: `n_train`, `n_test`, `prevalence`,
#'   `recall`, `avg_precision`, `scored`; a class absent from a fold's
#'   held-out points has `n_test = 0`), `summary` (one row per scheme:
#'   `balanced_accuracy`, `n_eval`), `confusion` (spatial-CV confusion
#'   matrix in estimated point counts, rows = weak label, columns =
#'   prediction), `fold_counts` (labelled points per spatial fold) and, with
#'   `oof = TRUE`, `oof` (a data frame in the row order of `feat`: `fold`,
#'   `pred`, and `p_wire_raw`, the forest's wire probability before the
#'   prior correction).
#' @export
cv_point_classifier <- function(feat, n_per_class = 20000, num_trees = 200, mtry = NULL,
                                drop_features = NULL, eval_veg_frac = 0.1, random = TRUE,
                                seed = 1, min_fold_n = 20, oof = FALSE) {
  feat <- as_point_table(feat)
  lab <- stable_order(feat[!is.na(label)])
  oof_out <- NULL
  if (oof) {
    oof_out <- data.frame(fold = feat$fold, pred = factor(NA_character_, levels = label_levels),
                          p_wire_raw = NA_real_)
  }
  run <- function(fold_col, scheme, keep_oof = FALSE) {
    n_f <- max(lab[[fold_col]])
    preds <- vector("list", n_f)
    folds <- vector("list", n_f)
    for (f in seq_len(n_f)) {
      tr <- lab[lab[[fold_col]] != f]
      te <- lab[lab[[fold_col]] == f]
      n_train <- table(factor(tr$label, levels = label_levels))
      n_test <- table(factor(te$label, levels = label_levels))
      folds[[f]] <- data.frame(scheme = scheme, fold = f, class = label_levels,
                               n_train = as.integer(n_train), n_test = as.integer(n_test),
                               prevalence = as.numeric(n_test) / max(nrow(te), 1),
                               recall = NA_real_, avg_precision = NA_real_)
      veg <- which(te$label == "vegetation")
      keep <- withr::with_seed(seed + f, c(which(te$label != "vegetation"),
                                           veg[stats::runif(length(veg)) < eval_veg_frac]))
      te <- te[keep]
      rows <- if (keep_oof) which(feat$fold == f) else integer()
      if (nrow(te) == 0 && length(rows) == 0) next
      fit <- train_point_classifier(tr, n_per_class, num_trees, mtry, drop_features, seed + f)
      if (length(rows)) {
        raw <- raw_probs(fit, feat[rows])
        p <- prior_correct(raw, fit)
        oof_out$pred[rows] <<- factor(colnames(p)[max.col(p, "first")], levels = label_levels)
        oof_out$p_wire_raw[rows] <<- if ("wire" %in% colnames(raw)) raw[, "wire"] else 0
      }
      if (nrow(te) == 0) next
      p <- classify_probs(fit, te)
      full <- matrix(0, nrow(p), length(label_levels), dimnames = list(NULL, label_levels))
      full[, colnames(p)] <- p
      preds[[f]] <- data.frame(
        truth = te$label,
        pred = factor(colnames(p)[max.col(p, "first")], levels = label_levels),
        w = ifelse(te$label == "vegetation", 1 / eval_veg_frac, 1),
        p = full
      )
      fm <- class_metrics(preds[[f]], scheme)
      at <- match(fm$class, folds[[f]]$class)
      folds[[f]]$recall[at] <- fm$recall
      folds[[f]]$avg_precision[at] <- fm$avg_precision
    }
    folds <- do.call(rbind, folds)
    folds <- folds[folds$class %in% levels(droplevels(lab$label)), ]
    folds$scored <- folds$n_train >= min_fold_n & folds$n_test >= min_fold_n
    list(preds = do.call(rbind, preds), folds = folds)
  }
  # Pooled metrics with the per-fold spread beside them.
  with_spread <- function(res, scheme) {
    m <- class_metrics(res$preds, scheme)
    ok <- res$folds[res$folds$scored & !is.na(res$folds$avg_precision), ]
    by <- split(ok$avg_precision, factor(ok$class, levels = m$class))
    m$n_folds_scored <- lengths(by)
    stat <- function(fun) vapply(by, function(x) if (length(x)) fun(x) else NA_real_, 0)
    m$ap_fold_min <- stat(min)
    m$ap_fold_median <- stat(stats::median)
    m$ap_fold_max <- stat(max)
    m
  }

  withr::with_seed(seed, lab[, random_fold := sample(rep_len(seq_len(max(fold)), .N))])
  sp <- run("fold", "spatial_block", keep_oof = oof)
  spatial <- sp$preds
  metrics <- with_spread(sp, "spatial_block")
  fold_metrics <- sp$folds
  summary <- scheme_summary(spatial, "spatial_block")
  if (random) {
    rn <- run("random_fold", "random")
    metrics <- rbind(metrics, with_spread(rn, "random"))
    fold_metrics <- rbind(fold_metrics, rn$folds)
    summary <- rbind(summary, scheme_summary(rn$preds, "random"))
  }
  rownames(metrics) <- rownames(fold_metrics) <- NULL
  out <- list(
    metrics = metrics,
    fold_metrics = fold_metrics,
    summary = summary,
    confusion = round(stats::xtabs(w ~ truth + pred, spatial)),
    fold_counts = table(fold = lab$fold, label = droplevels(lab$label))
  )
  if (oof) out$oof <- oof_out
  out
}

#' Classify all featurised points
#'
#' @param model A model from [train_point_classifier()].
#' @param feat Features table.
#' @return `feat` with `pred` (factor) and one `p_<class>` probability column
#'   for every class in `label_levels` (prior-corrected, see
#'   [classify_probs()]); classes absent from training get probability 0.
#' @export
predict_points <- function(model, feat) {
  feat <- data.table::copy(as_point_table(feat))
  p <- classify_probs(model, feat)
  for (cl in label_levels) {
    feat[, (paste0("p_", cl)) := if (cl %in% colnames(p)) p[, cl] else 0]
  }
  feat[, pred := factor(colnames(p)[max.col(p, "first")], levels = label_levels)]
  feat[]
}

# Seeded per-class subsample, drawn from a coordinate-sorted table so the
# result does not depend on the order the points arrived in.
capped_sample <- function(dt, n_per_class, seed) {
  dt <- stable_order(dt)
  withr::with_seed(seed, dt[, .SD[sample(.N, min(.N, n_per_class))], by = label])
}

# Weighted per-class metrics; `w` estimates point counts at true prevalence.
class_metrics <- function(df, scheme) {
  if (is.null(df$w)) df$w <- 1
  cls <- intersect(label_levels, as.character(unique(df$truth)))
  do.call(rbind, lapply(cls, function(cl) {
    tp <- sum(df$w[df$truth == cl & df$pred == cl])
    fp <- sum(df$w[df$truth != cl & df$pred == cl])
    fn <- sum(df$w[df$truth == cl & df$pred != cl])
    prec <- if (tp + fp > 0) tp / (tp + fp) else NA_real_
    rec  <- if (tp + fn > 0) tp / (tp + fn) else NA_real_
    pcol <- paste0("p.", cl)
    data.frame(scheme = scheme, class = cl, n = round(tp + fn),
               prevalence = (tp + fn) / sum(df$w),
               precision = prec, recall = rec,
               f1 = if (is.na(prec) || is.na(rec) || prec + rec == 0) NA_real_ else 2 * prec * rec / (prec + rec),
               avg_precision = if (pcol %in% names(df)) avg_precision(df[[pcol]], df$truth == cl, df$w) else NA_real_)
  }))
}

# One row per evaluation: the scalars that belong to the scheme, not to a
# class, so they are never averaged over class rows by mistake.
scheme_summary <- function(df, scheme) {
  if (is.null(df$w)) df$w <- 1
  per_class <- class_metrics(df, scheme)
  data.frame(scheme = scheme, balanced_accuracy = mean(per_class$recall, na.rm = TRUE),
             n_eval = round(sum(df$w)))
}

# Weighted average precision evaluated at distinct score thresholds: tied
# scores enter together, so row order cannot inflate the result.
avg_precision <- function(score, positive, w = rep(1, length(score))) {
  g <- factor(-score)
  tp <- tapply(w * positive, g, sum)
  tot <- tapply(w, g, sum)
  prec <- cumsum(tp) / cumsum(tot)
  sum(tp * prec) / sum(tp)
}

#' Score labels against vendor-delivered ASPRS classes
#'
#' Some 3DEP deliveries classify vegetation (ASPRS 3-5) and buildings (6).
#' Those vendor classes are independent of this package's weak labels, so
#' they provide a ground-truth check for the classes they cover. Only points
#' whose vendor class is in `map` are scored; vendor "unclassified" points
#' are excluded. Vegetation usually dominates (prevalence near 1), so its F1
#' cannot show skill: an always-"vegetation" baseline is reported alongside,
#' with balanced accuracy and Cohen's kappa over the mapped classes. A class
#' that is never predicted has precision 0, not NA. A class with no vendor
#' points (e.g. no buildings on a rural corridor) has `n = 0` and `NA` recall
#' and F1, and is left out of balanced accuracy.
#'
#' @param labels Factor of labels to score (e.g. `pred$pred` or `feat$label`).
#' @param vendor_class Integer ASPRS class of the same points; must have the
#'   same length as `labels`.
#' @param map Named list mapping package labels to vendor class codes.
#' @return A list with `metrics` (one row per mapped class: `n`,
#'   `prevalence`, `predicted`, `precision`, `recall`, `f1`), `summary` (one
#'   row: `n` points scored, `balanced_accuracy`, `kappa`), `baseline` (a
#'   list with the same `metrics` and `summary` for predicting the majority
#'   class everywhere) and `confusion`. With no points in a mapped vendor
#'   class, every metric is `NA` (with a warning).
#' @export
evaluate_vendor_classes <- function(labels, vendor_class,
                                    map = list(vegetation = 3:5, building = 6L)) {
  if (length(labels) != length(vendor_class)) {
    rlang::abort(sprintf("`labels` (%d) and `vendor_class` (%d) must have the same length.",
                         length(labels), length(vendor_class)))
  }
  truth <- rep(NA_character_, length(vendor_class))
  for (nm in names(map)) truth[vendor_class %in% map[[nm]]] <- nm
  keep <- !is.na(truth)
  lab <- as.character(labels[keep])
  lab[is.na(lab)] <- "(unlabelled)"
  truth <- truth[keep]
  score <- function(pred) {
    out <- do.call(rbind, lapply(names(map), function(cl) {
      tp <- sum(truth == cl & pred == cl)
      np <- sum(pred == cl)
      nt <- sum(truth == cl)
      prec <- if (np > 0) tp / np else if (nt > 0) 0 else NA_real_
      rec <- if (nt > 0) tp / nt else NA_real_
      data.frame(class = cl, n = nt, prevalence = if (length(truth)) nt / length(truth) else NA_real_,
                 predicted = np, precision = prec, recall = rec,
                 f1 = if (is.na(rec)) NA_real_ else if (prec + rec > 0) 2 * prec * rec / (prec + rec) else 0)
    }))
    # Cohen's kappa over the mapped classes, other predictions counting as wrong
    po <- mean(pred == truth)
    pe <- sum(vapply(names(map), function(cl) mean(truth == cl) * mean(pred == cl), 0))
    summary <- data.frame(
      n = length(truth),
      balanced_accuracy = if (any(!is.na(out$recall))) mean(out$recall, na.rm = TRUE) else NA_real_,
      kappa = if (length(truth) && pe < 1) (po - pe) / (1 - pe) else NA_real_
    )
    list(metrics = out, summary = summary)
  }
  if (length(truth) == 0) {
    rlang::warn("No points have a vendor class in `map`; every metric is NA.")
  }
  majority <- if (length(truth)) names(which.max(table(truth))) else character()
  ours <- score(lab)
  list(metrics = ours$metrics, summary = ours$summary,
       baseline = score(rep(majority, length(truth))),
       confusion = table(vendor = truth, label = lab))
}
