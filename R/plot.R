# Figures (ggplot2, in Suggests). Tufte rules: ink on paper, no chart junk,
# direct labels where they fit, colour reserved for the classes and risk
# tiers that matter, and one sentence of subtitle in place of a legend box
# wherever that reads better.
#
# Every colour lives in vegrisk_palette(); plot functions reach it through
# the scale_*_vegrisk() helpers and never name a hex value. Two styles:
# "midmod" (the default: mid-century earth tones on parchment, see
# analysis/style-spike.md) and "classic" (the original white-paper look):
#   options(vegrisk.style = "classic")

vegrisk_style <- function() {
  style <- getOption("vegrisk.style", "midmod")
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
      greenness = c("#d8b365", "#f5f5f5", "#5ab4ac"),
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
      # Dry (ochre) through sage to deep olive: greener is darker, the same
      # direction as the canopy ramp, so the two maps read alike.
      greenness = c("#CB8E33", "#AEAB75", "#38431A"),
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

# Two-colour lists are `scale_*_gradient()` ends; longer ones are ramps
# through `scale_*_gradientn()`.
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

scale_fill_vegrisk_wind <- function(..., pal = vegrisk_palette()) {
  vegrisk_gradient("fill", pal$wind_hit, ...)
}

scale_fill_vegrisk_greenness <- function(..., pal = vegrisk_palette()) {
  vegrisk_gradient("fill", pal$greenness, ...)
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

# ---- shared map furniture -----------------------------------------------

# Short horizontal colour bar with the title on top, so every key reads the
# same way.
colour_bar <- function(order) {
  # Always a horizontal bar, whichever side of the map the legend sits on.
  ggplot2::guide_colourbar(order = order, title.position = "top", direction = "horizontal",
                           label.position = "bottom",
                           barwidth = ggplot2::unit(9, "lines"), barheight = ggplot2::unit(0.5, "lines"))
}

# Characters that must stay out of the source as literals (R CMD check wants
# ASCII) and out of "\u" escapes (which some editors unescape in place).
sym <- list(sq = intToUtf8(178), ge = intToUtf8(8805), le = intToUtf8(8804), pm = intToUtf8(177),
            deg = intToUtf8(176), larr = intToUtf8(8592), rarr = intToUtf8(8594))

# A metric scale bar at the bottom-left of a map instead of a graticule:
# the one thing a corridor map's axes carried (distance) in a form that
# works for any projected CRS, feet included.
map_scale_bar <- function(ext, m, pal) {
  span_m <- (ext[["xmax"]] - ext[["xmin"]]) * m
  bar_m <- c(20, 50, 100, 200, 500, 1000)[findInterval(span_m / 5, c(0, 35, 75, 150, 350, 750))]
  x0 <- ext[["xmin"]]
  y0 <- ext[["ymin"]] - 0.03 * (ext[["ymax"]] - ext[["ymin"]])
  list(
    ggplot2::annotate("segment", x = x0, xend = x0 + bar_m / m, y = y0, yend = y0,
                      colour = pal$ink, linewidth = 0.6),
    ggplot2::annotate("text", x = x0 + bar_m / m / 2, y = y0, label = paste(bar_m, "m"), vjust = -0.6,
                      size = 2.8, colour = pal$ink2, family = pal$text_family)
  )
}

# Extent of everything drawn on a map: the segments plus any raster.
map_extent <- function(seg, raster = NULL) {
  bb <- sf::st_bbox(seg)
  ext <- c(xmin = bb[["xmin"]], xmax = bb[["xmax"]], ymin = bb[["ymin"]], ymax = bb[["ymax"]])
  if (!is.null(raster)) {
    e <- as.vector(terra::ext(raster))
    ext <- c(xmin = min(ext[["xmin"]], e[["xmin"]]), xmax = max(ext[["xmax"]], e[["xmax"]]),
             ymin = min(ext[["ymin"]], e[["ymin"]]), ymax = max(ext[["ymax"]], e[["ymax"]]))
  }
  ext
}

# No graticule, no grid; legend beside a tall (north-south) corridor so the
# map keeps its width.
map_frame <- function(crs, seg) {
  bb <- sf::st_bbox(seg)
  tall <- (bb[["ymax"]] - bb[["ymin"]]) > 2 * (bb[["xmax"]] - bb[["xmin"]])
  side <- if (tall) {
    ggplot2::theme(legend.position = "right", legend.justification = "top",
                   legend.box = "vertical", legend.spacing.y = ggplot2::unit(1, "lines"))
  } else {
    ggplot2::theme(legend.box = "horizontal", legend.box.just = "top", legend.direction = "horizontal",
                   legend.spacing.x = ggplot2::unit(1.5, "lines"))
  }
  list(ggplot2::coord_sf(crs = crs, datum = NA, expand = TRUE, clip = "off"),
       ggplot2::labs(x = NULL, y = NULL),
       theme_vegrisk(),
       ggplot2::theme(panel.grid = ggplot2::element_blank()),
       side)
}

map_size <- function(seg) {
  bb <- sf::st_bbox(seg)
  tall <- (bb[["ymax"]] - bb[["ymin"]]) > 2 * (bb[["xmax"]] - bb[["xmin"]])
  if (tall) c(9, 10) else c(8, 9)
}

# Cells the LiDAR did not observe, or that were left out of the canopy model
# as uncertain, clipped to the corridor the returns reach (voids fill the
# bounding box outside the clip too).
unobserved_cells <- function(rasters, seg, crs) {
  if (is.null(rasters$unobserved)) return(NULL)
  un <- terra::as.data.frame(rasters$unobserved, xy = TRUE, na.rm = TRUE)
  un <- un[un[[3]] %in% TRUE, c("x", "y")]
  if (nrow(un) && !is.null(rasters$void)) {
    ref <- terra::as.data.frame(rasters$void, xy = TRUE, na.rm = TRUE)
    ref <- ref[ref[[3]] %in% FALSE, c("x", "y")]
    verts <- line_vertex_table(seg, crs)
    d <- function(xy) FNN::get.knnx(as.matrix(verts[, c("x", "y")]), as.matrix(xy), k = 1)$nn.dist[, 1]
    un <- if (nrow(ref)) un[d(un) <= max(d(ref)), ] else un[0, ]
  }
  if (nrow(un)) un else NULL
}

#' Map of canopy height, segment priority, and strike trees
#'
#' Segment colour is the canopy area inside the clearance envelope under the
#' pessimistic (lower) conductor bound - where to verify first, not a
#' finding. Zero is drawn as absence (a thin neutral line), never as the
#' pale end of the risk ramp. Line type is the confidence: dashed where the
#' tier depends on the unknown conductor elevation, dotted where too little
#' of the corridor was observed to claim no risk (`"no data"`). Cells the
#' LiDAR did not observe are drawn grey and their area is reported, so
#' unseen never reads as clear. Strike trees are ink dots (strike at every
#' plausible conductor height) or paper dots (at some); supports used for
#' the upper bound are crosses.
#'
#' @param rasters Output of [corridor_rasters()].
#' @param risk Output of [assess_risk()].
#' @param structures OSM structures and line vertices (`sf`), optional.
#' @param title Plot title.
#' @param source Data credit shown in the subtitle.
#' @param encroach_limits Range of the encroachment ramp (m^2). The lower
#'   end is zero; an `NA` upper end is the largest value on the map. Set
#'   both to share one ramp across maps.
#' @param file Output PNG path, or `NULL` to return the plot.
#' @export
plot_risk_map <- function(rasters, risk, structures = NULL, encroach_limits = c(0, NA),
                          title = "Vegetation risk along the line",
                          source = "USGS 3DEP LiDAR", file = NULL) {
  rlang::check_installed(c("ggplot2", "scales"))
  pal <- vegrisk_palette()
  chm <- terra::as.data.frame(rasters$chm, xy = TRUE, na.rm = TRUE)
  names(chm)[3] <- "h"
  crs <- sf::st_crs(risk$segments)
  m <- crs_m_per_unit(crs)
  seg <- risk$segments
  seg$certain <- ifelse(seg$confidence == "bound-dependent", "bound-dependent", "measured / robust")
  # "no data" only replaces "none", so this means no data under both bounds.
  seg$certain[seg$priority_lo %in% "no data"] <- "insufficient LiDAR coverage"
  gap <- seg$certain == "insufficient LiDAR coverage"
  seg$zero <- seg$encroach_lo_m2 %in% 0 & !gap
  pos <- seg[!seg$zero & !gap, ]
  top <- if (is.na(encroach_limits[2])) max(c(1, pos$encroach_lo_m2), na.rm = TRUE) else encroach_limits[2]
  strike <- risk$trees[risk$trees$strike, ]
  strike$both <- factor(ifelse(strike$strike_certain, "at every plausible conductor height",
                               "at some plausible height"),
                        levels = c("at every plausible conductor height", "at some plausible height"))
  un <- unobserved_cells(rasters, seg, crs)

  p <- ggplot2::ggplot() +
    ggplot2::geom_raster(data = chm, ggplot2::aes(x, y, fill = h)) +
    scale_fill_vegrisk_canopy(limits = c(0, 30), oob = scales::squish, breaks = c(0, 10, 20, 30),
                              labels = c("0", "10", "20", "30+"), name = "Canopy height (m)", pal = pal,
                              guide = colour_bar(1))
  st <- NULL
  if (!is.null(structures) && nrow(structures) > 0) {
    st <- sf::st_transform(structures, crs)
    st <- st[lengths(sf::st_intersects(st, sf::st_as_sfc(sf::st_bbox(seg)))) > 0, ]
    p <- p + ggplot2::geom_sf(data = st, shape = 3, size = 1.6, colour = pal$ink2)
  }
  if (nrow(strike) > 0) {
    p <- p +
      # Ink dot with a paper rim / paper dot with an ink rim: legible on
      # both the palest and the darkest canopy.
      ggplot2::geom_sf(data = strike[strike$both == "at some plausible height", ], ggplot2::aes(shape = both),
                       size = 1.8, stroke = 0.45, fill = pal$paper, colour = pal$strike_line,
                       show.legend = "point") +
      ggplot2::geom_sf(data = strike[strike$both == "at every plausible conductor height", ], ggplot2::aes(shape = both),
                       size = 1.8, stroke = 0.3, fill = pal$strike_fill, colour = pal$paper,
                       show.legend = FALSE) +
      ggplot2::scale_shape_manual(values = c(`at every plausible conductor height` = 21, `at some plausible height` = 21),
                                  name = "Strike trees", drop = FALSE,
                                  guide = ggplot2::guide_legend(
                                    order = 3, title.position = "top", ncol = 1, direction = "vertical",
                                    override.aes = list(fill = c(pal$strike_fill, pal$paper), size = 2.2,
                                                        colour = c(pal$paper, pal$strike_line))))
  }
  # Paper casing keeps every segment legible over dark canopy and markers.
  p <- p + ggplot2::geom_sf(data = seg, colour = pal$paper, linewidth = 2.2, lineend = "butt")
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
      scale_colour_vegrisk_encroach(limits = c(0, top), oob = scales::squish, na.value = pal$nodata, pal = pal,
                                    name = sprintf("Canopy in clearance envelope\nif conductor at code minimum (m%s)", sym$sq),
                                    breaks = scales::breaks_extended(4), guide = colour_bar(2))
  }
  p <- p +
    ggplot2::scale_linetype_manual(values = c(`measured / robust` = "solid", `bound-dependent` = "22",
                                              `insufficient LiDAR coverage` = "11"),
                                   guide = "none") +
    map_scale_bar(map_extent(seg, rasters$chm), m, pal)

  # Line type and marks are explained in words, only when used.
  notes <- character()
  if (!nrow(pos) && any(seg$zero)) {
    notes <- c(notes, paste0("No canopy in the clearance envelope on any ", if (any(gap)) "observed ", "segment (thin line)."))
  } else if (any(seg$zero)) notes <- c(notes, "Thin line: no canopy in the clearance envelope.")
  if (any(seg$certain == "bound-dependent")) notes <- c(notes, "Dashed segments: tier depends on the unknown conductor elevation.")
  if (any(gap)) notes <- c(notes, "Dotted segments: too little of the corridor observed to claim no risk.")
  if (!is.null(un)) {
    notes <- c(notes, sprintf("%s m%s unobserved by the LiDAR or left out as uncertain (grey; not bare ground).",
                              format(round(nrow(un) * prod(terra::res(rasters$unobserved)) * m^2), big.mark = ","),
                              sym$sq))
  }
  if (!is.null(st) && nrow(st) > 0) notes <- c(notes, "Crosses: supports used for the upper conductor bound.")
  p <- p +
    ggplot2::labs(title = title,
                  subtitle = paste(c(sprintf("Potential strike trees: %d at some plausible conductor height, %d at every plausible height.",
                                             sum(risk$trees$strike_possible), sum(risk$trees$strike_certain)),
                                     sprintf("%.0f m segments | %s | OSM line geometry", stats::median(seg$length_m), source),
                                     notes), collapse = "\n")) +
    map_frame(crs, seg)
  wh <- map_size(seg)
  save_or_return(p, file, wh[1], wh[2])
}

#' Ground and conductor profile along the line
#'
#' Where the conductor was classified from returns it is drawn as a line
#' (the per-5 m-bin elevation, interpolated across gaps of at most
#' `max_gap_m`); elsewhere the band between the code-minimum floor and the
#' chord between supports brackets it. The two never join: a switch between
#' measured and bounded is a break in the drawing, not a vertical in the
#' conductor. Strike trees, when `risk` is given, sit at their base
#' elevation along the line.
#'
#' @param profile Output of [conductor_profile()].
#' @param risk Output of [assess_risk()], optional; strike trees are drawn at
#'   their base elevation.
#' @param attach_m Attachment height used for the upper bound (for the
#'   subtitle).
#' @param line_id Which line of a multi-line corridor to draw; the first by
#'   default, with a message when others exist.
#' @param file Output PNG path, or `NULL`.
#' @export
plot_profile <- function(profile, risk = NULL, attach_m = NA, line_id = NULL, file = NULL) {
  rlang::check_installed("ggplot2")
  pal <- vegrisk_palette()
  lines <- unique(profile$line_id)
  if (is.null(line_id)) {
    line_id <- lines[1]
    if (length(lines) > 1) {
      rlang::inform(sprintf("plot_profile(): drawing line %s of %d; set `line_id` for another.", line_id, length(lines)))
    }
  }
  pr <- profile[profile$line_id == line_id, ]
  if (!nrow(pr)) rlang::abort(sprintf("No profile vertices for line_id %s.", line_id))
  pr$z_hi[is.infinite(pr$z_hi)] <- NA
  # Runs of the same source: measured and bounded stretches never connect.
  r <- rle(pr$src)
  pr$run <- rep(seq_along(r$lengths), r$lengths)
  meas <- pr[pr$src == "measured", ]
  bnd <- pr[pr$src == "bounded", ]
  frac <- mean(pr$src == "measured")
  title <- if (frac >= 0.995) "Conductor elevation: measured along the whole line"
           else if (frac <= 0.005) "Conductor elevation: bounded along the whole line"
           else sprintf("Conductor elevation: measured along %s%% of the line, bounded elsewhere",
                        format(signif(100 * frac, 2)))

  trees <- NULL
  if (!is.null(risk) && nrow(risk$trees) && any(risk$trees$strike)) {
    tr <- risk$trees[risk$trees$strike, ]
    m <- crs_m_per_unit(sf::st_crs(tr))
    pj <- line_project(sf::st_coordinates(tr)[, 1:2, drop = FALSE], profile, m)
    keep <- pj$line_id == line_id
    if (any(keep)) {
      trees <- data.frame(s_m = pj$s_m[keep], z = profile$ground[pj$vertex[keep]],
                          both = tr$strike_certain[keep])
    }
  }

  p <- ggplot2::ggplot(pr, ggplot2::aes(s_m)) +
    ggplot2::geom_ribbon(data = bnd, ggplot2::aes(ymin = z_lo, ymax = z_hi, group = run),
                         fill = pal$conductor, alpha = 0.16, na.rm = TRUE) +
    ggplot2::geom_line(data = bnd, ggplot2::aes(y = z_lo, group = run), colour = pal$conductor,
                       linewidth = 0.3, na.rm = TRUE) +
    ggplot2::geom_line(ggplot2::aes(y = ground), colour = pal$ink2) +
    ggplot2::geom_line(data = meas, ggplot2::aes(y = z_lo, group = run), colour = pal$conductor,
                       linewidth = 1.1, lineend = "round") +
    # Below the ground line at the start: nothing is ever drawn there.
    ggplot2::annotate("text", x = min(pr$s_m), y = pr$ground[1], label = "ground",
                      hjust = -0.1, vjust = 1.8, size = 3, colour = pal$ink2, family = pal$text_family)
  if (!is.null(trees)) {
    p <- p + ggplot2::geom_point(data = trees, ggplot2::aes(s_m, z, fill = both), shape = 24, size = 1.8,
                                 stroke = 0.3, colour = pal$ink, show.legend = FALSE) +
      ggplot2::scale_fill_manual(values = c(`TRUE` = pal$strike_fill, `FALSE` = pal$paper))
  }
  notes <- c(
    if (nrow(meas)) "Thick line: conductor from classified returns (5 m bins, interpolated across short gaps).",
    if (nrow(bnd)) paste0("Band: ground + NESC clearance (thin line) up to the chord between supports",
                          if (!is.na(attach_m)) sprintf(" at ground + %g m", attach_m) else "", "."),
    if (nrow(bnd) && any(is.na(pr$z_hi) & pr$src == "bounded")) "No band: the next support lies outside the data.",
    if (!is.null(trees)) sprintf("Triangles: %d potential strike trees at their base elevation (ink = at every plausible conductor height).",
                                 nrow(trees)),
    if (length(lines) > 1) sprintf("Line %s of %d.", line_id, length(lines))
  )
  p <- p +
    ggplot2::labs(title = title, subtitle = paste(notes, collapse = "\n"),
                  x = "Distance along line (m)", y = "Elevation (m)") +
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
#' @param line_id Which merged line of a multi-line corridor to cut; the
#'   first by default, with a message when others exist.
#' @export
plot_cross_section <- function(las, pred, lines, file = NULL, at = 0.5,
                               width_m = 4, half_len_m = 40, line_id = NULL) {
  rlang::check_installed("ggplot2")
  pal <- vegrisk_palette()
  m <- las_m_per_unit(las)
  parts <- merge_lines(sf::st_geometry(lines))
  if (is.null(line_id)) {
    line_id <- 1L
    if (length(parts) > 1) {
      rlang::inform(sprintf("plot_cross_section(): cutting line 1 of %d; set `line_id` for another.", length(parts)))
    }
  }
  ln <- parts[line_id]
  at <- min(max(at, 0), 1)
  # Tangent from two points either side of the cut (clamped inside the line),
  # so at = 0 or 1 still gives a direction.
  a0 <- max(at - 0.01, 0)
  a1 <- min(at + 0.01, 1)
  p0 <- sf::st_coordinates(sf::st_line_sample(ln, sample = at))[1, 1:2]
  q0 <- sf::st_coordinates(sf::st_line_sample(ln, sample = a0))[1, 1:2]
  q1 <- sf::st_coordinates(sf::st_line_sample(ln, sample = a1))[1, 1:2]
  u <- (q1 - q0) / sqrt(sum((q1 - q0)^2)) # along-line unit vector
  if (any(!is.finite(u))) rlang::abort("The line has no length at `at`; cannot orient the section.")
  v <- c(-u[2], u[1])                      # across-line unit vector (to the left of travel)
  compass <- function(vec) {
    b <- (atan2(vec[1], vec[2]) * 180 / pi) %% 360
    c("N", "NE", "E", "SE", "S", "SW", "W", "NW")[1 + (round(b / 45) %% 8)]
  }

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
    # show.legend = TRUE keeps a key for every class, present in the slab or not.
    ggplot2::geom_point(size = 0.35, alpha = 0.8, show.legend = TRUE) +
    scale_colour_vegrisk_class(name = NULL, drop = FALSE, pal = pal, labels = c(low = "low (<2 m)")) +
    ggplot2::guides(colour = ggplot2::guide_legend(override.aes = list(size = 3, alpha = 1), nrow = 1)) +
    ggplot2::coord_equal() +
    ggplot2::labs(title = "Classified point cloud, cross-section through the corridor",
                  subtitle = sprintf("%g m slab, %.0f%% along the line%s; random-forest predictions (ground from 3DEP)",
                                     width_m, 100 * at,
                                     if (length(parts) > 1) sprintf(" (line %d of %d)", line_id, length(parts)) else ""),
                  x = sprintf("Distance from mapped centreline (m): %s %s %s %s", compass(-v), sym$larr, sym$rarr, compass(v)),
                  y = "Elevation (m)") +
    theme_vegrisk()
  save_or_return(p, file, 8, 4.5)
}

#' Cross-validation metrics: spatial-block vs random folds
#'
#' Schemes are offset within each class row so none hides another; colours
#' are keyed by scheme name (a subset keeps its colours) and unknown schemes
#' are kept, drawn neutral, with a warning. Average precision below 0.01 is
#' printed to two significant figures, so 0.004 never reads as 0.00.
#'
#' @param metrics `metrics` element of [cv_point_classifier()], optionally
#'   with extra schemes (e.g. an ablation) stacked in.
#' @param file Output PNG path, or `NULL`.
#' @export
plot_cv <- function(metrics, file = NULL) {
  rlang::check_installed(c("ggplot2", "scales"))
  pal <- vegrisk_palette()
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
    theme_vegrisk() +
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
    ggplot2::geom_segment(ggplot2::aes(x = 0, xend = importance, yend = feature), colour = pal$rule, linewidth = 0.6) +
    ggplot2::geom_point(size = 2.2, colour = pal$highlight) +
    ggplot2::labs(title = "What the classifier relies on",
                  subtitle = "Permutation importance (increase in out-of-bag Brier score)", x = NULL, y = NULL) +
    theme_vegrisk() +
    ggplot2::theme(panel.grid.major.y = ggplot2::element_blank())
  save_or_return(p, file, 6, 3.5)
}

#' Map of dry-season canopy greenness and dry grown-in segments
#'
#' Scored Landsat pixels are drawn at their 30 m footprint on a sequential
#' greenness ramp (dry ochre to deep olive) with the `dry_canopy` cut marked
#' on the key; pixels the screen did not score (too little canopy, too
#' little LiDAR coverage, too few clear looks) are grey. Segments are
#' coloured by the combined screen under the chosen conductor bound.
#'
#' @param dryness Output of [canopy_dryness()].
#' @param bound `"hi"` (optimistic conductor, the default) or `"lo"`
#'   (pessimistic): which grow-in tier "grown in" refers to.
#' @param title Plot title; `NULL` states how many grown-in segments have
#'   dry canopy.
#' @param file Output PNG path, or `NULL`.
#' @export
plot_canopy_dryness <- function(dryness, bound = c("hi", "lo"), title = NULL, file = NULL) {
  rlang::check_installed(c("ggplot2", "scales"))
  bound <- match.arg(bound)
  pal <- vegrisk_palette()
  seg <- dryness$segments
  info <- attr(seg, "landsat")
  key <- info$dry_index
  crs <- sf::st_crs(seg)
  m <- crs_m_per_unit(crs)
  px <- cbind(sf::st_coordinates(dryness$pixels), sf::st_drop_geometry(dryness$pixels))
  px$value <- px[[key]]
  w <- 30 / m
  grow <- if (bound == "lo") seg$priority_lo == "grow-in" else seg$priority == "grow-in"
  dry_grow <- if (bound == "lo") seg$dry_grow_in_lo else seg$dry_grow_in
  lv <- c("dry and grown in", "dry canopy", "grown in", "neither", "no canopy pixels")
  seg$screen <- factor(ifelse(is.na(seg$dry_canopy), lv[5],
                       ifelse(dry_grow %in% TRUE, lv[1], ifelse(seg$dry_canopy, lv[2],
                       ifelse(grow, lv[3], lv[4])))), levels = lv)
  dates <- if (length(info$dates)) range(info$dates) else as.Date(c(NA, NA))
  if (is.null(title)) {
    title <- sprintf("%d of %d grown-in segments have canopy among the corridor's driest %.0f%%",
                     sum(dry_grow, na.rm = TRUE), sum(grow, na.rm = TRUE), 100 * info$dry_quantile)
  }
  scored <- px[px$scored, ]
  # The dry cut on the key: the value at `dry_quantile` of the scored pixels.
  cut <- if (nrow(scored)) stats::quantile(scored$value, info$dry_quantile, names = FALSE) else NA
  rng <- if (nrow(scored)) range(scored$value) else c(0, 1)
  brk <- pretty(rng, 3)
  brk <- brk[brk >= rng[1] & brk <= rng[2]]
  # Round ticks that would collide with the cut's label give way to it.
  if (!is.na(cut)) brk <- c(brk[abs(brk - cut) > 0.2 * diff(rng)], cut)
  brk <- round(sort(unique(brk)), 3)
  lab <- ifelse(!is.na(cut) & abs(brk - cut) < 1e-6, sprintf("%.2f\ndry cut", cut), formatC(brk, format = "f", digits = 2))

  p <- ggplot2::ggplot() +
    ggplot2::geom_tile(data = px[!px$scored, ], ggplot2::aes(X, Y), width = w, height = w,
                       fill = pal$nodata, colour = pal$paper, linewidth = 0.15) +
    ggplot2::geom_tile(data = scored, ggplot2::aes(X, Y, fill = value), width = w, height = w,
                       colour = pal$paper, linewidth = 0.15) +
    scale_fill_vegrisk_greenness(name = toupper(key), breaks = brk, labels = lab, pal = pal,
                                 guide = colour_bar(1)) +
    ggplot2::geom_sf(data = seg, colour = pal$paper, linewidth = 2.4, lineend = "butt") +
    ggplot2::geom_sf(data = seg, ggplot2::aes(colour = screen, linetype = screen), linewidth = 1.3,
                     lineend = "butt", show.legend = "line") +
    scale_colour_vegrisk_dryness(drop = FALSE, name = NULL, pal = pal,
                                 guide = ggplot2::guide_legend(order = 2, ncol = 1, direction = "vertical")) +
    ggplot2::scale_linetype_manual(values = c(`dry and grown in` = "solid", `dry canopy` = "solid",
                                              `grown in` = "solid", neither = "solid",
                                              `no canopy pixels` = "11"), drop = FALSE, name = NULL,
                                   guide = ggplot2::guide_legend(order = 2, ncol = 1, direction = "vertical")) +
    map_scale_bar(map_extent(seg, NULL), m, pal) +
    ggplot2::labs(title = title,
                  subtitle = sprintf(paste("Dry-season median of %d Landsat scenes, %s to %s.",
                                           "\nDry = segment in the lowest %.0f%% of the corridor's scored canopy pixels by %s.",
                                           "\nGrown in = %s-bound grow-in tier from LiDAR.",
                                           "\nGrey pixels not scored: < %.0f%% canopy, < %.0f%% observed by the LiDAR, or < %d clear looks."),
                                     length(info$scenes), format(dates[1], "%Y-%m"), format(dates[2], "%Y-%m"),
                                     100 * info$dry_quantile, toupper(key),
                                     if (bound == "lo") "pessimistic" else "optimistic",
                                     100 * info$min_canopy_frac, 100 * (info$min_coverage %||% 0), info$min_obs %||% 1L)) +
    map_frame(crs, seg)
  wh <- map_size(seg)
  save_or_return(p, file, wh[1], wh[2])
}

#' Strike trees the fire-weather winds would throw into the line
#'
#' Map of potential strike trees (under one conductor bound) coloured by the
#' share of fire-weather hours whose wind would push them into the line,
#' with the windward threshold marked on the key, over a faint canopy
#' height backdrop, beside a wind rose of those hours on a square-root
#' radius (so a sector with twice the share has twice the area).
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
  m <- crs_m_per_unit(crs)
  tr <- risk$trees[risk$trees[[paste0("strike_", bound)]], ]
  tr$hit <- tr[[paste0("wind_hit_", bound)]]
  tr <- tr[order(tr$hit), ]
  ww <- info$windward_min %||% 0.5
  n_ww <- sum(tr$hit >= ww, na.rm = TRUE)
  if (is.null(title)) {
    title <- sprintf("%d of %d potential strike trees stand where fire-weather winds would throw them into the line",
                     n_ww, nrow(tr))
  }

  # The canopy backdrop is one colour at varying opacity (darker = taller),
  # which leaves the fill scale to the strike-tree hit share.
  chm <- NULL
  if (!is.null(rasters)) {
    chm <- terra::as.data.frame(rasters$chm, xy = TRUE, na.rm = TRUE)
    names(chm)[3] <- "h"
  }
  p <- ggplot2::ggplot() +
    (if (!is.null(chm)) ggplot2::geom_raster(data = chm, ggplot2::aes(x, y, alpha = h), fill = pal$canopy_faint[2],
                                             show.legend = FALSE)) +
    ggplot2::scale_alpha_continuous(range = c(0.15, 1), limits = c(0, 30), oob = scales::squish, guide = "none") +
    ggplot2::geom_sf(data = risk$segments, colour = pal$paper, linewidth = 1.8, lineend = "butt") +
    ggplot2::geom_sf(data = risk$segments, colour = pal$line, linewidth = 0.6, lineend = "butt") +
    ggplot2::geom_sf(data = tr, ggplot2::aes(fill = hit), shape = 21, size = 1.9, stroke = 0.3,
                     colour = pal$ink) +
    scale_fill_vegrisk_wind(limits = c(0, 1), breaks = c(0, ww, 1),
                            labels = c("0%", sprintf("%.0f%% windward", 100 * ww), "100%"),
                            pal = pal, na.value = pal$nodata,
                            name = "Fire-weather hours that\nthrow the tree into the line",
                            guide = colour_bar(1)) +
    map_scale_bar(map_extent(risk$segments, rasters$chm), m, pal) +
    map_frame(crs, risk$segments)

  rose <- data.frame(dir = info$dir_from_deg)
  rose$sector <- factor(round(rose$dir / 22.5) %% 16, levels = 0:15)
  rose <- as.data.frame(table(sector = rose$sector))
  rose$share <- rose$Freq / sum(rose$Freq)
  rose$angle <- as.numeric(as.character(rose$sector)) * 22.5
  top <- rose[which.max(rose$share), ]
  r <- ggplot2::ggplot(rose, ggplot2::aes(angle, share)) +
    ggplot2::geom_col(width = 22.5, fill = pal$highlight, colour = pal$paper, linewidth = 0.2) +
    ggplot2::coord_polar(start = -pi / 16) +
    ggplot2::scale_x_continuous(limits = c(-11.25, 348.75), breaks = c(0, 90, 180, 270),
                                labels = c("N", "E", "S", "W")) +
    # Square-root radius: wedge area, which the eye reads, is proportional
    # to the share. The largest sector is labelled directly.
    ggplot2::scale_y_sqrt(breaks = NULL) +
    # The largest sector is labelled on its wedge, in paper so it reads on the fill.
    ggplot2::annotate("text", x = top$angle, y = top$share * 0.45, label = scales::percent(top$share, accuracy = 1),
                      size = 2.8, colour = pal$paper, family = pal$text_family) +
    ggplot2::labs(x = NULL, y = NULL, title = "Fire-weather winds come from") +
    theme_vegrisk(9) +
    ggplot2::theme(plot.title = ggplot2::element_text(size = 9, hjust = 0.5), aspect.ratio = 1,
                   panel.grid.major.y = ggplot2::element_blank(), plot.margin = ggplot2::margin(4, 4, 4, 4))

  sub <- sprintf(paste("%d hours with gusts %s %.0f m/s and RH %s %g%% (ERA5 reanalysis via Open-Meteo).",
                       "\nStrike trees under the %s conductor bound, over canopy height (darker = taller).",
                       "\nAn hour counts against a tree when its wind blows the tree within the arc of fall directions",
                       "that reach a conductor (%s%g%s fall scatter)."),
                 info$n_hours, sym$ge, info$min_gust_ms, sym$le, info$max_rh,
                 if (bound == "lo") "pessimistic (code-minimum)" else "optimistic", sym$pm, info$spread_deg, sym$deg)
  # The rose takes the top of a narrow right column; the map keeps the rest.
  # free(): the rose is not aligned with the map's legend rows, so it fills
  # its cell instead of inheriting the legend's height as a gap.
  out <- patchwork::wrap_plots(A = p, B = patchwork::free(r), design = "AB\nA#",
                               widths = c(3, 1), heights = c(1, 2.2)) +
    patchwork::plot_annotation(title = title, subtitle = sub, theme = theme_vegrisk())
  save_or_return(out, file, 10, 8)
}

save_or_return <- function(p, file, w, h) {
  if (is.null(file)) return(p)
  ggplot2::ggsave(file, p, width = w, height = h, dpi = 150, bg = vegrisk_palette()$paper)
  invisible(p)
}
