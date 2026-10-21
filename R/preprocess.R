# Corridor extraction and height normalisation.
#
# All user-facing distances in this package are in METRES. Point clouds are
# kept in their native CRS; `las_m_per_unit()` converts metre parameters to
# native units so a US-survey-feet state-plane tile does not silently shrink
# every buffer by 3.28x.

#' Metres per horizontal CRS unit of a LAS object or file header
#'
#' @param x A `LAS`, `LAScatalog`, `LASheader`, or anything with an `sf::st_crs()`.
#' @return Numeric scalar (1 for metre CRSs, 0.3048006 for US survey feet).
#' @export
las_m_per_unit <- function(x) crs_m_per_unit(sf::st_crs(x))

crs_m_per_unit <- function(crs) {
  crs <- sf::st_crs(crs)
  if (is.na(crs)) rlang::abort("Data has no CRS; cannot convert metre parameters.")
  if (isTRUE(crs$IsGeographic) || is.null(crs$ud_unit)) {
    rlang::abort("CRS is geographic or has no linear unit; reproject to a projected CRS first.")
  }
  as.numeric(units::set_units(crs$ud_unit, "m"))
}

#' Build a corridor polygon around power lines
#'
#' @param lines `sf` lines (any CRS).
#' @param crs Target CRS (normally the point cloud's).
#' @param half_width_m Corridor half-width in metres.
#' @return An `sfc` POLYGON in `crs`.
#' @export
line_corridor <- function(lines, crs, half_width_m = 40) {
  lines <- sf::st_transform(sf::st_geometry(lines), crs)
  m_per_unit <- crs_m_per_unit(crs)
  sf::st_union(sf::st_buffer(lines, half_width_m / m_per_unit, endCapStyle = "FLAT"))
}

#' Read the corridor point cloud and normalise heights
#'
#' Clips one or more LAS/LAZ files to a corridor around `lines`, drops noise
#' (ASPRS 7, 18), bridge decks (17) and withheld points, and converts elevations to height above
#' ground using a TIN of the delivered ground class (2). If the delivery has
#' no ground class, ground is classified with the cloth simulation filter.
#'
#' @param files Paths to `.las`/`.laz` files covering the corridor.
#' @param lines `sf` power lines.
#' @param half_width_m Corridor half-width in metres.
#' @return A height-normalised `LAS` with the original elevation kept in
#'   column `Zref` (lidR convention) and heights in `Z`.
#' @export
read_corridor <- function(files, lines, half_width_m = 40) {
  ctg <- lidR::readLAScatalog(files, progress = FALSE)
  lidR::opt_filter(ctg) <- "-drop_class 7 17 18 -drop_withheld"
  lidR::opt_select(ctg) <- "xyzirnc"
  corridor <- line_corridor(lines, sf::st_crs(ctg), half_width_m)

  las <- lidR::clip_roi(ctg, sf::st_sf(geometry = corridor))
  if (is.list(las)) las <- do.call(rbind, las)
  if (lidR::is.empty(las)) rlang::abort("No points inside the corridor; check tiles and CRS.")

  if (!any(las$Classification == 2L)) {
    message("No ground class delivered; running cloth simulation filter.")
    rlang::check_installed("RCSF", reason = "to classify ground with the cloth simulation filter")
    las <- lidR::classify_ground(las, lidR::csf(sloop_smooth = TRUE))
  }
  lidR::normalize_height(las, lidR::tin())
}
