utm <- sf::st_crs(26913)

# A labelled features table built by hand, with the attributes
# point_features() would record.
toy_feat <- function(n = 300, seed = 3) {
  set.seed(seed)
  feat <- data.table::data.table(
    pid = seq_len(2 * n), X = runif(2 * n, 0, 500), Y = runif(2 * n, 0, 500), Z = 0,
    a = c(stats::rnorm(n, 0), stats::rnorm(n, 3)),
    b = stats::runif(2 * n),
    label = factor(rep(c("vegetation", "structure"), each = n), levels = label_levels)
  )
  attr(feat, "crs") <- utm
  attr(feat, "k") <- 10L
  attr(feat, "features") <- c("a", "b")
  feat
}

test_that("predictors come from the recorded allow-list, never from model output (#18)", {
  feat <- toy_feat()
  model <- train_point_classifier(feat, num_trees = 20)
  expect_setequal(model$forest$independent.variable.names, c("a", "b"))
  expect_equal(model$features, c("a", "b"))

  # Retraining on predict_points() output: pred / p_* must not leak in.
  pred <- predict_points(model, feat)
  pred$line_id <- 1L  # a joined column is not a feature either
  again <- train_point_classifier(pred, num_trees = 20)
  expect_setequal(again$forest$independent.variable.names, c("a", "b"))

  # Without the attribute (a hand-built table) the deny-list still drops
  # model output.
  bare <- data.table::copy(pred)
  attr(bare, "features") <- NULL
  bare$line_id <- NULL
  third <- train_point_classifier(bare, num_trees = 20)
  expect_setequal(third$forest$independent.variable.names, c("a", "b"))

  # A recorded feature that has gone missing is an error, not a smaller model.
  broken <- data.table::copy(feat)[, b := NULL]
  expect_error(train_point_classifier(broken, num_trees = 20), "missing feature column")
  expect_error(classify_probs(model, broken), "lacks predictor")
})

test_that("the attributes survive labelling, blocking and prediction", {
  feat <- toy_feat()
  b <- assign_blocks(feat, block_m = 100, n_folds = 5)  # crs from the attribute
  expect_equal(attr(b, "features"), c("a", "b"))
  expect_equal(sf::st_crs(attr(b, "crs")), utm)
  model <- train_point_classifier(b, num_trees = 20)
  p <- predict_points(model, b)
  expect_equal(attr(p, "k"), 10L)
  expect_equal(attr(p, "features"), c("a", "b"))
})

test_that("a CRS that disagrees with the features table is refused (#20)", {
  feat <- toy_feat()
  expect_error(assign_blocks(feat, sf::st_crs(2232), block_m = 100), "differs from the CRS")
  bare <- toy_feat()
  attr(bare, "crs") <- NULL
  expect_error(assign_blocks(bare, block_m = 100), "`crs` is missing")
  expect_silent(assign_blocks(bare, utm, block_m = 100))
})

test_that("exported entry points accept a data.frame (#20)", {
  feat <- toy_feat()
  df <- as.data.frame(feat)
  b_dt <- assign_blocks(feat, block_m = 100)
  b_df <- assign_blocks(df, utm, block_m = 100)
  expect_equal(b_df$fold, b_dt$fold)
  model <- train_point_classifier(as.data.frame(b_dt), num_trees = 20)
  expect_s3_class(model, "ranger")
  p_df <- predict_points(model, as.data.frame(b_dt))
  p_dt <- predict_points(model, b_dt)
  expect_equal(p_df$pred, p_dt$pred)
  expect_true(data.table::is.data.table(p_df))
  expect_error(predict_points(model, as.matrix(b_dt[, c("a", "b")])), "data.frame")
})

