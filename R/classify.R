# Random-forest point classifier with spatially blocked cross-validation.
#
# Neighbouring LiDAR points share neighbourhoods (and therefore near-identical
# eigen features), so random k-fold CV leaks information between train and
# test folds and overstates accuracy. Folds are assigned by square spatial
# block instead; `cv_point_classifier()` reports both schemes so the gap is
# visible.

#' Assign points to spatial blocks and CV folds
#'
#' @param feat A features table with `X`, `Y`.
#' @param crs CRS of the coordinates.
#' @param block_m Block edge length in metres.
#' @param n_folds Number of folds.
#' @param seed RNG seed for fold assignment.
#' @return `feat` with integer columns `block` and `fold`.
#' @export
assign_blocks <- function(feat, crs, block_m = 100, n_folds = 5, seed = 1) {
  m <- crs_m_per_unit(crs)
  feat <- data.table::copy(feat)
  b <- block_m / m
  key <- paste(floor(feat$X / b), floor(feat$Y / b))
  feat[, block := match(key, unique(key))]
  n_blocks <- max(feat$block)
  if (n_blocks < n_folds) rlang::abort("Fewer spatial blocks than folds; reduce `block_m`.")
  withr::with_seed(seed, fold_of_block <- sample(rep_len(seq_len(n_folds), n_blocks)))
  feat[, fold := fold_of_block[block]]
  feat[]
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
#' @param feat Labelled features (from [weak_labels()]).
#' @param n_per_class Maximum training points per class.
#' @param num_trees,mtry Passed to [ranger::ranger()].
#' @param drop_features Feature columns to exclude (for ablation).
#' @param seed RNG seed.
#' @return A `ranger` model (probability forest).
#' @export
train_point_classifier <- function(feat, n_per_class = 20000, num_trees = 300,
                                   mtry = NULL, drop_features = NULL, seed = 1) {
  train <- capped_sample(feat[!is.na(label)], n_per_class, seed)
  train[, label := droplevels(label)]
  freq <- table(train$label)
  fit <- ranger::ranger(
    x = as.data.frame(train[, feature_columns(train, drop_features), with = FALSE]),
    y = train$label,
    case.weights = as.numeric(1 / freq[as.character(train$label)]),
    probability = TRUE, num.trees = num_trees, mtry = mtry,
    importance = "permutation", seed = seed, num.threads = NULL
  )
  # Prevalence among labelled points. Abstained near-line candidates (enriched
  # for wire) are excluded, so the wire prior is, if anything, too low.
  fit$prior <- prop.table(table(droplevels(feat$label[!is.na(feat$label)])))
  fit
}

#' Prior-corrected class probabilities
#'
#' @param model A model from [train_point_classifier()].
#' @param feat Features table.
#' @return Matrix of class probabilities at the training-set prevalence.
#' @export
classify_probs <- function(model, feat) {
  vars <- model$forest$independent.variable.names
  p <- stats::predict(model, as.data.frame(feat[, vars, with = FALSE]))$predictions
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
#' @param feat Labelled features with `fold` (from [assign_blocks()]).
#' @param eval_veg_frac Fraction of held-out vegetation points scored.
#' @inheritParams train_point_classifier
#' @return A list with `metrics` (per-class precision / recall / F1 and
#'   balanced accuracy for each scheme), `confusion` (spatial-CV confusion
#'   matrix in estimated point counts, rows = weak label, columns =
#'   prediction) and `fold_counts` (labelled points per spatial fold).
#' @export
cv_point_classifier <- function(feat, n_per_class = 20000, num_trees = 200, mtry = NULL,
                                drop_features = NULL, eval_veg_frac = 0.1, seed = 1) {
  lab <- feat[!is.na(label)]
  run <- function(fold_col) {
    preds <- vector("list", max(lab[[fold_col]]))
    for (f in seq_along(preds)) {
      tr <- lab[lab[[fold_col]] != f]
      te <- lab[lab[[fold_col]] == f]
      veg <- which(te$label == "vegetation")
      keep <- withr::with_seed(seed + f, c(which(te$label != "vegetation"),
                                           veg[stats::runif(length(veg)) < eval_veg_frac]))
      te <- te[keep]
      if (nrow(te) == 0) next
      fit <- train_point_classifier(tr, n_per_class, num_trees, mtry, drop_features, seed + f)
      p <- classify_probs(fit, te)
      full <- matrix(0, nrow(p), length(label_levels), dimnames = list(NULL, label_levels))
      full[, colnames(p)] <- p
      preds[[f]] <- data.frame(
        truth = te$label,
        pred = factor(colnames(p)[max.col(p, "first")], levels = label_levels),
        w = ifelse(te$label == "vegetation", 1 / eval_veg_frac, 1),
        p = full
      )
    }
    do.call(rbind, preds)
  }

  withr::with_seed(seed, lab[, random_fold := sample(rep_len(seq_len(max(fold)), .N))])
  spatial <- run("fold")
  random <- run("random_fold")
  list(
    metrics = rbind(class_metrics(spatial, "spatial_block"), class_metrics(random, "random")),
    confusion = round(stats::xtabs(w ~ truth + pred, spatial)),
    fold_counts = table(fold = lab$fold, label = droplevels(lab$label))
  )
}

#' Classify all featurised points
#'
#' @param model A model from [train_point_classifier()].
#' @param feat Features table.
#' @return `feat` with `pred` (factor) and one `p_<class>` probability column
#'   per class (prior-corrected, see [classify_probs()]).
#' @export
predict_points <- function(model, feat) {
  feat <- data.table::copy(feat)
  p <- classify_probs(model, feat)
  for (cl in colnames(p)) feat[, (paste0("p_", cl)) := p[, cl]]
  feat[, pred := factor(colnames(p)[max.col(p, "first")], levels = label_levels)]
  feat[]
}

capped_sample <- function(dt, n_per_class, seed) {
  withr::with_seed(seed, dt[, .SD[sample(.N, min(.N, n_per_class))], by = label])
}

# Weighted per-class metrics; `w` estimates point counts at true prevalence.
class_metrics <- function(df, scheme) {
  if (is.null(df$w)) df$w <- 1
  cls <- intersect(label_levels, as.character(unique(df$truth)))
  out <- do.call(rbind, lapply(cls, function(cl) {
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
  out$balanced_accuracy <- mean(out$recall, na.rm = TRUE)
  out
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
