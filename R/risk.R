# Corridor vegetation-risk metrics.
#
# Two failure modes are screened (both standard in utility integrated
# vegetation management):
#
#   grow-in  - canopy under the conductors closer than a clearance target
#   fall-in  - a tree beside the conductors tall enough to reach one if it
#              falls ("strike tree")
#
# Fall-in geometry: a tree of height h pivoting at its base sweeps a sphere
# of radius h, so it can strike the line if the 3D distance from its base to
# the nearest conductor point is <= h (+ growth allowance). "Nearest" is the
# minimum over every conductor vertex the tree could reach, not the vertex
# at the tree's own station: on a sloping or sagging span the conductor a
# few metres along the line is often closer in 3D (#19). The vertical
# component uses the DTM at the tree and the modelled conductor elevation, so
# terrain matters: a tree whose base sits a little below the conductor (e.g.
# on a canyon wall above a low span) needs far less height to reach it than
# the same tree on flat ground.
#
# Conductor elevation is the dominant uncertainty. Where the classifier finds
# conductor returns it is measured; elsewhere it is bracketed (see
# conductor_profile()) and every metric is computed under both bounds.

#' Split power lines into equal-length segments
#'
#' @param lines `sf` lines (any CRS).
#' @param crs Projected CRS for the output.
#' @param seg_m Target segment length in metres. Each line is split into
#'   `floor(length / seg_m)` equal segments, so segments are between `seg_m`
#'   and `2 * seg_m` long.
#' @param ways Optional `sf` of the unclipped OSM ways the lines were cut
#'   from; when given, each segment also gets its chainage along the way.
#' @return `sf` with `seg_id`, `line_id` (one per merged line, numbered in
#'   the order of the first input feature touching each, not union order),
#'   `s_from_m` / `s_to_m` (chainage of the segment's ends along its merged
#'   line, metres), `length_m`, and, when `lines` is an `sf` carrying them,
#'   `osm_id`, `name`, `voltage_kv` and `operator` of the input line the
#'   segment's midpoint lies on, so a segment can be traced back to the OSM
#'   way it came from. With `ways =` (the unclipped OSM ways), each segment
#'   also gets `s_way_from_m` / `s_way_to_m`: chainage along the way itself,
#'   which does not move when the study window or the data extent changes.
#' @export
segment_lines <- function(lines, crs, seg_m = 50, ways = NULL) {
  m <- crs_m_per_unit(crs)
  src <- if (inherits(lines, "sf")) sf::st_transform(lines, crs) else NULL
  parts <- merge_lines(sf::st_transform(sf::st_geometry(lines), crs))
  if (!is.null(src) && nrow(src) > 1 && length(parts) > 1) {
    first <- vapply(seq_along(parts), function(i) {
      hit <- which(lengths(sf::st_intersects(sf::st_geometry(src), parts[i])) > 0)
      if (length(hit)) min(hit) else NA_integer_
    }, 1L)
    parts <- parts[order(first)]
  }
  out <- lapply(seq_along(parts), function(i) {
    len <- as.numeric(sf::st_length(parts[i])) * m
    n <- max(1L, floor(len / seg_m))
    br <- seq(0, 1, length.out = n + 1)
    g <- do.call(c, lapply(seq_len(n), function(j) lwgeom::st_linesubstring(parts[i], br[j], br[j + 1])))
    sf::st_sf(line_id = i, s_from_m = br[-length(br)] * len, s_to_m = br[-1] * len, geometry = g)
  })
  out <- do.call(rbind, out)
  out$seg_id <- seq_len(nrow(out))
  out$length_m <- as.numeric(sf::st_length(out)) * m
  cols <- c("seg_id", "line_id", "s_from_m", "s_to_m", "length_m")
  keep <- if (is.null(src)) character() else intersect(c("osm_id", "name", "voltage_kv", "operator"), names(src))
  if (length(keep)) {
    mid <- sf::st_line_sample(sf::st_cast(sf::st_geometry(out), "LINESTRING"), sample = 0.5)
    nn <- sf::st_nearest_feature(mid, src)
    for (k in keep) out[[k]] <- sf::st_drop_geometry(src)[[k]][nn]
    cols <- c(cols, keep)
  }
  if (!is.null(ways)) {
    ends <- lapply(sf::st_geometry(out), function(g) { xy <- sf::st_coordinates(g); xy[c(1, nrow(xy)), 1:2] })
    a <- way_chainage(do.call(rbind, lapply(ends, `[`, 1, )), ways, crs)
    b <- way_chainage(do.call(rbind, lapply(ends, `[`, 2, )), ways, crs)
    out$s_way_from_m <- pmin(a$s_way_m, b$s_way_m)
    out$s_way_to_m <- pmax(a$s_way_m, b$s_way_m)
    cols <- c(cols, "s_way_from_m", "s_way_to_m")
  }
  out[, c(cols, "geometry")]
}

