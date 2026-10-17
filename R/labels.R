# Weak (programmatic) training labels for above-ground points.
#
# 3DEP deliveries are usually classified only to ground / unclassified /
# noise, so there are no vegetation, wire, or building labels to learn from.
# Labels come from OSM layers and from column / along-line geometry:
#
#   building   - inside an OSM building footprint (shrunk inward so that
#                overhanging tree crowns at the eaves are not labelled roof)
#   structure  - within a small radius of an OSM pole/tower node
#   wire       - near a mapped line, elevated, with an "air gap" beneath it
#                across a 3 x 3 cell window, and part of a run of such cells
#                that extends along the line within one conductor row (so
#                parallel phases pass, while crown tops - which can also
#                pass the air-gap test - are compact and do not)
#   vegetation - every other above-ground point, excluding a margin around
#                the classes above and excluding elevated near-line
#                candidates that failed the wire test (those abstain)
#
# Points left NA are not used for training but are still classified by the
# model. The rules use height and empty space beneath a point, which the
# per-point features (height, echo structure, local shape) partly encode, so
# cross-validated accuracy against these labels measures how well the model
# recovers the rules, not agreement with ground truth (see README,
# "Limitations").

#' Assign weak labels to featurised points
#'
#' @param feat Output of [point_features()].
#' @param crs CRS of the point cloud.
#' @param lines,structures,buildings `sf` layers from OSM (any CRS).
#' @param cell_m 2D cell size for the air-gap test.
#' @param gap_floor_m Points below this height are ignored by the air-gap test
#'   (grass, fences, shrubs). Cannot be lower than the featurisation floor.
#' @param layer_m Maximum vertical thickness of a suspended cell's points
#'   (allows vertically stacked phases and a shield wire).
#' @param gap_m Depth of empty space required beneath a cell's lowest point
#'   across its 3 x 3 window.
#' @param wire_min_m Minimum height for a wire label.
#' @param wire_search_m Wire labels are only assigned within this horizontal
#'   distance of a mapped line (covers OSM misalignment and phase spacing).
#' @param run_half_m,row_m,min_run,min_extent_m,min_occupancy Along-line run
#'   test. For each candidate cell, its "row" is the candidates within
#'   `run_half_m` chainage and `row_m` perpendicular offset of it (one
#'   conductor; parallel phases form separate rows). The row qualifies if it
#'   has at least `min_run` cells, spans at least `min_extent_m` along the
#'   line, and occupies at least `min_occupancy` of the 1 m chainage bins
#'   across that span. All members of a qualifying row are wire.
#' @param structure_radius_m Radius around pole/tower nodes.
#' @param building_shrink_m Inward buffer applied to building footprints.
#' @param margin_m Width of the unlabelled margin around non-vegetation labels.
#' @return `feat` with a factor column `label` (levels vegetation, wire,
#'   structure, building; NA = unlabelled).
#' @export
weak_labels <- function(feat, crs, lines, structures = NULL, buildings = NULL,
                        cell_m = 1, gap_floor_m = 2, layer_m = 4, gap_m = 2,
                        wire_min_m = 6, wire_search_m = 12,
                        run_half_m = 10, min_run = 6, min_extent_m = 12,
                        row_m = 1.5, min_occupancy = 0.4,
                        structure_radius_m = 3, building_shrink_m = 1,
                        margin_m = 2) {
  m <- crs_m_per_unit(crs)
  feat <- data.table::copy(feat)
  pts <- sf::st_as_sf(feat[, c("X", "Y")], coords = c("X", "Y"), crs = crs)
  lab <- rep(NA_character_, nrow(feat))
  ambiguous <- rep(FALSE, nrow(feat))

  # --- wire: air gap + along-line run near a mapped line -------------------
  cs <- cell_m / m
  cand <- suspended_cells(feat, cs, gap_floor_m, layer_m, gap_m, wire_min_m)
  if (nrow(cand) > 0) {
    verts <- line_vertex_table(lines, crs)
    pr <- line_project(cbind((cand$cx + 0.5) * cs, (cand$cy + 0.5) * cs), verts, m)
    cand[, `:=`(line_id = pr$line_id, s_m = pr$s_m, offset_m = pr$offset_m)]
    cand <- cand[pr$dist_m <= wire_search_m]
    cand[, wire := along_line_run(line_id, s_m, offset_m, run_half_m, min_run,
                                  min_extent_m, row_m, min_occupancy)]
  } else {
    cand[, wire := logical()]
  }
  key <- feat[, paste(floor(X / cs), floor(Y / cs))]
  is_wire <- key %in% cand[wire == TRUE, paste(cx, cy)]
  # Elevated near-line candidates that failed the run test abstain rather
  # than becoming vegetation: they may be conductors the rule missed.
  abstain <- key %in% cand[wire == FALSE, paste(cx, cy)] & feat$height_m >= wire_min_m
  lab[is_wire] <- "wire"
  ambiguous <- ambiguous | abstain

  # Margin: points horizontally near a wire-labelled point but not wire
  # themselves are ambiguous (crown edges touching conductors, insulators).
  if (any(is_wire)) {
    nn <- FNN::get.knnx(as.matrix(feat[is_wire, c("X", "Y")]),
                        as.matrix(feat[, c("X", "Y")]), k = 1)
    ambiguous <- ambiguous | (nn$nn.dist[, 1] * m <= margin_m & !is_wire)
  }

  # --- structures -----------------------------------------------------------
  if (!is.null(structures) && nrow(structures) > 0) {
    s <- sf::st_coordinates(sf::st_transform(sf::st_geometry(structures), crs))
    d_s <- FNN::get.knnx(s[, 1:2, drop = FALSE], as.matrix(feat[, c("X", "Y")]), k = 1)$nn.dist[, 1] * m
    lab[d_s <= structure_radius_m] <- "structure"
    ambiguous <- ambiguous | (d_s > structure_radius_m & d_s <= structure_radius_m + margin_m)
  }

  # --- buildings ------------------------------------------------------------
  if (!is.null(buildings) && nrow(buildings) > 0) {
    b <- sf::st_union(sf::st_transform(sf::st_geometry(buildings), crs))
    core <- sf::st_buffer(b, -building_shrink_m / m)
    halo <- sf::st_buffer(b, margin_m / m)
    in_core <- lengths(sf::st_intersects(pts, core)) > 0
    in_halo <- lengths(sf::st_intersects(pts, halo)) > 0
    lab[in_core] <- "building"
    ambiguous <- ambiguous | (in_halo & !in_core)
  }

  # --- vegetation = everything else, outside margins --------------------------
  veg <- is.na(lab) & !ambiguous
  lab[veg] <- "vegetation"
  lab[ambiguous & !(lab %in% c("wire", "structure", "building"))] <- NA

  feat[, label := factor(lab, levels = label_levels)]
  feat[]
}

