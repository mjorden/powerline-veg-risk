# Figures (ggplot2, in Suggests). Minimal ink: no chart junk, direct labels
# where possible, colour reserved for the classes / risk tiers that matter.
#
# Every colour lives in vegrisk_palette(); plot functions reach it through
# the scale_*_vegrisk() helpers below and never name a hex value. Two styles:
# "classic" (the default, the shipped figures) and "midmod", an opt-in
# mid-century earth-tone style under design review (analysis/style-spike.md):
#   options(vegrisk.style = "midmod")

vegrisk_style <- function() {
  style <- getOption("vegrisk.style", "classic")
  if (!style %in% c("classic", "midmod")) {
    rlang::abort(sprintf("`vegrisk.style` must be \"classic\" or \"midmod\", not \"%s\".", style))
  }
  style
}

vegrisk_palette <- function(style = vegrisk_style()) {
  switch(style,
    classic = list(
      paper = "white", ink = "black", ink2 = "grey35", muted = "grey40", rule = "grey85",
      neutral = "grey70", line = "grey30", highlight = "#1f3b73", nodata = "grey90",
      classes = c(vegetation = "#4d7c3a", wire = "#d62728", structure = "#1f3b73",
                  building = "#b08d57", low = "#d9d9c3", ground = "#bdbdbd"),
      schemes = c(random = "#9e9e9e", spatial_block = "#1f3b73", spatial_ablation = "#7fb3d5"),
      conductor = "#d62728", strike_fill = "#ffd92f", strike_line = "black",
      canopy = c("#f4f4ef", "#1b4d1b"), canopy_faint = c("#f4f4ef", "#8fae8f"),
      encroach = c("#fee8c8", "#b30000"), wind_hit = c("#fde0c5", "#b2182b"),
      dryness = c(`dry and grown in` = "#b2182b", `dry canopy` = "#ef8a62", `grown in` = "#4d4d4d",
                  neither = "#bababa", `no canopy pixels` = "#e0e0e0"),
      title_family = "", text_family = ""
    ),
    # Validated against the paper colour in analysis/style-spike.md: point
    # classes all-pairs CVD dE >= 9.6; ramps monotone, light end >= 2:1.
    midmod = list(
      paper = "#F4EEDE", ink = "#3B2A1E", ink2 = "#6B5744", muted = "#8C7B68", rule = "#E3D9C4",
      neutral = "#AFA497", line = "#6B5744", highlight = "#1F95B2", nodata = "#8E8578",
      classes = c(vegetation = "#606A04", wire = "#1F95B2", structure = "#6E3318",
                  building = "#AE7F1E", low = "#E1CFB3", ground = "#AFA497"),
      schemes = c(random = "#6B5744", spatial_block = "#1F95B2", spatial_ablation = "#AE7F1E"),
      conductor = "#1F95B2", strike_fill = "#3B2A1E", strike_line = "#3B2A1E",
      canopy = c("#AEAB75", "#7F8747", "#38431A"), canopy_faint = c("#D9D4B4", "#AEAB75"),
      encroach = c("#CB8E33", "#B5562A", "#6B2A12"), wind_hit = c("#CB8E33", "#B5562A", "#6B2A12"),
      dryness = c(`dry and grown in` = "#6B2A12", `dry canopy` = "#CB8E33", `grown in` = "#3B2A1E",
                  neither = "#AFA497", `no canopy pixels` = "#8E8578"),
      title_family = vegrisk_font(c("Futura", "Avenir Next", "Century Gothic", "Gill Sans"), "sans"),
      text_family = vegrisk_font(c("Charter", "Palatino", "Palatino Linotype", "Book Antiqua",
                                   "Georgia"), "serif")
    ))
}

# First installed family from `prefer`, else the generic `fallback`, so a
# missing font degrades to the device default instead of erroring.
font_cache <- new.env(parent = emptyenv())
vegrisk_font <- function(prefer, fallback) {
  if (!requireNamespace("systemfonts", quietly = TRUE)) return(fallback)
  if (is.null(font_cache$have)) font_cache$have <- unique(systemfonts::system_fonts()$family)
  have <- font_cache$have
  hit <- prefer[prefer %in% have]
  if (length(hit)) hit[1] else fallback
}

# Two-colour lists are classic `scale_*_gradient()` ends; longer ones are
# midmod ramps through `scale_*_gradientn()`.
vegrisk_gradient <- function(aesthetic, colours, ...) {
  if (length(colours) == 2) {
    if (aesthetic == "fill") ggplot2::scale_fill_gradient(low = colours[1], high = colours[2], ...)
    else ggplot2::scale_colour_gradient(low = colours[1], high = colours[2], ...)
  } else {
    if (aesthetic == "fill") ggplot2::scale_fill_gradientn(colours = colours, ...)
    else ggplot2::scale_colour_gradientn(colours = colours, ...)
  }
}