#' Build terrain and vegetation-only canopy height rasters
#'
#' The canopy height model (CHM) is built from *consensus* vegetation: points
#' the classifier predicts as vegetation and the weak-label rules also call
#' vegetation. Points the rules labelled wire / structure / building, and the
#' unlabelled margins and abstained near-line candidates, are left out. The
#' prior-corrected classifier rarely predicts the rare classes, so using its
#' argmax alone would let conductor returns over canopy set the CHM to the
#' conductor's height - zero clearance by construction.
#'
#' Conductor returns that cross over canopy are not "suspended" (there is
#' canopy below them), so the rules can label them vegetation. When a
#' conductor `profile` is supplied, points are excluded as conductor returns
#' only if they are (a) within `envelope_m` of the centreline where the
#' conductor is measured, (b) at or above the measured conductor elevation
#' minus `below_m`, and (c) wire-like: either locally linear
#' (`linearity_k10 >= min_linearity`) or locally suspended - no return of
#' any kind in the `gap_m` layer just beneath the conductor band (measured
#' conductor elevation minus `below_m`) within its 3 x 3 m neighbourhood
#' (bundled conductors form ribbons, not lines, so linearity alone misses
#' them). A tree crown that reaches wire height has foliage below it and
#' stays in the canopy model, as does canopy within `gap_m` of a conductor
#' (which the clearance target flags anyway). Keep `envelope_m` no wider
#' than the grow-in zone used in [assess_risk()], or tall side trees could
#' lose their tops before the fall-in test.
#'
#' A cell with no canopy is bare ground only if the LiDAR saw it as such.
#' Cells are returned as `unobserved` (unknown, not bare ground) when either
#'
#' * they held points kept out of the canopy model whose class is uncertain -
#'   unlabelled points (the margins around wire / structure / building labels
#'   and abstained near-line candidates), points the classifier and the rules
#'   disagree on, and conductor-envelope exclusions - and no canopy remains; or
#' * they are LiDAR voids: no return of any class within a `void_m` square
#'   window (missing or truncated tiles, water, dropouts). The TIN terrain
#'   model interpolates straight across voids, so they would otherwise read as
#'   bare ground.
#'
#' Points the rules labelled wire, structure or building are not uncertain:
#' a wire label requires an observed air gap beneath it, and structures and
#' buildings are not canopy.
#'
#' @param las Height-normalised `LAS` from [read_corridor()].
#' @param pred Output of [predict_points()] (with the weak `label` column and
#'   the linearity feature named by `linearity`).
#' @param res_m Raster resolution in metres.
#' @param profile Optional output of [conductor_profile()].
#' @param envelope_m Half-width of the conductor envelope (metres).
#' @param below_m Depth below the measured conductor still treated as
#'   conductor returns (sag between bins, bundle spacing).
#' @param min_linearity Linearity needed for an envelope point to count as a
#'   conductor return.
#' @param linearity Name of the linearity column in `pred` used for that
#'   test. By default the smallest neighbourhood [point_features()] recorded
#'   on `pred` (`linearity_k10` for the default `k`); an absent column is an
#'   error, never silently "not linear".
#' @param gap_m Empty space beneath a candidate cluster for it to count as
#'   suspended.
#' @param drop Optional logical vector over `pred` rows of points to keep out
#'   of the canopy model (e.g. vendor-classified buildings). These are known
#'   not to be canopy, so they do not make a cell unobserved.
#' @param void_m Width of the square window (metres) that must contain no
#'   LiDAR return of any class for a cell to count as a void. Wide enough
#'   that ordinary point spacing never empties it (3DEP QL2 is >= 2 pts/m^2).
#' @return A list with `dtm` (ground elevation) and `chm` (canopy height),
#'   both `SpatRaster` in metres, `unobserved` (logical `SpatRaster`), `void`
#'   (logical `SpatRaster`, the voids alone), `n_conductor_excluded` and
#'   `n_uncertain_excluded` (points left out of the canopy model as uncertain,
#'   conductor exclusions included).
#' @export
corridor_rasters <- function(las, pred, res_m = 1, profile = NULL, envelope_m = 15,
                             below_m = 1, min_linearity = 0.6, gap_m = 1.5, drop = NULL,
                             void_m = 5, linearity = NULL) {
  pred <- as_point_table(pred, "pred")
  m <- las_m_per_unit(las)
  res <- res_m / m
  dtm <- lidR::rasterize_terrain(lidR::unnormalize_height(las), res, lidR::tin())
  consensus <- pred$pred == "vegetation" & pred$label %in% "vegetation"
  if (!is.null(drop)) consensus <- consensus & !drop
  # Kept out of the canopy model without being known non-canopy.
  uncertain <- !consensus & !(pred$label %in% c("wire", "structure", "building"))
  if (!is.null(drop)) uncertain <- uncertain & !drop
  hit_rows <- integer()
  if (!is.null(profile) && any(profile$src == "measured")) {
    cand <- which(consensus)
    pr <- line_project(as.matrix(pred[cand, c("X", "Y")]), profile, m)
    zabs <- las$Zref[pred$pid[cand]] * m
    meas <- profile$src[pr$vertex] == "measured"
    near <- meas & pr$dist_m <= envelope_m & zabs >= profile$z_lo[pr$vertex] - below_m
    if (is.null(linearity)) linearity <- paste0("linearity_k", min(attr(pred, "k") %||% 10L))
    if (!linearity %in% names(pred)) {
      rlang::abort(sprintf("`pred` has no `%s` column; pass `linearity` to name the linearity feature.",
                           linearity))
    }
    linear <- pred[[linearity]][cand] >= min_linearity
    # Local air gap beneath the conductor band: a candidate cell is
    # suspended if no return of any kind lies in the `gap_m` layer just below
    # the band (conductor - below_m) anywhere in its 3 x 3 neighbourhood.
    # Bundle sub-conductors sit inside the band, so they do not fill the gap;
    # a crown reaching wire height does.
    cs <- 1 / m
    band <- profile$z_lo[pr$vertex] - below_m
    allp <- data.table::data.table(cx = floor(pred$X / cs), cy = floor(pred$Y / cs),
                                   z = las$Zref[pred$pid] * m)
    cc <- data.table::data.table(cx = floor(pred$X[cand][near] / cs),
                                 cy = floor(pred$Y[cand][near] / cs), zb = band[near])
    cc <- cc[, .(zb = min(zb)), by = .(cx, cy)]
    win <- data.table::rbindlist(lapply(-1:1, function(i) lapply(-1:1, function(j) {
      cc[, .(cx, cy, nx = cx + i, ny = cy + j, zb)]
    })) |> unlist(recursive = FALSE))
    hits <- allp[win, on = c(cx = "nx", cy = "ny"), allow.cartesian = TRUE, nomatch = NULL,
                 .(ocx = i.cx, ocy = i.cy, z = x.z, zb = i.zb)]
    filled <- unique(hits[z < zb & z >= zb - gap_m, .(ocx, ocy)])
    cc[, gap := Inf]
    cc[filled, gap := 0, on = c(cx = "ocx", cy = "ocy")]
    ck <- paste(floor(pred$X[cand][near] / cs), floor(pred$Y[cand][near] / cs))
    gap <- stats::setNames(cc$gap, paste(cc$cx, cc$cy))
    suspended <- rep(FALSE, length(cand))
    suspended[near] <- gap[ck] >= gap_m
    hit <- near & (linear | suspended)
    hit_rows <- cand[hit]
    consensus[hit_rows] <- FALSE
    uncertain[hit_rows] <- TRUE
  }
  if (any(consensus)) {
    veg <- las[pred$pid[consensus]]
    chm <- lidR::rasterize_canopy(veg, res, lidR::p2r(subcircle = 0.15 / m))
    chm <- terra::crop(terra::extend(chm, dtm), dtm)
  } else { # no canopy anywhere (e.g. a cleared corridor)
    chm <- terra::setValues(dtm, NA_real_)
  }

  excluded <- terra::setValues(dtm, FALSE)
  cells <- terra::cellFromXY(dtm, as.matrix(pred[which(uncertain), c("X", "Y")]))
  excluded[unique(stats::na.omit(cells))] <- TRUE
  # Voids: returns of any class (ground included) per cell, summed over the
  # window; NA-padding at the raster edge is ignored.
  n_ret <- tabulate(stats::na.omit(terra::cellFromXY(dtm, cbind(las$X, las$Y))),
                    nbins = terra::ncell(dtm))
  w <- 2L * floor(void_m / res_m / 2) + 1L # odd window, no wider than void_m
  void <- terra::focal(terra::setValues(dtm, n_ret), w = w, fun = "sum", na.rm = TRUE) == 0
  unobserved <- (excluded & is.na(chm)) | void
  # Z is assumed to share the horizontal unit (true for both case studies).
  list(dtm = dtm * m, chm = chm * m, unobserved = unobserved, void = void,
       n_conductor_excluded = length(hit_rows), n_uncertain_excluded = sum(uncertain))
}