label_levels <- c("vegetation", "wire", "structure", "building")

# 2D cells whose points form an elevated layer at most `layer_m` thick, with
# nothing in the surrounding 3 x 3 window between `gap_floor_m` and `gap_m`
# below the cell's lowest point. Returns cx, cy (integer cell indices), zlo,
# zhi.
suspended_cells <- function(feat, cs, gap_floor_m, layer_m, gap_m, wire_min_m) {
  d <- feat[height_m >= gap_floor_m, .(cx = floor(X / cs), cy = floor(Y / cs), height_m)]
  cells <- d[, .(zlo = min(height_m), zhi = max(height_m)), by = .(cx, cy)]
  shifts <- expand.grid(i = -1:1, j = -1:1)
  win <- data.table::rbindlist(lapply(seq_len(nrow(shifts)), function(k) {
    cells[, .(cx = cx + shifts$i[k], cy = cy + shifts$j[k], zlo)]
  }))[, .(wmin = min(zlo)), by = .(cx, cy)]
  cells <- cells[win, on = c("cx", "cy"), nomatch = NULL]
  cells[zlo >= wire_min_m & (zhi - zlo) <= layer_m & wmin >= zlo - gap_m,
        .(cx, cy, zlo, zhi)]
}

# Logical per cell: is it part of a run of candidate cells that extends along
# the line (chainage) rather than forming a compact blob?
along_line_run <- function(line_id, s, offset, half, min_run, min_extent,
                           row_m, min_occupancy) {
  out <- logical(length(s))
  for (lid in unique(line_id)) {
    idx <- which(line_id == lid)
    o <- order(s[idx])
    ss <- s[idx][o]
    oo <- offset[idx][o]
    lo <- findInterval(ss - half, ss, left.open = TRUE) + 1L
    hi <- findInterval(ss + half, ss)
    rows <- lapply(seq_along(ss), function(i) {
      j <- lo[i]:hi[i]
      j[abs(oo[j] - oo[i]) <= row_m]
    })
    centre_ok <- vapply(rows, function(j) {
      if (length(j) < min_run) return(FALSE)
      ext <- max(ss[j]) - min(ss[j])
      ext >= min_extent && length(unique(floor(ss[j]))) / (floor(ext) + 1) >= min_occupancy
    }, logical(1))
    # Every member of a qualifying row window is wire (so run ends are kept).
    keep <- logical(length(ss))
    for (i in which(centre_ok)) keep[rows[[i]]] <- TRUE
    out[idx[o]] <- keep
  }
  out
}
