# Figures (ggplot2, in Suggests). Minimal ink: no chart junk, direct labels
# where possible, colour reserved for the classes / risk tiers that matter.

class_colours <- c(vegetation = "#4d7c3a", wire = "#d62728", structure = "#1f3b73",
                   building = "#b08d57", low = "#d9d9c3", ground = "#bdbdbd")
priority_colours <- c(`grow-in` = "#b2182b", `fall-in` = "#ef8a62", none = "#9e9e9e")

theme_vegrisk <- function(base_size = 10) {
  ggplot2::theme_minimal(base_size = base_size) +
    ggplot2::theme(panel.grid.minor = ggplot2::element_blank(),
                   plot.title.position = "plot",
                   plot.title = ggplot2::element_text(face = "bold"),
                   legend.position = "top", legend.justification = "left")
}

#' Map of canopy height, segment priority, and strike trees
#'
#' Segment colour is the canopy area inside the clearance envelope under the
#' pessimistic (lower) conductor bound - where to verify first, not a
#' finding; line type is the confidence (solid =
#' measured conductor or same tier under both bounds, dashed = tier depends
#' on the unknown conductor elevation).
#'
#' @param rasters Output of [corridor_rasters()].
#' @param risk Output of [assess_risk()].
#' @param structures OSM structures (`sf`), optional.
#' @param title Plot title.
#' @param source Data credit shown in the subtitle.
#' @param file Output PNG path, or `NULL` to return the plot.
#' @export
plot_risk_map <- function(rasters, risk, structures = NULL,
                          title = "Vegetation risk along the line",
                          source = "USGS 3DEP LiDAR", file = NULL) {
  rlang::check_installed(c("ggplot2", "scales"))
  chm <- terra::as.data.frame(rasters$chm, xy = TRUE, na.rm = TRUE)
  names(chm)[3] <- "h"
  crs <- sf::st_crs(risk$segments)
  seg <- risk$segments
  seg$certain <- ifelse(seg$confidence == "bound-dependent", "bound-dependent", "measured / robust")
  strike <- risk$trees[risk$trees$strike, ]
  strike$both <- factor(ifelse(strike$strike_lo & strike$strike_hi, "under both bounds", "under one bound"),
                        levels = c("under both bounds", "under one bound"))

  p <- ggplot2::ggplot() +
    ggplot2::geom_raster(data = chm, ggplot2::aes(x, y, fill = h)) +
    ggplot2::scale_fill_gradient(low = "#f4f4ef", high = "#1b4d1b", limits = c(0, 30),
                                 oob = scales::squish, name = "Canopy height (m)") +
    ggplot2::geom_sf(data = seg, ggplot2::aes(colour = encroach_lo_m2, linetype = certain), linewidth = 1.1) +
    ggplot2::scale_colour_gradient(low = "#fee8c8", high = "#b30000",
                                   name = "Canopy in clearance envelope\nif conductor at code minimum (m\u00b2)") +
    ggplot2::scale_linetype_manual(values = c(`measured / robust` = "solid", `bound-dependent` = "22"),
                                   name = NULL) +
    ggplot2::geom_sf(data = strike, ggplot2::aes(shape = both), size = 1.5, stroke = 0.4,
                     fill = "#ffd92f", colour = "black") +
    ggplot2::scale_shape_manual(values = c(`under both bounds` = 21, `under one bound` = 1),
                                name = "Strike trees") +
    ggplot2::labs(title = title,
                  subtitle = sprintf(paste("Potential strike trees: %d if the conductor is at code minimum, %d at the optimistic bound",
                                           "\n%.0f m segments | %s | OSM line geometry"),
                                     sum(risk$trees$strike_lo), sum(risk$trees$strike_hi),
                                     stats::median(seg$length_m), source),
                  x = NULL, y = NULL) +
    ggplot2::coord_sf(crs = crs, datum = crs, expand = FALSE) +
    ggplot2::scale_x_continuous(n.breaks = 3) +
    theme_vegrisk() +
    ggplot2::theme(axis.text = ggplot2::element_text(size = 7), legend.box = "vertical")
  # Tall (north-south) corridors: legend to the side so the map keeps its width.
  bb <- sf::st_bbox(seg)
  tall <- (bb[["ymax"]] - bb[["ymin"]]) > 2 * (bb[["xmax"]] - bb[["xmin"]])
  if (tall) p <- p + ggplot2::theme(legend.position = "right", legend.justification = "top")
  if (!is.null(structures) && nrow(structures) > 0) {
    st <- sf::st_transform(structures, crs)
    st <- st[lengths(sf::st_intersects(st, sf::st_as_sfc(sf::st_bbox(seg)))) > 0, ]
    p <- p + ggplot2::geom_sf(data = st, shape = 3, size = 1.6)
  }
  save_or_return(p, file, if (tall) 9 else 8, if (tall) 10 else 9)
}