scale_fill_vegrisk_canopy <- function(..., faint = FALSE, pal = vegrisk_palette()) {
  vegrisk_gradient("fill", if (faint) pal$canopy_faint else pal$canopy, ...)
}

scale_colour_vegrisk_encroach <- function(..., pal = vegrisk_palette()) {
  vegrisk_gradient("colour", pal$encroach, ...)
}

scale_colour_vegrisk_wind <- function(..., pal = vegrisk_palette()) {
  vegrisk_gradient("colour", pal$wind_hit, ...)
}

scale_colour_vegrisk_class <- function(..., pal = vegrisk_palette()) {
  ggplot2::scale_colour_manual(values = pal$classes, ...)
}

scale_colour_vegrisk_scheme <- function(..., pal = vegrisk_palette()) {
  ggplot2::scale_colour_manual(values = pal$schemes, ...)
}

scale_colour_vegrisk_dryness <- function(..., pal = vegrisk_palette()) {
  ggplot2::scale_colour_manual(values = pal$dryness, ...)
}

theme_vegrisk <- function(base_size = 10, style = vegrisk_style()) {
  if (style == "classic") {
    return(ggplot2::theme_minimal(base_size = base_size) +
      ggplot2::theme(panel.grid.minor = ggplot2::element_blank(),
                     plot.title.position = "plot",
                     plot.title = ggplot2::element_text(face = "bold"),
                     legend.position = "top", legend.justification = "left"))
  }
  pal <- vegrisk_palette(style)
  # Tufte: ink on paper, hairline major grid only, no ticks or boxes; the
  # geometric sans is kept to the title, everything read closely is serif.
  ggplot2::theme_minimal(base_size = base_size, base_family = pal$text_family) +
    ggplot2::theme(
      text = ggplot2::element_text(colour = pal$ink2),
      plot.background = ggplot2::element_rect(fill = pal$paper, colour = NA),
      panel.background = ggplot2::element_rect(fill = pal$paper, colour = NA),
      panel.grid.major = ggplot2::element_line(colour = pal$rule, linewidth = 0.25),
      panel.grid.minor = ggplot2::element_blank(),
      axis.ticks = ggplot2::element_blank(),
      axis.text = ggplot2::element_text(colour = pal$ink2),
      axis.title = ggplot2::element_text(colour = pal$ink2, size = ggplot2::rel(0.9)),
      plot.title.position = "plot",
      plot.title = ggplot2::element_text(family = pal$title_family, colour = pal$ink,
                                         size = ggplot2::rel(1.25), margin = ggplot2::margin(b = 4)),
      plot.subtitle = ggplot2::element_text(colour = pal$ink2, lineheight = 1.1,
                                            margin = ggplot2::margin(b = 8)),
      plot.caption = ggplot2::element_text(colour = pal$ink2, hjust = 0),
      plot.margin = ggplot2::margin(14, 16, 10, 14),
      strip.text = ggplot2::element_text(family = pal$title_family, colour = pal$ink, hjust = 0,
                                         size = ggplot2::rel(0.95)),
      legend.position = "top", legend.justification = "left",
      legend.title = ggplot2::element_text(colour = pal$ink2, size = ggplot2::rel(0.85)),
      legend.text = ggplot2::element_text(colour = pal$ink2, size = ggplot2::rel(0.85)),
      legend.key = ggplot2::element_rect(fill = pal$paper, colour = NA)
    )
}