#' Model conductor elevation along the line
#'
#' Conductor returns are points the wire rule labelled (`label == "wire"`) or
#' that the classifier calls wire with probability >= `min_p_wire`. Returns
#' within `structure_mask_m` of a support are ignored (guy wires, crossarms
#' and insulators there are elevated and linear too). Each `bin_m` chainage
#' bin takes a low quantile (`q`) of return elevations; bins below the lower
#' bound (physically non-compliant, so an artefact) or implying a slope
#' steeper than `max_slope` to both neighbours are rejected. Surviving bins
#' are interpolated across gaps of at most `max_gap_m` (`src = "measured"`).
#' Elsewhere the conductor is bracketed (`src = "bounded"`):
#'
#' * lower bound: ground + `min_ground_clear_m`. NESC Table 232-1 vertical
#'   clearance for a 115 kV line is roughly 4.9 m over land accessible only
#'   to pedestrians (more over roads), so a compliant line is not lower.
#' * upper bound: with `supports`, the straight chord between the supports
#'   either side of a station, each at ground + `attach_m`. A conductor sags
#'   below the chord between its attachments, so it cannot be higher unless
#'   attachments exceed `attach_m`. Where the next support lies outside the
#'   data the upper bound is unknown and set to `Inf` (no optimistic claim).
#'   Without `supports`, the highest chord between any two points no more
#'   than `max_span_m` apart is used, which is only an upper bound if real
#'   spans are no longer than that.
#'
#' A terrain-following model (constant height above the ground below) is
#' wrong where a span crosses a gully; the bounds make that uncertainty
#' explicit instead of hiding it.
#'
#' @param pred Output of [predict_points()].
#' @param segments Output of [segment_lines()].
#' @param dtm Ground elevation raster (metres), from [corridor_rasters()].
#' @param supports Optional `sf` points of support structures.
#' @param step_m Vertex spacing of the conductor model (metres).
#' @param search_m Wire points farther than this from the line are ignored.
#' @param min_p_wire Classifier probability needed for a point the rule did
#'   not label to count as a conductor return.
#' @param structure_mask_m Returns this close to a support are ignored.
#' @param bin_m,min_bin_points,q Chainage bin width, minimum returns per bin,
#'   and the quantile of return elevations used per bin.
#' @param max_slope Maximum plausible conductor slope (rise / run) between
#'   adjacent measured bins.
#' @param max_gap_m Largest gap between measured bins that is interpolated.
#' @param min_ground_clear_m,attach_m,max_span_m Bounds parameters, metres.
#' @return data.frame of vertices: `line_id`, `x`, `y`, `tx`, `ty` (unit
#'   tangent along the line), `s_m`, `seg_id`, `ground`, `z_lo`, `z_hi`,
#'   `src`. The attribute `bins` is a data frame with one row per line
#'   counting the chainage bins that held conductor returns (`n_bins`) and
#'   how many each sanity check rejected (`n_too_few`, `n_below_floor`,
#'   `n_implausible`), with `n_measured` the bins that survived and
#'   `n_above_upper_bound` the measured bins that sit above the support
#'   chord (kept, but a sign that the support set or `attach_m` is wrong),
#'   so a profile that silently lost most of its returns can be told from
#'   one that never had them.
#' @export
conductor_profile <- function(pred, segments, dtm, supports = NULL, step_m = 1,
                              search_m = 15, min_p_wire = 0.9, structure_mask_m = 8,
                              bin_m = 5, min_bin_points = 3, q = 0.25, max_slope = 0.2,
                              max_gap_m = 30, min_ground_clear_m = 4.9, attach_m = 20,
                              max_span_m = 500) {
  pred <- as_point_table(pred, "pred")
  crs <- sf::st_crs(segments)
  m <- crs_m_per_unit(crs)
  v <- line_vertex_table(segments, crs, step_m)
  nearest_seg <- sf::st_nearest_feature(sf::st_as_sf(v[, c("x", "y")], coords = c("x", "y"), crs = crs), segments)
  v$seg_id <- segments$seg_id[nearest_seg]
  # line_vertex_table() numbers merged parts in union order; the profile
  # must use the same line ids as the segments (#53).
  v$line_id <- segments$line_id[nearest_seg]
  v$ground <- terra::extract(dtm, as.matrix(v[, c("x", "y")]))[, 1]
  v <- v[!is.na(v$ground), ]

  v$z_lo <- v$ground + min_ground_clear_m
  v$z_hi <- NA_real_
  sup <- NULL
  if (!is.null(supports) && nrow(supports) > 0) {
    sxy <- sf::st_coordinates(sf::st_transform(sf::st_geometry(supports), crs))[, 1:2, drop = FALSE]
    sp <- line_project(sxy, v, m)
    sup <- data.frame(line_id = sp$line_id, s_m = sp$s_m,
                      z = terra::extract(dtm, sxy)[, 1] + attach_m, xy = sxy)
    sup <- sup[sp$dist_m <= search_m & !is.na(sup$z), ]
  }
  for (lid in unique(v$line_id)) {
    i <- which(v$line_id == lid)
    v$z_hi[i] <- if (is.null(sup)) {
      taut_upper(v$s_m[i], v$ground[i] + attach_m, max_span_m, step = 5)
    } else {
      support_chord(v$s_m[i], sup[sup$line_id == lid, ])
    }
  }
  v$z_hi <- pmax(v$z_hi, v$z_lo)
  v$src <- "bounded"

  rule <- if (!is.null(pred$label)) pred$label %in% "wire" else FALSE
  confident <- if (!is.null(pred$p_wire)) pred$pred %in% "wire" & pred$p_wire >= min_p_wire else FALSE
  w <- pred[which(rule | confident)]
  if (nrow(w) > 0 && !is.null(sup) && nrow(sup) > 0) {
    d_sup <- FNN::get.knnx(as.matrix(sup[, c("xy.X", "xy.Y")]), as.matrix(w[, c("X", "Y")]), k = 1)$nn.dist[, 1] * m
    w <- w[d_sup > structure_mask_m]
  }
  bin_log <- data.frame(line_id = unique(v$line_id), n_bins = 0L, n_too_few = 0L,
                        n_below_floor = 0L, n_implausible = 0L, n_measured = 0L,
                        n_above_upper_bound = 0L)
  if (nrow(w) > 0) {
    xy <- as.matrix(w[, c("X", "Y")])
    pr <- line_project(xy, v, m)
    obs <- data.frame(line_id = pr$line_id, s_m = pr$s_m,
                      z = terra::extract(dtm, xy)[, 1] + w$height_m)[pr$dist_m <= search_m, ]
    obs <- obs[!is.na(obs$z), ]
    if (nrow(obs) > 0) {
      obs$bin <- floor(obs$s_m / bin_m)
      bins <- stats::aggregate(z ~ line_id + bin, obs, function(z) {
        c(q = stats::quantile(z, q, names = FALSE), n = length(z))
      })
      bins <- data.frame(line_id = bins$line_id, s_m = (bins$bin + 0.5) * bin_m,
                         z = bins$z[, "q"], n = bins$z[, "n"])
      for (lid in unique(bins$line_id)) {
        i <- which(v$line_id == lid)
        k <- which(bin_log$line_id == lid)
        b <- bins[bins$line_id == lid, ]
        bin_log$n_bins[k] <- nrow(b)
        b <- b[b$n >= min_bin_points, ]
        bin_log$n_too_few[k] <- bin_log$n_bins[k] - nrow(b)
        floor_z <- stats::approx(v$s_m[i], v$z_lo[i], xout = b$s_m, rule = 2)$y
        above <- b[b$z >= floor_z, ]
        bin_log$n_below_floor[k] <- nrow(b) - nrow(above)
        b <- plausible_bins(above, max_slope)
        bin_log$n_implausible[k] <- nrow(above) - nrow(b)
        bin_log$n_measured[k] <- nrow(b)
        if (nrow(b) == 0) next
        # Measured bins above the support chord mean the chord is not an
        # upper bound there: a missed or spurious support, or attachments
        # above `attach_m`. They are kept (measured beats bounded) and
        # counted so the support set can be checked (#51).
        chord <- stats::approx(v$s_m[i], v$z_hi[i], xout = b$s_m, rule = 2)$y
        bin_log$n_above_upper_bound[k] <- sum(is.finite(chord) & b$z > chord + 0.5)
        zz <- interp_with_gaps(b, v$s_m[i], bin_m, max_gap_m)
        ok <- !is.na(zz)
        v$z_lo[i[ok]] <- zz[ok]
        v$z_hi[i[ok]] <- zz[ok]
        v$src[i[ok]] <- "measured"
      }
    }
  }
  attr(v, "bins") <- bin_log
  v
}