#' Ground and conductor profile along the line
#'
#' @param profile Output of [conductor_profile()].
#' @param risk Output of [assess_risk()], optional; strike trees are drawn at
#'   their base elevation.
#' @param attach_m Attachment height used for the upper bound (for the
#'   subtitle).
#' @param file Output PNG path, or `NULL`.
#' @export
plot_profile <- function(profile, risk = NULL, attach_m = NA, file = NULL) {
  rlang::check_installed("ggplot2")
  pr <- profile[profile$line_id == profile$line_id[1], ]
  unknown <- is.infinite(pr$z_hi)
  pr$z_hi[unknown] <- NA
  meas <- pr[pr$src == "measured", ]
  p <- ggplot2::ggplot(pr, ggplot2::aes(s_m)) +
    ggplot2::geom_ribbon(ggplot2::aes(ymin = z_lo, ymax = z_hi), fill = "#d62728", alpha = 0.18,
                         na.rm = TRUE) +
    ggplot2::geom_line(ggplot2::aes(y = z_lo), colour = "#d62728", linewidth = 0.3, na.rm = TRUE) +
    ggplot2::geom_line(ggplot2::aes(y = ground), colour = "grey35") +
    ggplot2::geom_point(data = meas, ggplot2::aes(y = z_lo), colour = "#d62728", size = 0.8) +
    ggplot2::annotate("text", x = max(pr$s_m), y = pr$ground[nrow(pr)], label = "ground",
                      hjust = 1.05, vjust = 1.6, size = 3, colour = "grey35") +
    ggplot2::labs(title = sprintf("Conductor elevation: measured along %.0f%% of the line, bounded elsewhere",
                                  100 * mean(pr$src == "measured")),
                  subtitle = paste0("Band: ground + NESC clearance (thin line) up to the chord between supports",
                                    if (!is.na(attach_m)) sprintf(" at ground + %g m", attach_m) else "", ".\n",
                                    "No band = next support outside the data. Dots = measured conductor returns."),
                  x = "Distance along line (m)", y = "Elevation (m, NAVD88)") +
    theme_vegrisk()
  save_or_return(p, file, 8, 3.8)
}

#' Cross-section of classified points perpendicular to the line
#'
#' @param las Height-normalised `LAS`.
#' @param pred Output of [predict_points()].
#' @param lines Corridor lines (`sf`, same CRS as `las`).
#' @param file Output PNG path, or `NULL`.
#' @param at Fraction along the line at which to cut the section.
#' @param width_m Slab thickness (metres, along the line).
#' @param half_len_m Section half-length (metres, across the line).
#' @export
plot_cross_section <- function(las, pred, lines, file = NULL, at = 0.5,
                               width_m = 4, half_len_m = 40) {
  rlang::check_installed("ggplot2")
  m <- las_m_per_unit(las)
  ln <- merge_lines(sf::st_geometry(lines))[1]
  p0 <- sf::st_coordinates(sf::st_line_sample(ln, sample = at))[1, 1:2]
  p1 <- sf::st_coordinates(sf::st_line_sample(ln, sample = min(at + 0.01, 1)))[1, 1:2]
  u <- (p1 - p0) / sqrt(sum((p1 - p0)^2)) # along-line unit vector
  v <- c(-u[2], u[1])                      # across-line unit vector

  dx <- las$X - p0[1]
  dy <- las$Y - p0[2]
  along <- (dx * u[1] + dy * u[2]) * m
  across <- (dx * v[1] + dy * v[2]) * m
  sel <- abs(along) <= width_m / 2 & abs(across) <= half_len_m
  z <- if ("Zref" %in% names(las@data)) las$Zref else las$Z
  cls <- ifelse(las$Classification == 2L, "ground", "low")
  cls[pred$pid] <- as.character(pred$pred)
  d <- data.frame(across = across[sel], z = z[sel] * m,
                  class = factor(cls[sel], levels = names(class_colours)))
  d <- d[order(d$class %in% c("wire", "structure")), ] # draw rare classes on top

  p <- ggplot2::ggplot(d, ggplot2::aes(across, z, colour = class)) +
    ggplot2::geom_point(size = 0.35, alpha = 0.8) +
    ggplot2::scale_colour_manual(values = class_colours, name = NULL, drop = FALSE,
                                 labels = c(low = "low (<2 m)")) +
    ggplot2::guides(colour = ggplot2::guide_legend(override.aes = list(size = 3, alpha = 1))) +
    ggplot2::coord_equal() +
    ggplot2::labs(title = "Classified point cloud, cross-section through the corridor",
                  subtitle = sprintf("%g m slab, %.0f%% along the line; random-forest predictions (ground from 3DEP)",
                                     width_m, 100 * at),
                  x = "Distance from mapped centreline (m)", y = "Elevation (m, NAVD88)") +
    theme_vegrisk()
  save_or_return(p, file, 8, 4.5)
}

