# Stable identity and spans (#53).
#
# A twin keys state on things that exist in the world: the structure, the
# span between two structures, the tree. Run-local ordinals (`seg_id`,
# `line_id`) and CRS-dependent coordinates are not stable across runs,
# epochs or deliveries, so this file adds: a canonical CRS per site, tree
# ids in it, an epoch-matching table, a structure table along each OSM way,
# spans between confirmed structures, chainage measured along the way
# rather than the clipped window, and a per-span roll-up of the 50 m
# station metrics.

#' Canonical projected CRS for a site
#'
#' NAD83(2011) / UTM, zone from the longitude of the object's centroid
#' (EPSG 6329 + zone: Colorado is 6342, middle Tennessee 6345), so ids and
#' stored coordinates agree whatever CRS a delivery arrived in, including
#' State Plane US survey feet.
#'
#' @param x An `sf`/`sfc` object, bbox or anything with a CRS and extent.
#' @return An `sf::st_crs()` object.
#' @export
canonical_crs <- function(x) {
  bb <- sf::st_bbox(x)
  centre <- sf::st_sfc(sf::st_point(c(mean(bb[c("xmin", "xmax")]), mean(bb[c("ymin", "ymax")]))), crs = sf::st_crs(x))
  c4326 <- sf::st_coordinates(sf::st_transform(centre, 4326))
  zone <- floor((c4326[1, 1] + 180) / 6) + 1
  if (c4326[1, 2] < 0) rlang::abort("canonical_crs() covers the northern hemisphere only.")
  sf::st_crs(6329L + as.integer(zone))
}

#' Stable tree ids from a canonical-CRS position
#'
#' `<epsg>:<x>:<y>` with x and y the half-metre cell of the canonical CRS, so the
#' same treetop has the same id from a UTM-metre and a State-Plane-feet
#' delivery, and ids from different zones cannot collide.
#'
#' @param xy Two-column matrix of coordinates in `crs`.
#' @param crs Their CRS.
#' @param canonical Target CRS; by default [canonical_crs()] of the points.
#' @return Character vector of ids.
#' @export
tree_ids <- function(xy, crs, canonical = NULL) {
  pts <- sf::st_as_sf(as.data.frame(xy), coords = c(1, 2), crs = crs)
  if (is.null(canonical)) canonical <- canonical_crs(pts)
  c2 <- sf::st_coordinates(sf::st_transform(pts, canonical))
  # Half-metre cells by floor: a point near a cell edge can land on either
  # side after a reprojection, which match_trees() tolerates; round() would
  # add the same ambiguity at every .25 and .75 as well.
  sprintf("%d:%.0f:%.0f", canonical$epsg, floor(c2[, 1] * 2), floor(c2[, 2] * 2))
}

#' Match treetops between two epochs
#'
#' Nearest neighbour from `a` to `b` within `tol_m`, one match per tree of
#' `a`, with the height change. Trees of `a` with no neighbour within the
#' tolerance are listed with `NA`, so "gone" is recorded, not dropped.
#'
#' @param a,b `sf` POINT layers with `tree_id` and `height_m` (any CRS).
#' @param tol_m Largest distance that counts as the same tree.
#' @return A data frame: `id_a`, `id_b`, `distance_m`, `dh_m` (b minus a).
#' @export
match_trees <- function(a, b, tol_m = 2) {
  if (nrow(a) == 0) return(data.frame(id_a = character(), id_b = character(), distance_m = numeric(), dh_m = numeric()))
  crs <- canonical_crs(a)
  pa <- sf::st_coordinates(sf::st_transform(a, crs))[, 1:2, drop = FALSE]
  if (nrow(b) == 0) {
    return(data.frame(id_a = a$tree_id, id_b = NA_character_, distance_m = NA_real_, dh_m = NA_real_))
  }
  pb <- sf::st_coordinates(sf::st_transform(b, crs))[, 1:2, drop = FALSE]
  nn <- FNN::get.knnx(pb, pa, k = 1)
  hit <- nn$nn.dist[, 1] <= tol_m
  j <- nn$nn.index[, 1]
  data.frame(id_a = a$tree_id,
             id_b = ifelse(hit, b$tree_id[j], NA_character_),
             distance_m = ifelse(hit, nn$nn.dist[, 1], NA_real_),
             dh_m = ifelse(hit, b$height_m[j] - a$height_m, NA_real_))
}