# Chord between the supports either side of each station; Inf where a side
# has no support inside the data.
support_chord <- function(s, sup) {
  if (nrow(sup) == 0) return(rep(Inf, length(s)))
  sup <- sup[order(sup$s_m), ]
  k <- findInterval(s, sup$s_m)
  out <- rep(Inf, length(s))
  ok <- k >= 1 & k < nrow(sup)
  a <- k[ok]
  t <- (s[ok] - sup$s_m[a]) / (sup$s_m[a + 1] - sup$s_m[a])
  out[ok] <- sup$z[a] + t * (sup$z[a + 1] - sup$z[a])
  at <- match(s, sup$s_m)
  out[!is.na(at)] <- sup$z[at[!is.na(at)]]
  out
}

# Keep measured bins with at least one neighbour within `max_slope` (drops
# isolated bins and spikes or ramps a conductor cannot make).
plausible_bins <- function(b, max_slope) {
  b <- b[order(b$s_m), ]
  if (nrow(b) < 2) return(b[0, ])
  sl <- abs(diff(b$z) / diff(b$s_m))
  left <- c(Inf, sl)
  right <- c(sl, Inf)
  b[pmin(left, right) <= max_slope, ]
}

# Linear interpolation of binned elevations onto stations, NA outside the
# observed range and across gaps longer than `max_gap`.
interp_with_gaps <- function(b, s, bin_m, max_gap) {
  b <- b[order(b$s_m), ]
  if (nrow(b) == 1) return(ifelse(abs(s - b$s_m) <= bin_m / 2, b$z, NA_real_))
  zz <- stats::approx(b$s_m, b$z, xout = s, rule = 1)$y
  k <- findInterval(s, b$s_m, rightmost.closed = TRUE)
  inside <- k >= 1 & k < nrow(b)
  gap <- rep(Inf, length(s))
  gap[inside] <- b$s_m[k[inside] + 1] - b$s_m[k[inside]]
  zz[gap > max_gap] <- NA_real_
  zz
}