#' Cross-validation metrics: spatial-block vs random folds
#'
#' @param metrics `metrics` element of [cv_point_classifier()], optionally
#'   with extra schemes (e.g. an ablation) stacked in.
#' @param file Output PNG path, or `NULL`.
#' @export
plot_cv <- function(metrics, file = NULL) {
  rlang::check_installed(c("ggplot2", "scales"))
  scheme_labels <- c(random = "Random k-fold", spatial_block = "Spatial block (100 m)",
                     spatial_ablation = "Spatial block, no height/echo features")
  long <- rbind(
    data.frame(metrics[, c("scheme", "class", "n", "prevalence")], metric = "Average precision",
               value = metrics$avg_precision),
    data.frame(metrics[, c("scheme", "class", "n", "prevalence")], metric = "Recall (argmax)",
               value = metrics$recall)
  )
  long$metric <- factor(long$metric, levels = c("Average precision", "Recall (argmax)"))
  long$class <- factor(long$class, levels = rev(label_levels))
  long$scheme <- factor(long$scheme, levels = names(scheme_labels), labels = scheme_labels)
  long <- long[!is.na(long$scheme), ]
  noskill <- unique(long[long$metric == "Average precision", c("class", "metric", "prevalence")])

  ap <- function(sch, cl) metrics$avg_precision[metrics$scheme == sch & metrics$class == cl]
  title <- if (all(c("random", "spatial_block") %in% metrics$scheme)) {
    sprintf("Wire average precision %.2f with random folds, %.2f with spatial blocks",
            ap("random", "wire"), ap("spatial_block", "wire"))
  } else "Cross-validated agreement with weak labels"
  n_lab <- unique(metrics[metrics$scheme == "spatial_block", c("class", "n")])

  p <- ggplot2::ggplot(long, ggplot2::aes(value, class)) +
    ggplot2::geom_point(data = noskill, ggplot2::aes(x = prevalence), shape = "|", size = 4,
                        colour = "grey40") +
    ggplot2::geom_line(ggplot2::aes(group = class), colour = "grey85", na.rm = TRUE) +
    ggplot2::geom_point(ggplot2::aes(colour = scheme), size = 2.2, na.rm = TRUE) +
    ggplot2::facet_wrap(~metric, nrow = 1) +
    ggplot2::scale_colour_manual(values = c("#9e9e9e", "#1f3b73", "#7fb3d5"), name = NULL) +
    ggplot2::scale_x_continuous(limits = c(0, 1), breaks = c(0, 0.5, 1)) +
    ggplot2::scale_y_discrete(labels = function(cl) {
      sprintf("%s (n=%s)", cl, format(n_lab$n[match(cl, n_lab$class)], big.mark = ",", trim = TRUE))
    }) +
    ggplot2::labs(title = title,
                  subtitle = paste("Agreement with weak (rule-based) labels, not ground truth, at site prevalence.",
                                   "Grey tick = no-skill average precision (class prevalence)."),
                  x = NULL, y = NULL) +
    theme_vegrisk()
  save_or_return(p, file, 9, 3.2)
}

#' Permutation importance of the top features
#'
#' @param model A model from [train_point_classifier()].
#' @param file Output PNG path, or `NULL`.
#' @param n Number of features to show.
#' @export
plot_importance <- function(model, file = NULL, n = 12) {
  rlang::check_installed("ggplot2")
  imp <- sort(model$variable.importance, decreasing = TRUE)[seq_len(min(n, length(model$variable.importance)))]
  d <- data.frame(feature = factor(names(imp), levels = rev(names(imp))), importance = imp)
  p <- ggplot2::ggplot(d, ggplot2::aes(importance, feature)) +
    ggplot2::geom_segment(ggplot2::aes(x = 0, xend = importance, yend = feature), colour = "grey70") +
    ggplot2::geom_point(size = 2, colour = "#1f3b73") +
    ggplot2::labs(title = "What the classifier relies on",
                  subtitle = "Permutation importance (increase in out-of-bag Brier score)", x = NULL, y = NULL) +
    theme_vegrisk()
  save_or_return(p, file, 6, 3.5)
}

save_or_return <- function(p, file, w, h) {
  if (is.null(file)) return(p)
  ggplot2::ggsave(file, p, width = w, height = h, dpi = 150, bg = "white")
  invisible(p)
}