test_that("folds, training sets and CV metrics do not depend on row order (#22)", {
  feat <- toy_feat()
  shuffled <- feat[sample(nrow(feat))]
  b1 <- assign_blocks(feat, block_m = 100, n_folds = 5)
  b2 <- assign_blocks(shuffled, block_m = 100, n_folds = 5)
  expect_equal(b2$block[order(b2$pid)], b1$block[order(b1$pid)])
  expect_equal(b2$fold[order(b2$pid)], b1$fold[order(b1$pid)])
  # Block ids are positional: the south-west-most block is 1.
  expect_equal(b1$block[which.min(floor(b1$X / 100) * 1e6 + floor(b1$Y / 100))], 1L)

  m1 <- train_point_classifier(b1, n_per_class = 50, num_trees = 20)
  m2 <- train_point_classifier(b2, n_per_class = 50, num_trees = 20)
  expect_equal(m1$prediction.error, m2$prediction.error)
  expect_equal(m1$variable.importance, m2$variable.importance)

  cv1 <- cv_point_classifier(b1, n_per_class = 50, num_trees = 20, random = FALSE)
  cv2 <- cv_point_classifier(b2, n_per_class = 50, num_trees = 20, random = FALSE)
  expect_equal(cv1$metrics, cv2$metrics)
  expect_equal(cv1$confusion, cv2$confusion)
})

test_that("cv_point_classifier keeps scheme-level scalars apart from class rows (#22)", {
  b <- assign_blocks(toy_feat(), block_m = 100, n_folds = 5)
  cv <- cv_point_classifier(b, n_per_class = 50, num_trees = 20)
  expect_false("balanced_accuracy" %in% names(cv$metrics))
  expect_setequal(cv$summary$scheme, c("spatial_block", "random"))
  expect_equal(nrow(cv$summary), 2)
  expect_true(all(cv$summary$balanced_accuracy >= 0 & cv$summary$balanced_accuracy <= 1))
  expect_true(all(c("n", "prevalence", "avg_precision") %in% names(cv$metrics)))
  for (s in cv$summary$scheme) {
    rows <- cv$metrics[cv$metrics$scheme == s, ]
    expect_equal(cv$summary$balanced_accuracy[cv$summary$scheme == s], mean(rows$recall, na.rm = TRUE))
  }
})

test_that("the conductor-return test names its linearity column from k, or aborts (#18)", {
  skip_if_not_installed("lidR")
  x0 <- 500000
  y0 <- 4400000
  g <- expand.grid(X = x0 + seq(0, 40, 0.5), Y = y0 + seq(-10, 10, 0.5))
  ground <- data.frame(g, Z = 0, Classification = 2L)
  wire <- data.frame(X = x0 + seq(0, 40, 0.25), Y = y0, Z = 12, Classification = 1L)
  pts <- rbind(ground, wire)
  pts$ReturnNumber <- 1L
  pts$NumberOfReturns <- 1L
  pts$Intensity <- 100L
  las <- lidR::LAS(data.table::as.data.table(pts), crs = utm)
  las <- lidR::normalize_height(las, lidR::tin())
  ag <- which(las$Classification != 2L)
  pred <- data.table::data.table(pid = ag, X = las$X[ag], Y = las$Y[ag], height_m = las$Z[ag],
                                 pred = factor("vegetation", levels = label_levels),
                                 label = factor("vegetation", levels = label_levels),
                                 linearity_k15 = 0.95)
  ln <- sf::st_sf(geometry = sf::st_sfc(sf::st_linestring(rbind(c(x0, y0), c(x0 + 40, y0))), crs = utm))
  prof <- line_vertex_table(segment_lines(ln, utm, seg_m = 20), utm)
  prof$seg_id <- 1L
  prof$ground <- 0
  prof$z_lo <- prof$z_hi <- 12
  prof$src <- "measured"

  # k = c(15, 30) recorded on the table: the k15 column is found by name.
  data.table::setattr(pred, "k", c(15L, 30L))
  r <- corridor_rasters(las, pred, profile = prof, envelope_m = 5)
  expect_equal(r$n_conductor_excluded, nrow(wire))
  # Hand-built table with no k: the default column is missing, so abort
  # rather than silently treating every return as non-linear.
  data.table::setattr(pred, "k", NULL)
  expect_error(corridor_rasters(las, pred, profile = prof, envelope_m = 5), "linearity_k10")
  # Partial matching is not an option: k = 100 would once have matched k10.
  pred[, linearity_k100 := linearity_k15]
  expect_error(corridor_rasters(las, pred, profile = prof, envelope_m = 5, linearity = "linearity_k1"),
               "linearity_k1")
  expect_silent(corridor_rasters(las, pred, profile = prof, envelope_m = 5, linearity = "linearity_k100"))
})