# Highest chord value at each station over all chords spanning it whose
# endpoints are at most `max_span` apart. Computed on a `step`-metre
# resample of the profile, then interpolated back.
taut_upper <- function(s, z, max_span, step = 5) {
  ss <- seq(min(s), max(s), by = step)
  if (length(ss) < 2) return(z)
  zz <- stats::approx(s, z, xout = ss)$y
  up <- vapply(seq_along(ss), function(k) {
    a <- which(ss >= ss[k] - max_span & ss <= ss[k])
    b <- which(ss >= ss[k] & ss <= ss[k] + max_span)
    sa <- matrix(ss[a], length(a), length(b))
    sb <- matrix(ss[b], length(a), length(b), byrow = TRUE)
    za <- matrix(zz[a], length(a), length(b))
    zb <- matrix(zz[b], length(a), length(b), byrow = TRUE)
    span <- sb - sa
    val <- ifelse(span > 0, za + (zb - za) * (ss[k] - sa) / span, za)
    # Only chords that straddle the station bound it; a zero-length chord at
    # a line end assumes a support there, which is no bound at all (#51).
    inside <- span > 0 & span <= max_span & sa < ss[k] & sb > ss[k]
    if (any(inside)) max(val[inside]) else Inf
  }, numeric(1))
  stats::approx(ss, up, xout = s, rule = 2)$y
}