#' Map of canopy height, segment priority, and strike trees
#'
#' Segment colour is the canopy area inside the clearance envelope under the
#' pessimistic (lower) conductor bound - where to verify first, not a
#' finding; line type is the confidence (solid =
#' measured conductor or same tier under both bounds, dashed = tier depends
#' on the unknown conductor elevation). Segments tiered `"no data"` (too
#' little of the corridor observed to claim no risk) are drawn grey and
#' dotted instead of on the encroachment scale, so they never read as clear.
#'
#' @param rasters Output of [corridor_rasters()].
#' @param risk Output of [assess_risk()].
#' @param structures OSM structures (`sf`), optional.
#' @param title Plot title.
#' @param source Data credit shown in the subtitle.
#' @param encroach_limits Range of the segment colour scale (m²). The
#'   lower end is fixed at zero so that no encroachment is always the pale
#'   end: with a free scale a line with none anywhere was drawn mid-orange
#'   throughout. An `NA` upper end is the largest encroachment on the map,
#'   but never below 5 m² (the default grow-in threshold), so an
#'   all-zero map keeps a real range. Set both ends to share one scale
#'   across maps.
#' @param file Output PNG path, or `NULL` to return the plot.
#' @export
plot_risk_map <- function(rasters, risk, structures = NULL, encroach_limits = c(0, NA),
                          title = "Vegetation risk along the line",
                          source = "USGS 3DEP LiDAR", file = NULL) {
  rlang::check_installed(c("ggplot2", "scales"))
  if (vegrisk_style() == "midmod") return(risk_map_midmod(rasters, risk, structures, title, source, file))
  pal <- vegrisk_palette()
  chm <- terra::as.data.frame(rasters$chm, xy = TRUE, na.rm = TRUE)
  names(chm)[3] <- "h"
  crs <- sf::st_crs(risk$segments)
  seg <- risk$segments
  seg$certain <- ifelse(seg$confidence == "bound-dependent", "bound-dependent", "measured / robust")
  # "no data" only replaces "none", so this means no data under both bounds.
  seg$certain[seg$priority_lo %in% "no data"] <- "insufficient LiDAR coverage"
  gap <- seg$certain == "insufficient LiDAR coverage"
  if (is.na(encroach_limits[2])) {
    encroach_limits[2] <- max(5, seg$encroach_lo_m2, na.rm = TRUE)
  }
  strike <- risk$trees[risk$trees$strike, ]
  strike$both <- factor(ifelse(strike$strike_lo & strike$strike_hi, "under both bounds", "under one bound"),
                        levels = c("under both bounds", "under one bound"))

  p <- ggplot2::ggplot() +
    ggplot2::geom_raster(data = chm, ggplot2::aes(x, y, fill = h)) +
    scale_fill_vegrisk_canopy(limits = c(0, 30), oob = scales::squish, name = "Canopy height (m)",
                              pal = pal) +
    ggplot2::geom_sf(data = seg[!gap, ], ggplot2::aes(colour = encroach_lo_m2, linetype = certain), linewidth = 1.1) +
    ggplot2::geom_sf(data = seg[gap, ], ggplot2::aes(linetype = certain), colour = pal$muted, linewidth = 1.1) +
    scale_colour_vegrisk_encroach(name = "Canopy in clearance envelope\nif conductor at code minimum (m\u00b2)",
                                  limits = encroach_limits, oob = scales::squish, pal = pal) +
    ggplot2::scale_linetype_manual(values = c(`measured / robust` = "solid", `bound-dependent` = "22",
                                              `insufficient LiDAR coverage` = "11"),
                                   name = NULL) +
    ggplot2::geom_sf(data = strike, ggplot2::aes(shape = both), size = 1.5, stroke = 0.4,
                     fill = pal$strike_fill, colour = pal$strike_line) +
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

# Prototype of plot_risk_map() in the midmod style (analysis/style-spike.md).
# Folds in #5 (scale anchored at zero), #33.1 (unobserved cells keyed, not
# drawn as bare ground), #33.3 (segments on top over a paper casing) and
# #33.7 ("30+" top break); graticule replaced by a scale bar.
risk_map_midmod <- function(rasters, risk, structures, title, source, file) {
  pal <- vegrisk_palette("midmod")
  chm <- terra::as.data.frame(rasters$chm, xy = TRUE, na.rm = TRUE)
  names(chm)[3] <- "h"
  crs <- sf::st_crs(risk$segments)
  m <- crs_m_per_unit(crs)
  seg <- risk$segments
  seg$certain <- ifelse(seg$confidence == "bound-dependent", "bound-dependent", "measured / robust")
  # "no data" only replaces "none", so this means no data under both bounds.
  seg$certain[seg$priority_lo %in% "no data"] <- "insufficient LiDAR coverage"
  strike <- risk$trees[risk$trees$strike, ]
  strike$both <- factor(ifelse(strike$strike_lo & strike$strike_hi, "under both bounds", "under one bound"),
                        levels = c("under both bounds", "under one bound"))
  # #5: zero is absence, not low-grade risk - zero segments get a thin
  # neutral line and the ramp covers only values above zero.
  gap <- seg$certain == "insufficient LiDAR coverage"
  seg$zero <- seg$encroach_lo_m2 %in% 0 & !gap
  pos <- seg[!seg$zero & !gap, ]
  top <- max(c(1, pos$encroach_lo_m2), na.rm = TRUE)
  bar <- function(order) ggplot2::guide_colourbar(order = order, title.position = "top",
                                                  barwidth = ggplot2::unit(9, "lines"),
                                                  barheight = ggplot2::unit(0.5, "lines"))

  # Unobserved cells (conductor returns removed, #33.1) hug the line, so they
  # are drawn over the casing, and also counted in the subtitle.
  un <- NULL
  if (!is.null(rasters$unobserved)) {
    un <- terra::as.data.frame(rasters$unobserved, xy = TRUE, na.rm = TRUE)
    un <- un[un[[3]] %in% TRUE, c("x", "y")]
    # Voids fill the bounding box outside the clipped corridor too; keep only
    # cells no farther from the line than the LiDAR returns reach (cells
    # with returns are the clipped corridor).
    if (nrow(un) && !is.null(rasters$void)) {
      ref <- terra::as.data.frame(rasters$void, xy = TRUE, na.rm = TRUE)
      ref <- ref[ref[[3]] %in% FALSE, c("x", "y")]
      verts <- line_vertex_table(seg, crs)
      d <- function(xy) FNN::get.knnx(as.matrix(verts[, c("x", "y")]), as.matrix(xy), k = 1)$nn.dist[, 1]
      un <- if (nrow(ref)) un[d(un) <= max(d(ref)), ] else un[0, ]
    }
    if (!nrow(un)) un <- NULL
  }
  p <- ggplot2::ggplot() +
    ggplot2::geom_raster(data = chm, ggplot2::aes(x, y, fill = h)) +
    scale_fill_vegrisk_canopy(limits = c(0, 30), oob = scales::squish, breaks = c(0, 10, 20, 30),
                              labels = c("0", "10", "20", "30+"), name = "Canopy height (m)", pal = pal,
                              guide = bar(1))
  if (!is.null(structures) && nrow(structures) > 0) {
    st <- sf::st_transform(structures, crs)
    st <- st[lengths(sf::st_intersects(st, sf::st_as_sfc(sf::st_bbox(seg)))) > 0, ]
    p <- p + ggplot2::geom_sf(data = st, shape = 3, size = 1.6, colour = pal$ink2)
  }
  if (nrow(strike) > 0) {
    p <- p +
      # Ink dot with a paper rim / paper dot with an ink rim: legible on
      # both the palest and the darkest canopy. Colour is taken by the
      # encroachment scale, so the two looks are fixed per layer.
      ggplot2::geom_sf(data = strike[strike$both == "under one bound", ], ggplot2::aes(shape = both),
                       size = 1.8, stroke = 0.45, fill = pal$paper, colour = pal$strike_line,
                       show.legend = "point") +
      ggplot2::geom_sf(data = strike[strike$both == "under both bounds", ], ggplot2::aes(shape = both),
                       size = 1.8, stroke = 0.3, fill = pal$strike_fill, colour = pal$paper,
                       show.legend = FALSE) +
      ggplot2::scale_shape_manual(values = c(`under both bounds` = 21, `under one bound` = 21),
                                  name = "Strike trees", drop = FALSE,
                                  guide = ggplot2::guide_legend(
                                    order = 3, title.position = "top", ncol = 1, direction = "vertical",
                                    override.aes = list(fill = c(pal$strike_fill, pal$paper), size = 2.2,
                                                        colour = c(pal$paper, pal$strike_line))))
  }
  p <- p +
    # Paper casing keeps every segment legible over dark canopy and markers.
    ggplot2::geom_sf(data = seg, colour = pal$paper, linewidth = 2.2, lineend = "butt")
  if (!is.null(un)) {
    res <- terra::res(rasters$unobserved)
    p <- p + ggplot2::geom_tile(data = un, ggplot2::aes(x, y), width = res[1], height = res[2],
                                fill = pal$nodata)
  }
  p <- p +
    ggplot2::geom_sf(data = seg[seg$zero, ], ggplot2::aes(linetype = certain), colour = pal$line,
                     linewidth = 0.5, lineend = "butt") +
    ggplot2::geom_sf(data = seg[gap, ], ggplot2::aes(linetype = certain), colour = pal$nodata,
                     linewidth = 0.9, lineend = "butt")
  if (nrow(pos)) {
    p <- p +
      ggplot2::geom_sf(data = pos, ggplot2::aes(colour = encroach_lo_m2, linetype = certain),
                       linewidth = 1.3, lineend = "butt") +
      scale_colour_vegrisk_encroach(limits = c(0, top), na.value = pal$nodata, pal = pal,
                                    name = "Canopy in clearance envelope\nif conductor at code minimum (m\u00b2)",
                                    breaks = scales::breaks_extended(4), guide = bar(2))
  }
  p <- p +
    ggplot2::scale_linetype_manual(values = c(`measured / robust` = "solid", `bound-dependent` = "22",
                                              `insufficient LiDAR coverage` = "11"),
                                   guide = "none")

  # Metric scale bar, bottom-left, instead of a graticule.
  # Below everything drawn (canopy extent, not just the line).
  bb <- sf::st_bbox(seg)
  ext <- as.vector(terra::ext(rasters$chm))
  span_m <- (max(bb[["xmax"]], ext[["xmax"]]) - min(bb[["xmin"]], ext[["xmin"]])) * m
  bar_m <- c(20, 50, 100, 200, 500, 1000)[findInterval(span_m / 5, c(0, 35, 75, 150, 350, 750))]
  x0 <- max(bb[["xmin"]], ext[["xmin"]])
  y0 <- min(bb[["ymin"]], ext[["ymin"]]) - 0.03 * (ext[["ymax"]] - ext[["ymin"]])
  p <- p +
    ggplot2::annotate("segment", x = x0, xend = x0 + bar_m / m, y = y0, yend = y0,
                      colour = pal$ink, linewidth = 0.6) +
    ggplot2::annotate("text", x = x0 + bar_m / m / 2, y = y0, label = paste(bar_m, "m"), vjust = -0.6,
                      size = 2.8, colour = pal$ink2, family = pal$text_family)

  # Line type is explained in words (one less legend box); only when used.
  dashed_note <- if (any(seg$certain == "bound-dependent")) {
    "\nDashed segments: tier depends on the unknown conductor elevation."
  } else ""
  if (any(seg$certain == "insufficient LiDAR coverage")) {
    dashed_note <- paste0(dashed_note, "\nDotted segments: too little of the corridor observed to claim no risk.")
  }
  zero_note <- if (!nrow(pos) && any(seg$zero)) {
    paste0("\nNo canopy in the clearance envelope on any ", if (any(gap)) "observed ", "segment (thin line).")
  } else if (any(seg$zero)) "\nThin line: no canopy in the clearance envelope." else ""
  unobs_note <- if (!is.null(un)) {
    sprintf("\n%s m\u00b2 unobserved by the LiDAR or left out as uncertain (grey; not bare ground).",
            format(round(nrow(un) * prod(terra::res(rasters$unobserved)) * m^2), big.mark = ","))
  } else ""
  p <- p +
    ggplot2::labs(title = title,
                  subtitle = sprintf(paste("Potential strike trees: %d if the conductor is at code minimum,",
                                           "%d at the optimistic bound.\n%.0f m segments | %s | OSM line geometry%s%s"),
                                     sum(risk$trees$strike_lo), sum(risk$trees$strike_hi),
                                     stats::median(seg$length_m), source, paste0(zero_note, dashed_note), unobs_note),
                  x = NULL, y = NULL) +
    ggplot2::coord_sf(crs = crs, datum = NA, expand = TRUE, clip = "off") +
    theme_vegrisk(style = "midmod") +
    ggplot2::theme(legend.box = "horizontal", legend.box.just = "top", legend.direction = "horizontal",
                   legend.spacing.x = ggplot2::unit(1.5, "lines"), panel.grid = ggplot2::element_blank())
  tall <- (bb[["ymax"]] - bb[["ymin"]]) > 2 * (bb[["xmax"]] - bb[["xmin"]])
  if (tall) {
    p <- p + ggplot2::theme(legend.position = "right", legend.justification = "top",
                            legend.box = "vertical", legend.spacing.y = ggplot2::unit(1, "lines"))
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
  pal <- vegrisk_palette()
  pr <- profile[profile$line_id == profile$line_id[1], ]
  unknown <- is.infinite(pr$z_hi)
  pr$z_hi[unknown] <- NA
  meas <- pr[pr$src == "measured", ]
  p <- ggplot2::ggplot(pr, ggplot2::aes(s_m)) +
    ggplot2::geom_ribbon(ggplot2::aes(ymin = z_lo, ymax = z_hi), fill = pal$conductor, alpha = 0.18,
                         na.rm = TRUE) +
    ggplot2::geom_line(ggplot2::aes(y = z_lo), colour = pal$conductor, linewidth = 0.3, na.rm = TRUE) +
    ggplot2::geom_line(ggplot2::aes(y = ground), colour = pal$ink2) +
    ggplot2::geom_point(data = meas, ggplot2::aes(y = z_lo), colour = pal$conductor, size = 0.8) +
    ggplot2::annotate("text", x = max(pr$s_m), y = pr$ground[nrow(pr)], label = "ground",
                      hjust = 1.05, vjust = 1.6, size = 3, colour = pal$ink2) +
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
  pal <- vegrisk_palette()
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
                  class = factor(cls[sel], levels = names(pal$classes)))
  d <- d[order(d$class %in% c("wire", "structure")), ] # draw rare classes on top

  p <- ggplot2::ggplot(d, ggplot2::aes(across, z, colour = class)) +
    ggplot2::geom_point(size = 0.35, alpha = 0.8) +
    scale_colour_vegrisk_class(name = NULL, drop = FALSE, pal = pal,
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
  if (vegrisk_style() == "midmod") return(cv_midmod(metrics, file))
  pal <- vegrisk_palette()
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
                        colour = pal$muted) +
    ggplot2::geom_line(ggplot2::aes(group = class), colour = pal$rule, na.rm = TRUE) +
    ggplot2::geom_point(ggplot2::aes(colour = scheme), size = 2.2, na.rm = TRUE) +
    ggplot2::facet_wrap(~metric, nrow = 1) +
    ggplot2::scale_colour_manual(values = unname(pal$schemes), name = NULL) +
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

# Prototype of plot_cv() in the midmod style (analysis/style-spike.md).
# Folds in #34: schemes offset vertically so none hides another, colours
# keyed by scheme name (a subset keeps its colours), unknown schemes kept
# under their raw names, n from any scheme, and AP printed to two
# significant figures below 0.01 so 0.004 does not read as 0.00.
cv_midmod <- function(metrics, file) {
  pal <- vegrisk_palette("midmod")
  scheme_labels <- c(random = "Random k-fold", spatial_block = "Spatial block (100 m)",
                     spatial_ablation = "Spatial block, no height/echo features")
  extra <- setdiff(unique(metrics$scheme), names(scheme_labels))
  if (length(extra)) {
    rlang::warn(sprintf("plot_cv(): no style for scheme(s) %s; drawn in neutral.", paste(extra, collapse = ", ")))
    scheme_labels <- c(scheme_labels, stats::setNames(extra, extra))
  }
  schemes <- intersect(names(scheme_labels), unique(metrics$scheme))
  cols <- c(pal$schemes, stats::setNames(rep(pal$neutral, length(extra)), extra))[schemes]
  # Hollow = the optimistic reference (random folds); filled = spatial.
  shapes <- stats::setNames(ifelse(schemes == "random", 21, 19), schemes)

  long <- rbind(
    data.frame(metrics[, c("scheme", "class", "n", "prevalence")], metric = "Average precision",
               value = metrics$avg_precision),
    data.frame(metrics[, c("scheme", "class", "n", "prevalence")], metric = "Recall (argmax)",
               value = metrics$recall)
  )
  long$metric <- factor(long$metric, levels = c("Average precision", "Recall (argmax)"))
  cls <- rev(label_levels[label_levels %in% metrics$class])
  long <- long[long$class %in% cls, ]
  # Vertical offsets within each class row, first scheme on top.
  off <- stats::setNames(seq(0.22, -0.22, length.out = max(length(schemes), 2))[seq_along(schemes)], schemes)
  if (length(schemes) == 1) off[] <- 0
  long$y <- match(long$class, cls) + off[long$scheme]
  long$scheme <- factor(long$scheme, levels = schemes)
  noskill <- unique(long[long$metric == "Average precision", c("class", "metric", "prevalence")])
  noskill$y <- match(noskill$class, cls)

  n_lab <- stats::aggregate(n ~ class, data = metrics, FUN = max)
  ylab <- sprintf("%s (n=%s)", cls, format(n_lab$n[match(cls, n_lab$class)], big.mark = ",", trim = TRUE))
  fmt <- function(x) if (is.na(x)) "NA" else if (x < 0.01) format(signif(x, 2), scientific = FALSE)
                     else sprintf("%.2f", x)
  ap <- function(sch, cl) metrics$avg_precision[metrics$scheme == sch & metrics$class == cl]
  a_r <- ap("random", "wire")
  a_s <- ap("spatial_block", "wire")
  title <- if (length(a_r) == 1 && length(a_s) == 1) {
    sprintf("Wire average precision %s with random folds, %s with spatial blocks", fmt(a_r), fmt(a_s))
  } else "Cross-validated agreement with weak labels"
  # Range rule at the row centre (the points themselves are offset).
  rng <- stats::aggregate(value ~ class + metric, data = long, FUN = range)
  rng <- data.frame(rng[c("class", "metric")], lo = rng$value[, 1], hi = rng$value[, 2],
                    y = match(rng$class, cls))

  p <- ggplot2::ggplot(long, ggplot2::aes(value, y)) +
    ggplot2::geom_segment(data = noskill, ggplot2::aes(x = prevalence, xend = prevalence,
                                                       y = y - 0.36, yend = y + 0.36),
                          colour = pal$muted, linewidth = 0.5) +
    ggplot2::geom_segment(data = rng, ggplot2::aes(x = lo, xend = hi, y = y, yend = y),
                          colour = pal$rule, linewidth = 0.6) +
    ggplot2::geom_point(ggplot2::aes(colour = scheme, shape = scheme), size = 2.2, stroke = 0.7,
                        fill = pal$paper, na.rm = TRUE) +
    ggplot2::facet_wrap(~metric, nrow = 1) +
    ggplot2::scale_colour_manual(values = cols, labels = scheme_labels[schemes], name = NULL) +
    ggplot2::scale_shape_manual(values = shapes, labels = scheme_labels[schemes], name = NULL) +
    ggplot2::scale_x_continuous(limits = c(0, 1), breaks = c(0, 0.5, 1), labels = c("0", "0.5", "1"),
                                expand = ggplot2::expansion(add = 0.02)) +
    ggplot2::scale_y_continuous(breaks = seq_along(cls), labels = ylab,
                                expand = ggplot2::expansion(add = 0.3)) +
    ggplot2::labs(title = title,
                  subtitle = paste("Agreement with weak (rule-based) labels, not ground truth, at site prevalence.",
                                   "\nVertical tick = no-skill average precision (class prevalence)."),
                  x = NULL, y = NULL) +
    theme_vegrisk(style = "midmod") +
    ggplot2::theme(panel.grid.major.y = ggplot2::element_blank(),
                   panel.spacing.x = ggplot2::unit(1.6, "lines"),
                   axis.text.y = ggplot2::element_text(colour = pal$ink2, hjust = 0))
  save_or_return(p, file, 9, 3.6)
}

#' Permutation importance of the top features
#'
#' @param model A model from [train_point_classifier()].
#' @param file Output PNG path, or `NULL`.
#' @param n Number of features to show.
#' @export
plot_importance <- function(model, file = NULL, n = 12) {
  rlang::check_installed("ggplot2")
  pal <- vegrisk_palette()
  imp <- sort(model$variable.importance, decreasing = TRUE)[seq_len(min(n, length(model$variable.importance)))]
  d <- data.frame(feature = factor(names(imp), levels = rev(names(imp))), importance = imp)
  p <- ggplot2::ggplot(d, ggplot2::aes(importance, feature)) +
    ggplot2::geom_segment(ggplot2::aes(x = 0, xend = importance, yend = feature), colour = pal$neutral) +
    ggplot2::geom_point(size = 2, colour = pal$highlight) +
    ggplot2::labs(title = "What the classifier relies on",
                  subtitle = "Permutation importance (increase in out-of-bag Brier score)", x = NULL, y = NULL) +
    theme_vegrisk()
  save_or_return(p, file, 6, 3.5)
}

#' Map of dry-season canopy greenness and dry grown-in segments
#'
#' Landsat pixels are drawn at their 30 m footprint, coloured by the index
#' that drives `dry_canopy`; pixels below the canopy-fraction cut-off (mostly
#' cleared right-of-way) are grey. Segments are coloured by the combined
#' screen.
#'
#' @param dryness Output of [canopy_dryness()].
#' @param title Plot title; `NULL` states how many grown-in segments have
#'   dry canopy.
#' @param file Output PNG path, or `NULL`.
#' @export
plot_canopy_dryness <- function(dryness, title = NULL, file = NULL) {
  rlang::check_installed(c("ggplot2", "scales"))
  pal <- vegrisk_palette()
  seg <- dryness$segments
  info <- attr(seg, "landsat")
  key <- info$dry_index
  crs <- sf::st_crs(seg)
  px <- cbind(sf::st_coordinates(dryness$pixels), sf::st_drop_geometry(dryness$pixels))
  px$value <- px[[key]]
  w <- 30 / crs_m_per_unit(crs)
  lv <- c("dry and grown in", "dry canopy", "grown in", "neither", "no canopy pixels")
  seg$screen <- factor(ifelse(is.na(seg$dry_canopy), lv[5],
                       ifelse(seg$dry_grow_in, lv[1], ifelse(seg$dry_canopy, lv[2],
                       ifelse(seg$priority == "grow-in", lv[3], lv[4])))), levels = lv)
  dates <- range(info$dates)
  if (is.null(title)) {
    title <- sprintf("%d of %d grown-in segments have canopy among the corridor's driest %.0f%%",
                     sum(seg$dry_grow_in, na.rm = TRUE), sum(seg$priority == "grow-in"),
                     100 * info$dry_quantile)
  }

  p <- ggplot2::ggplot() +
    ggplot2::geom_tile(data = px[!px$scored, ], ggplot2::aes(X, Y), width = w, height = w,
                       fill = pal$nodata, colour = pal$paper, linewidth = 0.1) +
    ggplot2::geom_tile(data = px[px$scored, ], ggplot2::aes(X, Y, fill = value), width = w, height = w,
                       colour = pal$paper, linewidth = 0.1) +
    ggplot2::scale_fill_distiller(palette = "BrBG", direction = 1, name = toupper(key)) +
    ggplot2::geom_sf(data = seg, ggplot2::aes(colour = screen), linewidth = 1.3) +
    scale_colour_vegrisk_dryness(drop = FALSE, name = NULL, pal = pal) +
    ggplot2::labs(title = title,
                  subtitle = sprintf(paste("Dry-season median of %d Landsat scenes, %s to %s.",
                                           "\nDry = segment in the lowest %.0f%% of the corridor's canopy pixels by %s.",
                                           "\nGrown in = optimistic-bound grow-in tier from LiDAR.",
                                           "\nGrey pixels not scored: < %.0f%% canopy, < %.0f%% observed by the LiDAR,",
                                           "or < %d clear looks."),
                                     length(info$scenes), format(dates[1], "%b %Y"), format(dates[2], "%b %Y"),
                                     100 * info$dry_quantile, toupper(key), 100 * info$min_canopy_frac,
                                     100 * (info$min_coverage %||% 0), info$min_obs %||% 1L),
                  x = NULL, y = NULL) +
    ggplot2::coord_sf(crs = crs, datum = crs, expand = FALSE) +
    ggplot2::scale_x_continuous(n.breaks = 3) +
    theme_vegrisk() +
    ggplot2::theme(axis.text = ggplot2::element_text(size = 7), legend.box = "vertical")
  bb <- sf::st_bbox(seg)
  tall <- (bb[["ymax"]] - bb[["ymin"]]) > 2 * (bb[["xmax"]] - bb[["xmin"]])
  if (tall) p <- p + ggplot2::theme(legend.position = "right", legend.justification = "top")
  save_or_return(p, file, if (tall) 9 else 8, if (tall) 10 else 9)
}

#' Strike trees the fire-weather winds would throw into the line
#'
#' Map of potential strike trees (under one conductor bound) coloured by the
#' share of fire-weather hours whose wind would push them into the line, over
#' the canopy height model, with a wind rose of those hours.
#'
#' @param risk Output of [wind_fall_exposure()].
#' @param rasters Output of [corridor_rasters()], optional (canopy backdrop).
#' @param bound `"lo"` or `"hi"`: conductor bound defining the strike trees.
#' @param title Plot title; `NULL` states the windward count.
#' @param file Output PNG path, or `NULL`.
#' @export
plot_wind_exposure <- function(risk, rasters = NULL, bound = c("lo", "hi"), title = NULL,
                               file = NULL) {
  rlang::check_installed(c("ggplot2", "scales", "patchwork"))
  bound <- match.arg(bound)
  pal <- vegrisk_palette()
  info <- attr(risk$segments, "wind")
  crs <- sf::st_crs(risk$segments)
  tr <- risk$trees[risk$trees[[paste0("strike_", bound)]], ]
  tr$hit <- tr[[paste0("wind_hit_", bound)]]
  tr <- tr[order(tr$hit), ]
  n_ww <- sum(tr$hit >= info$windward_min, na.rm = TRUE)
  if (is.null(title)) {
    title <- sprintf("%d of %d potential strike trees stand where fire-weather winds would throw them into the line",
                     n_ww, nrow(tr))
  }

  p <- ggplot2::ggplot()
  if (!is.null(rasters)) {
    chm <- terra::as.data.frame(rasters$chm, xy = TRUE, na.rm = TRUE)
    names(chm)[3] <- "h"
    p <- p + ggplot2::geom_raster(data = chm, ggplot2::aes(x, y, fill = h), show.legend = FALSE) +
      scale_fill_vegrisk_canopy(faint = TRUE, limits = c(0, 30), oob = scales::squish, pal = pal)
  }
  p <- p +
    ggplot2::geom_sf(data = risk$segments, colour = pal$line, linewidth = 0.6) +
    ggplot2::geom_sf(data = tr, ggplot2::aes(colour = hit), size = 1.8) +
    scale_colour_vegrisk_wind(limits = c(0, 1), labels = scales::percent, pal = pal,
                                   name = "Fire-weather hours that\nthrow the tree into the line") +
    ggplot2::coord_sf(crs = crs, datum = crs, expand = FALSE) +
    ggplot2::scale_x_continuous(n.breaks = 3) +
    ggplot2::labs(x = NULL, y = NULL) +
    theme_vegrisk() +
    ggplot2::theme(axis.text = ggplot2::element_text(size = 7))

  rose <- data.frame(dir = info$dir_from_deg)
  rose$sector <- factor(round(rose$dir / 22.5) %% 16, levels = 0:15)
  rose <- as.data.frame(table(sector = rose$sector))
  rose$share <- rose$Freq / sum(rose$Freq)
  rose$angle <- as.numeric(as.character(rose$sector)) * 22.5
  r <- ggplot2::ggplot(rose, ggplot2::aes(angle, share)) +
    ggplot2::geom_col(width = 22.5, fill = pal$highlight, colour = pal$paper, linewidth = 0.2) +
    ggplot2::coord_polar(start = -pi / 16) +
    ggplot2::scale_x_continuous(limits = c(-11.25, 348.75), breaks = c(0, 90, 180, 270),
                                labels = c("N", "E", "S", "W")) +
    ggplot2::scale_y_continuous(labels = scales::percent) +
    ggplot2::labs(x = NULL, y = NULL, title = "Fire-weather winds come from") +
    theme_vegrisk(9) +
    ggplot2::theme(axis.text.y = ggplot2::element_text(size = 6), plot.title = ggplot2::element_text(size = 9))

  ge <- intToUtf8(8805)  # >=
  le <- intToUtf8(8804)  # <=
  pm <- intToUtf8(177)   # +/-
  deg <- intToUtf8(176)
  sub <- sprintf(paste("%d hours with gusts %s %.0f m/s and RH %s %g%% (ERA5 reanalysis via Open-Meteo).",
                       "\nStrike trees under the %s conductor bound. An hour counts against a tree when its wind",
                       "\nblows the tree within the arc of fall directions that reach a conductor (%s%g%s fall scatter)."),
                 info$n_hours, ge, info$min_gust_ms, le, info$max_rh,
                 if (bound == "lo") "pessimistic (code-minimum)" else "optimistic", pm, info$spread_deg, deg)
  out <- patchwork::wrap_plots(p, r, widths = c(3, 1)) +
    patchwork::plot_annotation(title = title, subtitle = sub, theme = theme_vegrisk())
  save_or_return(out, file, 10, 8)
}

save_or_return <- function(p, file, w, h) {
  if (is.null(file)) return(p)
  ggplot2::ggsave(file, p, width = w, height = h, dpi = 150, bg = vegrisk_palette()$paper)
  invisible(p)
}