# A table whose rare class sits in a few blocks along one line, as conductor
# returns do: 5 x 5 blocks of 100 m, vegetation everywhere, wire in the six
# blocks of the row y in [200, 300) plus one more.
clustered_feat <- function(seed = 7) {
  set.seed(seed)
  n <- 2500
  veg <- data.table::data.table(X = runif(n, 0, 500), Y = runif(n, 0, 500), a = stats::rnorm(n, 0), b = stats::runif(n))
  nw <- c(400, 60, 50, 45, 40, 30)   # one block holds most of it
  wx <- c(50, 150, 250, 350, 450, 50)
  wy <- c(250, 250, 250, 250, 250, 350)
  wire <- data.table::rbindlist(lapply(seq_along(nw), function(i) {
    data.table::data.table(X = wx[i] + runif(nw[i], -40, 40), Y = wy[i] + runif(nw[i], -40, 40),
                           a = stats::rnorm(nw[i], 2.5), b = stats::runif(nw[i]))
  }))
  feat <- rbind(veg[, label := "vegetation"], wire[, label := "wire"])
  feat[, `:=`(pid = .I, Z = 0, label = factor(label, levels = label_levels))]
  # A fifth of the points are unlabelled, as margins and abstentions are.
  feat[sample(.N, .N / 5), label := NA]
  attr(feat, "crs") <- utm
  attr(feat, "k") <- 10L
  attr(feat, "features") <- c("a", "b")
  feat
}

test_that("blocks are dealt to folds by class presence, so a clustered class reaches every fold (#63)", {
  feat <- clustered_feat()
  b <- assign_blocks(feat, block_m = 100, n_folds = 5)
  wire_by_fold <- table(factor(b$fold[b$label %in% "wire"], levels = 1:5))
  expect_true(all(wire_by_fold > 0))                    # six wire blocks, five folds
  # Blocks stay whole, and every fold gets its share of them.
  expect_true(all(tapply(b$fold, b$block, function(x) length(unique(x))) == 1))
  blocks_by_fold <- table(unique(b[, .(block, fold)])$fold)
  expect_lte(max(blocks_by_fold) - min(blocks_by_fold), 1)
  # The biggest wire block is alone among wire blocks in its fold, bar the
  # sixth, which goes to the fold with the least wire.
  big <- b[label %in% "wire", .N, by = .(block, fold)][order(-N)]
  expect_equal(sum(big$fold == big$fold[1]), 1)
  # Same answer whatever the row order; a different deal without labels.
  b2 <- assign_blocks(feat[sample(.N)], block_m = 100, n_folds = 5)
  expect_equal(b2$fold[order(b2$pid)], b$fold[order(b$pid)])
  r <- assign_blocks(feat, block_m = 100, n_folds = 5, stratify = FALSE)
  expect_false(identical(r$fold, b$fold))
  expect_equal(r$fold, assign_blocks(data.table::copy(feat)[, label := NULL], block_m = 100, n_folds = 5)$fold)
  expect_error(assign_blocks(data.table::copy(feat)[, label := NULL], block_m = 100, stratify = TRUE), "label")
})