#' Locate trees and score grow-in / fall-in risk per segment
#'
#' Every metric is computed against both conductor bounds from
#' [conductor_profile()] (identical where the conductor is measured).
#'
#' @param rasters Output of [corridor_rasters()].
#' @param profile Output of [conductor_profile()].
#' @param segments Output of [segment_lines()].
#' @param tree_ws_m Local-maximum window for treetop detection (metres).
#' @param min_tree_m Minimum treetop height.
#' @param phase_offset_m Horizontal offset of the outer conductors from the
#'   mapped centreline (OSM maps the right-of-way centreline, not each phase).
#' @param growth_m Growth allowance added to tree heights (e.g. expected growth
#'   over a trim cycle).
#' @param under_line_m Horizontal distance from the centreline within which
#'   canopy counts as "under the conductors". Canopy there is scored as
#'   grow-in; treetops there are excluded from the fall-in count so the two
#'   are not double-counted. It must be at least `phase_offset_m +
#'   clearance_target_m`, so that canopy beside the outer phase inside the
#'   clearance target is scored (the function aborts otherwise).
#' @param wire_zone_m Half-width of the wire zone for canopy cover.
#' @param clearance_target_m Target radial clearance between canopy and the
#'   nearest conductor: the 3D distance from the canopy column to the outer
#'   phase, horizontal beyond `phase_offset_m` and vertical up to the
#'   conductor. The default 4.6 m (15 ft) is a common utility
#'   clearance-at-time-of-work target; it is not the NERC FAC-003 minimum
#'   vegetation clearance distance, which is smaller.
#' @param cover_min_m Canopy height counted as cover.
#' @param structures Optional `sf` points of support structures (e.g. OSM
#'   pole/tower nodes and the line's own vertices, which OSM mappers place at
#'   structures). Canopy within `structure_mask_m` is zeroed so poles,
#'   H-frames and crossarms are not scored as trees under the line.
#' @param structure_mask_m Mask radius around each structure (metres); should
#'   cover the structure's across-line width. Masked cells are excluded from
#'   cover and clearance and trees there are not scored, but they count as
#'   observed for `frac_observed` (a known structure, not a data gap).
#' @param min_support A CHM cell counts as canopy only if at least this many
#'   cells of its 3 x 3 window are >= `cover_min_m`. Removes 1-2 cell features
#'   (unmapped single poles, stray conductor returns classified as vegetation)
#'   that would otherwise appear as trees directly under the line. It also
#'   trims crown edges slightly.
#' @param min_encroach_m2 Canopy area inside the clearance envelope needed to
#'   call a segment grow-in (guards against single-cell artefacts).
#' @param coverage_m Half-width of the band over which LiDAR coverage is
#'   measured (`frac_observed`). Set it to the corridor half-width so that
#'   voids beside the line, where strike trees stand, count too.
#' @param min_observed A segment whose observed share of either the
#'   `coverage_m` band or the `under_line_m` zone is below this, and that
#'   would otherwise be `"none"`, is tiered `"no data"`: absence of risk
#'   cannot be claimed where the LiDAR did not see the ground.
#' @return A list: `segments` (`sf`, one row per segment) and `trees` (`sf`
#'   treetops: `tree_id` (`<epsg>:<x>:<y>`, the treetop's position in
#'   half-metres of the site's canonical UTM CRS, see [tree_ids()], so the
#'   same tree has the same id whatever CRS the delivery used), `seg_id`, `height_m`, `dh_m` horizontal
#'   distance to the nearest conductor, `reach_lo_m` / `reach_hi_m` the height a tree there
#'   needs to reach the conductor under each bound (the minimum 3D distance
#'   to any conductor vertex within reach, less the phase offset),
#'   `dz_lo_m` / `dz_hi_m` the conductor's height above the tree's base at
#'   that vertex, `reach_min_m` the smallest reach any conductor elevation
#'   inside the bracket allows, `strike_lo` / `strike_hi` whether the tree
#'   reaches the conductor at each bound, `strike_possible` whether it does
#'   at some plausible elevation, `strike_certain` whether it does at every
#'   plausible elevation, and `strike = strike_possible`). Columns ending
#'   `_lo` / `_hi` use the lower / upper conductor bound; segments also
#'   carry `n_strike_possible` and `n_strike_certain`, which the tiers use. `frac_observed` and `frac_observed_under` are the shares of the
#'   grid cells within `coverage_m` and `under_line_m` of the segment (not
#'   past the line's ends) with an observed terrain and canopy value; cells
#'   off the edge of the data count as unobserved, structure-masked cells as
#'   observed (known structures, not gaps).
#'   `priority` is the optimistic tier: grow-in under the upper conductor
#'   bound, fall-in only from trees that strike at every plausible conductor
#'   elevation; `priority_lo` is the pessimistic tier: grow-in under the
#'   lower bound, fall-in from trees that strike at some plausible elevation.
#'   The pessimistic tier saturates wherever canopy stands under a bounded
#'   span (the lower bound is only ~5 m above ground). Tiers are
#'   `"grow-in"`, `"fall-in"`, `"no data"` (no risk found, but coverage below
#'   `min_observed`) and `"none"`. A grow-in or fall-in finding stands even
#'   at low coverage, though unseen cells could hide a more severe tier.
#'   `confidence` is `"measured"` (conductor observed over at least half the
#'   segment *and* the same tier under both bounds), `"robust"` (same tier
#'   under both bounds, conductor mostly bounded), `"bound-dependent"` (the
#'   tier changes with the bound, however much of the conductor was seen:
#'   the finding sits in the unmeasured part) or `"low coverage"` (`"no
#'   data"` under both bounds). `frac_measured` is reported alongside.
#'   `encroach_*_m2` is the canopy area within `under_line_m` whose radial
#'   clearance to the outer phase is under `clearance_target_m`;
#'   `min_clearance_*_m` is the smallest radial clearance there. Rows are ordered by what holds even under the
#'   optimistic (upper) conductor bound - encroachment, then strike trees -
#'   then by the same metrics under the lower bound.
#' @export
assess_risk <- function(rasters, profile, segments, tree_ws_m = 5, min_tree_m = 3,
                        phase_offset_m = 3, growth_m = 0, under_line_m = 8,
                        wire_zone_m = 10, clearance_target_m = 4.6, cover_min_m = 2,
                        min_support = 6, structures = NULL, structure_mask_m = 8,
                        min_encroach_m2 = 5, coverage_m = wire_zone_m, min_observed = 0.75) {
  crs <- sf::st_crs(segments)
  m <- crs_m_per_unit(crs)
  lateral_m <- phase_offset_m + clearance_target_m
  if (under_line_m < lateral_m) {
    rlang::abort(sprintf(paste(
      "`under_line_m` (%g m) is narrower than `phase_offset_m` + `clearance_target_m` (%g m):",
      "canopy beside the outer phase inside the clearance target would be neither grow-in nor a strike tree.",
      "Widen `under_line_m` (and the conductor envelope with it)."), under_line_m, lateral_m))
  }
  dtm <- rasters$dtm
  # NA canopy means "no vegetation point": bare ground, unless the cell is
  # flagged unobserved (void or uncertain exclusion).
  chm <- terra::ifel(is.na(rasters$chm), 0, rasters$chm)
  if (!is.null(rasters$unobserved)) chm <- terra::mask(chm, rasters$unobserved, maskvalues = TRUE)
  observed <- !is.na(chm) & !is.na(dtm)
  if (!is.null(structures) && nrow(structures) > 0) {
    mask <- sf::st_union(sf::st_buffer(sf::st_transform(sf::st_geometry(structures), crs),
                                       structure_mask_m / m))
    # A structure footprint is known, not a data gap, even where its returns
    # were left out of the canopy model as uncertain.
    observed <- terra::mask(observed, terra::vect(mask), inverse = TRUE, updatevalue = TRUE) &
      !is.na(dtm)
    # NA, not 0: masked cells are unobserved, not bare ground.
    chm <- terra::mask(chm, terra::vect(mask), inverse = TRUE, updatevalue = NA)
  }
  support <- terra::focal(chm >= cover_min_m, w = 3, fun = "sum", na.rm = TRUE)
  # na.rm gives masked cells next to observed ones a finite support count;
  # keep them NA so the filter can't turn them into bare ground.
  chm <- terra::ifel(is.na(chm), NA, terra::ifel(support >= min_support, chm, 0))

  s_end <- tapply(profile$s_m, profile$line_id, max)
  near <- function(xy) {
    p <- line_project(xy, profile, m)
    list(dh = p$dist_m, seg_id = profile$seg_id[p$vertex],
         z_lo = profile$z_lo[p$vertex], z_hi = profile$z_hi[p$vertex],
         inside = p$s_m >= 0 & p$s_m <= s_end[as.character(p$line_id)])
  }

  # --- canopy cells: cover and grow-in clearance ---------------------------
  cells <- terra::as.data.frame(c(chm, dtm, observed), xy = TRUE, na.rm = FALSE)
  names(cells) <- c("x", "y", "h", "ground", "observed")
  nc <- near(as.matrix(cells[, c("x", "y")]))
  cells$dh <- nc$dh
  cells$seg_id <- nc$seg_id
  # Coverage is counted over every grid cell alongside the line (not past
  # its ends), so cells off the data's edge count as unobserved too.
  band <- nc$inside & nc$dh <= max(coverage_m, under_line_m)
  seen <- cells[band, c("dh", "seg_id", "observed")]
  seen$observed <- seen$observed %in% TRUE
  seen <- split(seen, seen$seg_id)
  scored <- cells$observed %in% TRUE & !is.na(cells$h)
  cells <- cells[scored, ]
  nc <- lapply(nc, `[`, scored)
  # Radial clearance from the canopy column to the nearest outer phase: the
  # horizontal gap beyond the phase offset and the vertical gap up to the
  # conductor (zero where the column reaches conductor height). A crown
  # beside the outer phase at conductor height is a clearance breach, not a
  # strike tree that cannot reach (#50).
  top <- cells$ground + cells$h
  hg <- pmax(cells$dh - phase_offset_m, 0)
  cells$clear_lo <- sqrt(hg^2 + pmax(nc$z_lo - top, 0)^2)
  cells$clear_hi <- sqrt(hg^2 + pmax(nc$z_hi - top, 0)^2)

  # --- treetops: fall-in ----------------------------------------------------
  trees <- empty_trees(crs)
  tt <- lidR::locate_trees(terra::ifel(chm < min_tree_m, NA, chm),
                           lidR::lmf(ws = tree_ws_m / m, hmin = min_tree_m))
  if (nrow(tt) > 0) {
    xy <- sf::st_coordinates(tt)[, 1:2, drop = FALSE]
    ground <- terra::extract(dtm, xy)[, 1]
    nt <- near(xy)
    h <- tt$Z + growth_m
    beside <- nt$dh > under_line_m
    rl <- min_reach(xy, ground, profile$z_lo, profile, m, phase_offset_m, h)
    rh <- min_reach(xy, ground, profile$z_hi, profile, m, phase_offset_m, h)
    rp <- min_reach(xy, ground, profile$z_lo, profile, m, phase_offset_m, h, z_hi = profile$z_hi)
    trees <- sf::st_sf(
      tree_id = tree_ids(xy, crs),
      seg_id = nt$seg_id, height_m = tt$Z, dh_m = nt$dh,
      reach_lo_m = rl$reach, reach_hi_m = rh$reach, reach_min_m = rp$reach,
      dz_lo_m = rl$dz, dz_hi_m = rh$dz,
      geometry = sf::st_geometry(tt)
    )
    trees$strike_lo <- beside & h >= trees$reach_lo_m
    trees$strike_hi <- beside & h >= trees$reach_hi_m
    # Reach is convex in conductor elevation, so over the bracket its minimum
    # is `reach_min_m` and its maximum sits at one of the two bounds: a tree
    # strikes at *some* plausible height if h >= the minimum, and at *every*
    # plausible height if h >= both bounds. Testing only the bounds missed
    # trees whose base lies between them (#49).
    trees$strike_possible <- beside & h >= trees$reach_min_m
    trees$strike_certain <- beside & h >= pmax(trees$reach_lo_m, trees$reach_hi_m)
    trees$strike <- trees$strike_possible
    trees <- trees[!is.na(ground), ]
  }

  # --- per-segment summary --------------------------------------------------
  frac_measured <- tapply(profile$src == "measured", profile$seg_id, mean)
  cell_area <- prod(terra::res(chm)) * m^2
  coverage <- function(sn, width) {
    if (is.null(sn)) return(0)
    band <- sn$observed[sn$dh <= width]
    if (length(band)) mean(band) else 0
  }
  seg_stats <- lapply(segments$seg_id, function(s) {
    cs <- cells[cells$seg_id == s, ]
    wz <- cs[cs$dh <= wire_zone_m, ]
    ul <- cs[cs$dh <= under_line_m & cs$h >= cover_min_m, ]
    ts <- trees[trees$seg_id == s, ]
    fm <- frac_measured[as.character(s)]
    sn <- seen[[as.character(s)]]
    data.frame(
      seg_id             = s,
      frac_measured      = if (is.na(fm)) 0 else unname(fm),
      frac_observed      = coverage(sn, coverage_m),
      frac_observed_under = coverage(sn, under_line_m),
      wire_zone_cover    = if (nrow(wz)) mean(wz$h >= cover_min_m) else NA_real_,
      wire_zone_max_h_m  = if (nrow(wz)) max(wz$h) else NA_real_,
      min_clearance_lo_m = if (nrow(ul)) min(ul$clear_lo) else NA_real_,
      min_clearance_hi_m = if (nrow(ul)) min(ul$clear_hi) else NA_real_,
      encroach_lo_m2     = sum(ul$clear_lo < clearance_target_m) * cell_area,
      encroach_hi_m2     = sum(ul$clear_hi < clearance_target_m) * cell_area,
      n_strike_lo        = sum(ts$strike_lo),
      n_strike_hi        = sum(ts$strike_hi),
      n_strike_possible  = sum(ts$strike_possible),
      n_strike_certain   = sum(ts$strike_certain)
    )
  })
  out <- merge(segments, do.call(rbind, seg_stats), by = "seg_id")
  unseen <- out$frac_observed < min_observed | out$frac_observed_under < min_observed
  tier <- function(area, n) {
    t <- ifelse(area >= min_encroach_m2, "grow-in", ifelse(n > 0, "fall-in", "none"))
    ifelse(t == "none" & unseen, "no data", t)
  }
  lv <- c("grow-in", "fall-in", "no data", "none")
  # Pessimistic: the lowest plausible conductor for grow-in (clearance falls
  # with the conductor) and any plausible conductor for fall-in; optimistic:
  # the highest conductor for grow-in and every plausible conductor for
  # fall-in (#49).
  p_lo <- tier(out$encroach_lo_m2, out$n_strike_possible)
  p_hi <- tier(out$encroach_hi_m2, out$n_strike_certain)
  out$priority <- factor(p_hi, levels = lv)
  out$priority_lo <- factor(p_lo, levels = lv)
  # A segment whose tier differs between the bounds is bound-dependent even
  # if most of its conductor was measured: the disagreement comes from the
  # part that was not.
  out$confidence <- factor(
    ifelse(p_lo == "no data", "low coverage",
           ifelse(p_lo != p_hi, "bound-dependent",
                  ifelse(out$frac_measured >= 0.5, "measured", "robust"))),
    levels = c("measured", "robust", "bound-dependent", "low coverage")
  )
  out <- out[order(-out$encroach_hi_m2, -out$n_strike_certain, -out$encroach_lo_m2,
                   -out$n_strike_possible), ]
  list(segments = out, trees = trees)
}