#' Structures along each OSM way, with stable ids and way chainage
#'
#' One row per vertex of each input way (unclipped: clipping adds end
#' points that are not structures). A vertex is *confirmed* when a tagged
#' pole or tower lies within `tol_m` of it, and takes that node's OSM id as
#' `structure_id` (`"S<osm id>"`); an unconfirmed vertex is keyed by its way
#' and position (`"V<way id>:<index>"`). `use` marks the vertices that
#' define spans and the upper conductor bound: the confirmed ones, or every
#' vertex with a warning when the way has none.
#'
#' @param lines `sf` lines with `osm_id` (one row per OSM way).
#' @param structures `sf` points of tagged structures with `osm_id` and
#'   optionally `type`; any CRS; may be `NULL`.
#' @param crs Projected CRS for the output.
#' @param tol_m Distance within which a structure node confirms a vertex.
#' @return `sf` POINT with `structure_id`, `way_id`, `line_id` (row of
#'   `lines`), `vertex`, `s_m` (chainage along the way, metres),
#'   `confirmed`, `use`, `type`.
#' @export
line_structures <- function(lines, structures = NULL, crs = sf::st_crs(lines), tol_m = 2) {
  m <- crs_m_per_unit(crs)
  lines <- sf::st_transform(lines, crs)
  way_ids <- if ("osm_id" %in% names(lines)) as.character(lines$osm_id) else as.character(seq_len(nrow(lines)))
  sxy <- NULL
  if (!is.null(structures) && nrow(structures) > 0) {
    sxy <- sf::st_coordinates(sf::st_transform(sf::st_geometry(structures), crs))[, 1:2, drop = FALSE]
  }
  rows <- lapply(seq_len(nrow(lines)), function(i) {
    xy <- sf::st_coordinates(sf::st_geometry(lines)[i])[, 1:2, drop = FALSE]
    xy <- xy[c(TRUE, rowSums(abs(diff(xy))) > 0), , drop = FALSE]
    s <- c(0, cumsum(sqrt(rowSums(diff(xy)^2)))) * m
    out <- data.frame(structure_id = sprintf("V%s:%d", way_ids[i], seq_len(nrow(xy))),
                      way_id = way_ids[i], line_id = i, vertex = seq_len(nrow(xy)), s_m = s,
                      confirmed = FALSE, use = FALSE, type = NA_character_, x = xy[, 1], y = xy[, 2],
                      stringsAsFactors = FALSE)
    if (!is.null(sxy)) {
      nn <- FNN::get.knnx(sxy, xy, k = 1)
      hit <- nn$nn.dist[, 1] * m <= tol_m
      j <- nn$nn.index[, 1]
      out$confirmed <- hit
      out$structure_id[hit] <- paste0("S", as.character(structures$osm_id)[j[hit]])
      if ("type" %in% names(structures)) out$type[hit] <- as.character(structures$type)[j[hit]]
    }
    if (any(out$confirmed)) {
      out$use <- out$confirmed
    } else {
      rlang::warn(sprintf(paste("Way %s: no tagged structure coincides with a vertex;",
                                "every vertex is treated as a support."), way_ids[i]))
      out$use <- TRUE
    }
    out
  })
  out <- do.call(rbind, rows)
  sf::st_as_sf(out, coords = c("x", "y"), crs = crs)
}

#' Spans between confirmed structures of each OSM way
#'
#' Splits each way at its `use` structures (see [line_structures()]) into
#' spans keyed by their end structures. A span longer than `max_span_m` is
#' flagged `implausible`: a structure is probably missing from the map, and
#' the upper conductor bound should not be trusted there.
#'
#' @inheritParams line_structures
#' @param max_span_m Longest plausible span. By default 600 m for lines of
#'   69 kV and above (or unknown voltage), 150 m below.
#' @return `sf` LINESTRING with `span_id` (`"<from>><to>"`),
#'   `from_structure_id`, `to_structure_id`, `way_id`, `line_id`,
#'   `s_from_m`, `s_to_m` (along the way), `length_m`, `implausible`, and
#'   the way's `osm_id`, `name`, `voltage_kv`, `operator` and `power` where
#'   present.
#' @export
line_spans <- function(lines, structures = NULL, crs = sf::st_crs(lines), max_span_m = NULL, tol_m = 2) {
  m <- crs_m_per_unit(crs)
  lines <- sf::st_transform(lines, crs)
  st <- line_structures(lines, structures, crs, tol_m)
  keep <- intersect(c("osm_id", "name", "voltage_kv", "operator", "power"), names(lines))
  rows <- lapply(seq_len(nrow(lines)), function(i) {
    g <- sf::st_geometry(lines)[i]
    len <- as.numeric(sf::st_length(g)) * m
    s <- st[st$line_id == i & st$use, ]
    s <- s[order(s$s_m), ]
    if (nrow(s) < 2) return(NULL)
    vmax <- if (!is.null(max_span_m)) max_span_m else {
      kv <- if ("voltage_kv" %in% names(lines)) lines$voltage_kv[i] else NA
      if (is.na(kv) || kv >= 69) 600 else 150
    }
    k <- seq_len(nrow(s) - 1)
    geom <- do.call(c, lapply(k, function(j) {
      lwgeom::st_linesubstring(g, s$s_m[j] / len, s$s_m[j + 1] / len)
    }))
    out <- sf::st_sf(
      span_id = paste(s$structure_id[k], s$structure_id[k + 1], sep = ">"),
      from_structure_id = s$structure_id[k], to_structure_id = s$structure_id[k + 1],
      way_id = s$way_id[1], line_id = i, s_from_m = s$s_m[k], s_to_m = s$s_m[k + 1],
      length_m = s$s_m[k + 1] - s$s_m[k], geometry = geom
    )
    out$implausible <- out$length_m > vmax
    for (col in keep) out[[col]] <- lines[[col]][i]
    out
  })
  rows <- Filter(Negate(is.null), rows)
  if (length(rows) == 0) {
    return(sf::st_sf(span_id = character(), from_structure_id = character(), to_structure_id = character(),
                     way_id = character(), line_id = integer(), s_from_m = numeric(), s_to_m = numeric(),
                     length_m = numeric(), implausible = logical(), geometry = sf::st_sfc(crs = crs)))
  }
  do.call(rbind, rows)
}