test_that("cross-validation reports each fold and the spread behind a pooled figure (#63)", {
  b <- assign_blocks(clustered_feat(), block_m = 100, n_folds = 5)
  cv <- cv_point_classifier(b, n_per_class = 200, num_trees = 30, random = FALSE, min_fold_n = 20)
  fm <- cv$fold_metrics
  expect_setequal(names(fm), c("scheme", "fold", "class", "n_train", "n_test", "prevalence", "recall",
                               "avg_precision", "scored"))
  expect_equal(nrow(fm), 5 * 2)                         # five folds, two classes present
  wire <- fm[fm$class == "wire", ]
  lab <- b[!is.na(label)]
  expect_equal(wire$n_test, as.integer(table(factor(lab$fold[lab$label == "wire"], levels = 1:5))))
  expect_equal(wire$n_train + wire$n_test, rep(sum(lab$label == "wire"), 5))
  expect_true(all(wire$scored))
  m <- cv$metrics[cv$metrics$class == "wire", ]
  expect_equal(m$n_folds_scored, 5)
  expect_equal(m$ap_fold_min, min(wire$avg_precision))
  expect_equal(m$ap_fold_median, stats::median(wire$avg_precision))
  expect_equal(m$ap_fold_max, max(wire$avg_precision))
  expect_lte(m$ap_fold_min, m$ap_fold_max)

  # A fold with too few points of a class on either side is reported but
  # does not count towards the spread.
  strict <- cv_point_classifier(b, n_per_class = 200, num_trees = 30, random = FALSE, min_fold_n = 100)
  sw <- strict$fold_metrics[strict$fold_metrics$class == "wire", ]
  expect_equal(sw$scored, sw$n_test >= 100 & sw$n_train >= 100)
  expect_lt(sum(sw$scored), 5)
  expect_equal(strict$metrics$n_folds_scored[strict$metrics$class == "wire"], sum(sw$scored))
  none <- cv_point_classifier(b, n_per_class = 200, num_trees = 30, random = FALSE, min_fold_n = 1e6)
  expect_true(all(none$metrics$n_folds_scored == 0))
  expect_true(all(is.na(none$metrics$ap_fold_median)))
  # The pooled figures do not depend on the threshold.
  expect_equal(strict$metrics$avg_precision, cv$metrics$avg_precision)
})

test_that("out-of-fold predictions cover every point, labelled or not, in the table's order (#63)", {
  b <- assign_blocks(clustered_feat(), block_m = 100, n_folds = 5)
  cv <- cv_point_classifier(b, n_per_class = 200, num_trees = 30, random = FALSE, oof = TRUE)
  expect_equal(nrow(cv$oof), nrow(b))
  expect_equal(cv$oof$fold, b$fold)
  expect_false(anyNA(cv$oof$pred))
  expect_true(all(cv$oof$p_wire_raw >= 0 & cv$oof$p_wire_raw <= 1))
  expect_gt(sum(is.na(b$label)), 0)                     # unlabelled points got one too
  # Each point is scored by the model that never saw its block: refitting
  # fold 2's model by hand reproduces its rows.
  lab <- stable_order(b[!is.na(label)])
  fit2 <- train_point_classifier(lab[fold != 2], 200, 30, NULL, NULL, 1 + 2)
  rows <- which(b$fold == 2)
  expect_equal(cv$oof$p_wire_raw[rows], raw_probs(fit2, b[rows])[, "wire"])
  # Row order does not change a point's prediction.
  sh <- b[sample(.N)]
  cv2 <- cv_point_classifier(sh, n_per_class = 200, num_trees = 30, random = FALSE, oof = TRUE)
  expect_equal(cv2$oof$pred[order(sh$pid)], cv$oof$pred[order(b$pid)])
  # Without oof = TRUE nothing is returned (or computed).
  expect_null(cv_point_classifier(b, n_per_class = 200, num_trees = 30, random = FALSE)$oof)
})