empty_trees <- function(crs) {
  sf::st_sf(tree_id = character(), seg_id = integer(), height_m = numeric(), dh_m = numeric(),
            reach_lo_m = numeric(), reach_hi_m = numeric(), reach_min_m = numeric(),
            dz_lo_m = numeric(), dz_hi_m = numeric(),
            strike_lo = logical(), strike_hi = logical(),
            strike_possible = logical(), strike_certain = logical(), strike = logical(),
            geometry = sf::st_sfc(crs = crs))
}

# Minimum 3D distance from each tree base to the conductor, over every
# profile vertex the tree could reach (#19). Returns the reach and the
# conductor's height above the base at the vertex that gives it. An unknown
# upper bound (z = Inf) is never reachable.
# With `z_hi` given, the conductor at each vertex is taken anywhere in
# [z, z_hi]: reach is convex in conductor elevation and least where the
# conductor is level with the tree's base, so clamping the base into the
# bracket gives the smallest reach any plausible conductor allows (#49).
min_reach <- function(xy, ground, z, profile, m, phase_offset_m, h, z_hi = NULL) {
  step <- stats::median(abs(diff(profile$s_m)), na.rm = TRUE)
  if (!is.finite(step) || step <= 0) step <- 1
  k <- min(nrow(profile), ceiling(2 * (max(h, na.rm = TRUE) + phase_offset_m) / step) + 3L)
  nn <- FNN::get.knnx(as.matrix(profile[, c("x", "y")]), xy, k = k)
  dh <- pmax(nn$nn.dist * m - phase_offset_m, 0)
  zl <- matrix(z[nn$nn.index], nrow = nrow(xy))
  g <- matrix(ground, nrow = nrow(xy), ncol = ncol(zl))
  zc <- if (is.null(z_hi)) zl else pmin(pmax(g, zl), matrix(z_hi[nn$nn.index], nrow = nrow(xy)))
  dz <- zc - g
  r <- sqrt(dh^2 + dz^2)
  r[is.na(r)] <- Inf
  i <- cbind(seq_len(nrow(xy)), max.col(-r, "first"))
  list(reach = r[i], dz = dz[i])
}

