# Line-referenced coordinates: chainage (distance along the line) and signed
# perpendicular offset, computed against a 1 m densified copy of the line.

#' Densify lines into ordered vertices with chainage and unit tangent
#'
#' @param lines `sf`/`sfc` lines.
#' @param crs Projected CRS.
#' @param step_m Vertex spacing in metres.
#' @return data.frame with `line_id`, `x`, `y`, `s_m` (chainage, metres),
#'   `tx`, `ty` (unit tangent).
#' @noRd
line_vertex_table <- function(lines, crs, step_m = 1) {
  m <- crs_m_per_unit(crs)
  parts <- merge_lines(sf::st_transform(sf::st_geometry(lines), crs))
  do.call(rbind, lapply(seq_along(parts), function(i) {
    xy <- sf::st_coordinates(sf::st_segmentize(parts[i], step_m / m))[, 1:2, drop = FALSE]
    xy <- xy[c(TRUE, rowSums(abs(diff(xy))) > 0), , drop = FALSE]
    d <- sqrt(rowSums(diff(xy)^2))
    tan <- diff(xy) / d
    tan <- rbind(tan, tan[nrow(tan), ])
    data.frame(line_id = i, x = xy[, 1], y = xy[, 2], s_m = c(0, cumsum(d)) * m,
               tx = tan[, 1], ty = tan[, 2])
  }))
}

#' Project points onto lines
#'
#' @param xy Two-column matrix of coordinates in `crs`.
#' @param verts Output of `line_vertex_table()`.
#' @param m Metres per CRS unit.
#' @return data.frame with `line_id`, `s_m`, `offset_m` (signed, + = left of
#'   the line direction), `dist_m`, and `vertex` (row index into `verts`).
#' @noRd
line_project <- function(xy, verts, m) {
  nn <- FNN::get.knnx(as.matrix(verts[, c("x", "y")]), xy, k = 1)
  v <- nn$nn.index[, 1]
  dx <- xy[, 1] - verts$x[v]
  dy <- xy[, 2] - verts$y[v]
  data.frame(
    line_id  = verts$line_id[v],
    s_m      = verts$s_m[v] + (dx * verts$tx[v] + dy * verts$ty[v]) * m,
    offset_m = (verts$tx[v] * dy - verts$ty[v] * dx) * m,
    dist_m   = nn$nn.dist[, 1] * m,
    vertex   = v
  )
}

# Union and merge line pieces into the fewest LINESTRINGs.
merge_lines <- function(g) {
  u <- sf::st_cast(sf::st_union(g), "MULTILINESTRING")
  sf::st_cast(sf::st_line_merge(u), "LINESTRING")
}