#' Chainage of points along the OSM ways
#'
#' @param xy Two-column matrix in `crs`.
#' @param lines The unclipped ways (`sf`), in any CRS.
#' @param crs CRS of `xy`.
#' @return data.frame with `line_id` (row of `lines`) and `s_way_m`.
#' @keywords internal
way_chainage <- function(xy, lines, crs) {
  m <- crs_m_per_unit(crs)
  verts <- line_vertex_table(sf::st_transform(sf::st_geometry(lines), crs), crs)
  # line_vertex_table() merges; recover the input row by nearest line.
  p <- line_project(xy, verts, m)
  row <- sf::st_nearest_feature(sf::st_as_sf(as.data.frame(xy), coords = c(1, 2), crs = crs),
                                sf::st_transform(lines, crs))
  data.frame(line_id = row, s_way_m = p$s_m)
}

#' Roll segment metrics up to spans
#'
#' Each segment belongs to the span that contains its midpoint along the
#' way. Per span: the worst tier (grow-in > fall-in > no data > none) under
#' each bound, the worst confidence (low coverage > bound-dependent >
#' robust > measured), summed encroachment areas and strike counts, the
#' minimum clearance, length-weighted `frac_measured`, minimum coverage,
#' and the flight window when the segments carry one.
#'
#' @param segments Output of [assess_risk()] (`$segments`).
#' @param spans Output of [line_spans()].
#' @param lines The unclipped ways the spans came from.
#' @return `spans` with the metrics joined; spans with no segment keep
#'   `n_segments = 0` and `NA` metrics.
#' @export
span_summary <- function(segments, spans, lines) {
  crs <- sf::st_crs(segments)
  m <- crs_m_per_unit(crs)
  spans <- sf::st_transform(spans, crs)
  seg <- sf::st_drop_geometry(segments)
  mid <- sf::st_coordinates(sf::st_line_sample(sf::st_cast(sf::st_geometry(segments), "LINESTRING"), sample = 0.5))
  wc <- way_chainage(mid[, 1:2, drop = FALSE], lines, crs)
  sp <- sf::st_drop_geometry(spans)
  seg$span_id <- vapply(seq_len(nrow(seg)), function(i) {
    cand <- which(sp$line_id == wc$line_id[i] & sp$s_from_m <= wc$s_way_m[i] & sp$s_to_m >= wc$s_way_m[i])
    if (length(cand)) sp$span_id[cand[1]] else NA_character_
  }, "")
  tiers <- c("grow-in", "fall-in", "no data", "none")
  confs <- c("low coverage", "bound-dependent", "robust", "measured")
  worst <- function(x, lv) { x <- as.character(x); x <- x[!is.na(x)]; if (!length(x)) NA_character_ else lv[min(match(x, lv))] }
  sum0 <- function(x) if (all(is.na(x))) NA_real_ else sum(x, na.rm = TRUE)
  min0 <- function(x) if (all(is.na(x))) NA_real_ else min(x, na.rm = TRUE)
  has_time <- "flight_from" %in% names(seg)
  agg <- lapply(split(seg, seg$span_id), function(d) {
    w <- d$length_m / sum(d$length_m)
    data.frame(
      span_id = d$span_id[1], n_segments = nrow(d),
      priority = worst(d$priority, tiers), priority_lo = worst(d$priority_lo, tiers),
      confidence = worst(d$confidence, confs),
      frac_measured = sum(w * d$frac_measured), frac_observed = min0(d$frac_observed),
      encroach_lo_m2 = sum0(d$encroach_lo_m2), encroach_hi_m2 = sum0(d$encroach_hi_m2),
      min_clearance_lo_m = min0(d$min_clearance_lo_m), min_clearance_hi_m = min0(d$min_clearance_hi_m),
      n_strike_possible = sum0(d$n_strike_possible), n_strike_certain = sum0(d$n_strike_certain),
      flight_from = if (has_time) min(d$flight_from, na.rm = TRUE) else as.POSIXct(NA, tz = "UTC"),
      flight_to = if (has_time) max(d$flight_to, na.rm = TRUE) else as.POSIXct(NA, tz = "UTC"),
      stringsAsFactors = FALSE)
  })
  agg <- do.call(rbind, agg)
  out <- merge(spans, agg, by = "span_id", all.x = TRUE)
  out$n_segments[is.na(out$n_segments)] <- 0L
  out$priority <- factor(out$priority, levels = tiers)
  out$priority_lo <- factor(out$priority_lo, levels = tiers)
  out$confidence <- factor(out$confidence, levels = rev(confs))
  attr(out, "segment_span") <- seg[, c("seg_id", "span_id")]
  out[order(out$line_id, out$s_from_m), ]
}