#' Line vertices as candidate structure locations
#'
#' OSM power-line ways are normally drawn with a node at each support
#' structure, tagged or not.
#'
#' @param lines `sf` lines.
#' @return `sf` POINT layer of the lines' vertices.
#' @export
line_vertex_points <- function(lines) {
  xy <- sf::st_coordinates(sf::st_geometry(lines))
  sf::st_as_sf(as.data.frame(unique(xy[, 1:2, drop = FALSE])), coords = c("X", "Y"),
               crs = sf::st_crs(lines))
}

#' Support structures of a line, confirmed by tagged OSM nodes
#'
#' The upper conductor bound is the chord between a span's own attachments,
#' so only the line's real supports may define it. A tagged pole or tower of
#' another circuit, a distribution tap, or a bend vertex a mapper added
#' mid-span would otherwise pull the chord below where the conductor can be
#' (#51). A vertex of `lines` is a *confirmed* support when a tagged
#' structure node lies within `tol_m` of it (OSM ways pass through their
#' member nodes exactly). When the line has confirmed supports, only those
#' are returned as `use = TRUE`; when it has none, every vertex is kept with
#' `use = TRUE` and a warning, which is the old behaviour.
#'
#' @param lines `sf` lines, unclipped (clipping adds end points that are not
#'   structures).
#' @param structures `sf` points of tagged structures (poles, towers), any
#'   CRS; may be `NULL`.
#' @param crs Projected CRS for the output.
#' @param tol_m Distance within which a structure node confirms a vertex.
#' @return `sf` POINT layer of the line's vertices with `confirmed` (a
#'   tagged structure coincides) and `use` (defines the upper bound).
#' @export
line_supports <- function(lines, structures = NULL, crs = sf::st_crs(lines), tol_m = 2) {
  m <- crs_m_per_unit(crs)
  v <- line_vertex_points(sf::st_transform(sf::st_geometry(lines), crs))
  v$confirmed <- FALSE
  if (!is.null(structures) && nrow(structures) > 0) {
    sxy <- sf::st_coordinates(sf::st_transform(sf::st_geometry(structures), crs))[, 1:2, drop = FALSE]
    d <- FNN::get.knnx(sxy, sf::st_coordinates(v)[, 1:2, drop = FALSE], k = 1)$nn.dist[, 1] * m
    v$confirmed <- d <= tol_m
  }
  if (any(v$confirmed)) {
    v$use <- v$confirmed
  } else {
    rlang::warn(paste("No tagged structure coincides with a vertex of the line;",
                      "every vertex is treated as a support for the upper conductor bound."))
    v$use <- TRUE
  }
  v
}
