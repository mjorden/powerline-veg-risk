# Data vintage: when the LiDAR was flown and which files it came from.
#
# A twin needs a valid-from date on every row, and conductor physics needs
# the flight hour; both come from the point GPS times and the LAS headers,
# which the pipeline used to discard (#52).

#' Identity and header record of LAS/LAZ files
#'
#' One row per file: size and MD5 (so a replaced or truncated tile is
#' detectable), the header's project GUID, creation date, generating
#' software and system identifier, point count, LAS version, GPS time type
#' and CRS, read from the header only (no points are loaded).
#'
#' @param files Paths to `.las`/`.laz` files.
#' @return A data frame with `file`, `bytes`, `md5`, `guid`, `created`
#'   (a `Date` from the header's creation day and year, `NA` when absent),
#'   `software`, `system`, `n_points`, `las_version`, `gps_time_type`
#'   (`"adjusted_standard"` or `"gps_week"`) and `crs` (WKT or `NA`).
#' @export
las_file_info <- function(files) {
  rows <- lapply(files, function(f) {
    h <- lidR::readLASheader(f)@PHB
    doy <- h[["File Creation Day of Year"]]
    yr <- h[["File Creation Year"]]
    created <- if (!is.null(doy) && !is.null(yr) && isTRUE(doy > 0) && isTRUE(yr > 0)) {
      as.Date(paste0(yr, "-01-01")) + (doy - 1)
    } else as.Date(NA)
    crs <- tryCatch(sf::st_crs(lidR::readLASheader(f))$wkt, error = function(e) NA_character_)
    data.frame(
      file = basename(f), bytes = file.size(f), md5 = unname(tools::md5sum(f)),
      guid = h[["Project ID - GUID"]] %||% NA_character_, created = created,
      software = h[["Generating Software"]] %||% NA_character_,
      system = h[["System Identifier"]] %||% NA_character_,
      n_points = as.numeric(h[["Number of point records"]] %||% NA),
      las_version = paste(h[["Version Major"]], h[["Version Minor"]], sep = "."),
      gps_time_type = if (isTRUE(h[["Global Encoding"]][["GPS Time Type"]])) "adjusted_standard" else "gps_week",
      crs = if (is.null(crs)) NA_character_ else crs,
      stringsAsFactors = FALSE
    )
  })
  do.call(rbind, rows)
}

#' When a point cloud was flown, from its GPS times
#'
#' LAS stores point times as *adjusted standard GPS time* (seconds since
#' 1980-01-06 minus 1e9; the usual case for 3DEP) or as *GPS week time*
#' (seconds into an unknown week), which the header's global encoding
#' says. Adjusted standard time converts to UTC (leap seconds, 18 s as of
#' 2017, are ignored: minutes matter here, not seconds); week time cannot be
#' converted without the week, so it gives `NA` and the caller should fall
#' back to the acquisition's published dates.
#'
#' @param las A `LAS` read with the `t` (gpstime) attribute selected.
#' @return A list: `gps_time_type`, `n` (points with a time), `from`,
#'   `median`, `to` (UTC `POSIXct`, `NA` for week time or no times) and
#'   `time` (a UTC `POSIXct` per point, or `NULL`).
#' @export
lidar_vintage <- function(las) {
  type <- if (isTRUE(las@header@PHB[["Global Encoding"]][["GPS Time Type"]])) "adjusted_standard" else "gps_week"
  t <- las@data[["gpstime"]]
  na <- as.POSIXct(NA, tz = "UTC")
  empty <- list(gps_time_type = type, n = 0L, from = na, median = na, to = na, time = NULL)
  if (is.null(t) || all(is.na(t)) || all(t == 0)) return(empty)
  if (type == "gps_week") {
    rlang::warn("Point times are GPS week seconds; the flight date cannot be recovered from them.")
    return(empty)
  }
  time <- as.POSIXct(t + 1e9, origin = "1980-01-06", tz = "UTC")
  ok <- !is.na(time) & t > 0
  list(gps_time_type = type, n = sum(ok),
       from = min(time[ok]), median = stats::median(time[ok]), to = max(time[ok]), time = time)
}

#' Flight window per segment
#'
#' @param time A UTC `POSIXct` per point (from [lidar_vintage()]).
#' @param seg_id Segment id per point.
#' @return A data frame with `seg_id`, `flight_from`, `flight_median`,
#'   `flight_to` and `n_timed`.
#' @export
segment_flight_window <- function(time, seg_id) {
  ok <- !is.na(time) & !is.na(seg_id)
  if (!any(ok)) {
    return(data.frame(seg_id = integer(), flight_from = as.POSIXct(character(), tz = "UTC"),
                      flight_median = as.POSIXct(character(), tz = "UTC"),
                      flight_to = as.POSIXct(character(), tz = "UTC"), n_timed = integer()))
  }
  d <- data.table::data.table(seg_id = seg_id[ok], t = time[ok])
  out <- d[, .(flight_from = min(t), flight_median = stats::median(t), flight_to = max(t), n_timed = .N),
           by = seg_id]
  as.data.frame(out[order(seg_id)])
}
