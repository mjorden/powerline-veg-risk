# Data acquisition: USGS 3DEP LiDAR tiles (The National Map API) and
# OpenStreetMap power-line geometry (Overpass API).

tnm_api <- "https://tnmaccess.nationalmap.gov/api/v1/products"

# One request builder for every service the package talks to: a project
# user agent, a timeout (an unattended run must not hang on a stalled
# socket), and retries on the transient failures these services actually
# return (Overpass answers 504 on overload; httr2's default retries only 429
# and 503) and on connection errors.
vegrisk_request <- function(url, timeout_s = 60, max_tries = 4) {
  httr2::request(url) |>
    httr2::req_user_agent(vegrisk_ua) |>
    httr2::req_timeout(timeout_s) |>
    httr2::req_retry(max_tries = max_tries, retry_on_failure = TRUE,
                     is_transient = function(resp) httr2::resp_status(resp) %in% c(429L, 502L, 503L, 504L))
}

#' Find USGS 3DEP LiDAR point-cloud tiles intersecting an area of interest
#'
#' Queries The National Map (TNM) Access API for "Lidar Point Cloud (LPC)"
#' products whose footprint intersects `aoi`.
#'
#' @param aoi An `sf`/`sfc` object (any CRS) or a `bbox`.
#' @param project Optional regular expression matched against the tile title
#'   to keep a single acquisition (3DEP areas are often flown several times;
#'   mixing years in one model mixes vegetation states).
#' @param max_items Page size for the API.
#' @return An `sf` data frame of tiles (EPSG:4326 footprints) with columns
#'   `title`, `url`, `size_mb`, `size_bytes`, `pub_date`. Aborts, naming the
#'   acquisitions that were found, when `project` matches none of them: a
#'   typo must not come back as an empty table.
#' @export
tnm_lidar_tiles <- function(aoi, project = NULL, max_items = 100) {
  bb <- sf::st_bbox(sf::st_transform(sf::st_as_sfc(sf::st_bbox(aoi)), 4326))
  offset <- 0
  items <- list()
  repeat {
    resp <- vegrisk_request(tnm_api) |>
      httr2::req_url_query(
        datasets = "Lidar Point Cloud (LPC)",
        bbox = paste(bb[c("xmin", "ymin", "xmax", "ymax")], collapse = ","),
        max = max_items, offset = offset, outputFormat = "JSON"
      ) |>
      httr2::req_perform() |>
      httr2::resp_body_json()
    items <- c(items, resp$items)
    offset <- offset + max_items
    if (offset >= resp$total || length(resp$items) == 0) break
  }
  if (length(items) == 0) {
    rlang::abort("No 3DEP LiDAR tiles found for this AOI.")
  }

  tiles <- tibble::tibble(
    title    = vapply(items, `[[`, "", "title"),
    url      = vapply(items, `[[`, "", "downloadURL"),
    size_mb  = vapply(items, function(i) i$sizeInBytes / 1e6, 0),
    size_bytes = vapply(items, function(i) as.numeric(i$sizeInBytes %||% NA), 0),
    pub_date = as.Date(vapply(items, function(i) i$publicationDate %||% NA_character_, "")),
    geometry = sf::st_sfc(lapply(items, function(i) {
      b <- i$boundingBox
      sf::st_polygon(list(matrix(
        c(b$minX, b$minY, b$maxX, b$minY, b$maxX, b$maxY, b$minX, b$maxY, b$minX, b$minY),
        ncol = 2, byrow = TRUE
      )))
    }), crs = 4326)
  )
  tiles <- sf::st_as_sf(tiles)
  filter_tiles(tiles, project)
}

# Keep the tiles whose title matches `project`; abort, naming what was
# there, rather than hand back an empty table.
filter_tiles <- function(tiles, project) {
  if (is.null(project)) return(tiles)
  keep <- grepl(project, tiles$title)
  if (!any(keep)) {
    found <- unique(sub("^USGS Lidar Point Cloud ", "", sub(" [^ ]*$", "", tiles$title)))
    rlang::abort(c(sprintf("`project` \"%s\" matches none of the %d tiles found for this AOI.", project, nrow(tiles)),
                   i = paste("Acquisitions found:", paste(found, collapse = ", "))))
  }
  tiles[keep, ]
}

#' Download LiDAR tiles, skipping files already present
#'
#' Each tile is downloaded to a `.part` file and renamed only once it is
#' complete, so an interrupted download is retried on the next run instead
#' of being accepted as a tile. Where TNM reported the size, the file is
#' checked against it, before and after the download.
#'
#' @param tiles Output of [tnm_lidar_tiles()].
#' @param dest_dir Directory for the `.laz` files.
#' @param timeout_s Timeout per tile download.
#' @return Character vector of local file paths.
#' @export
download_tiles <- function(tiles, dest_dir = "data-raw/laz", timeout_s = 3600) {
  dir.create(dest_dir, showWarnings = FALSE, recursive = TRUE)
  paths <- file.path(dest_dir, basename(tiles$url))
  sizes <- tiles$size_bytes %||% rep(NA_real_, nrow(tiles))
  for (i in seq_along(paths)) {
    if (tile_complete(paths[i], sizes[i])) next
    message("Downloading ", basename(paths[i]), sprintf(" (%.0f MB)", tiles$size_mb[i]))
    part <- paste0(paths[i], ".part")
    vegrisk_request(tiles$url[i], timeout_s = timeout_s, max_tries = 3) |>
      httr2::req_perform(path = part)
    if (!tile_complete(part, sizes[i])) {
      rlang::abort(sprintf("Download of %s is incomplete (%.0f of %.0f bytes); the .part file is kept for inspection.",
                           basename(paths[i]), file.size(part), sizes[i]))
    }
    file.rename(part, paths[i])
  }
  paths
}

# A tile on disk counts as complete when it exists, is not empty, and (when
# TNM gave a size) is exactly that size.
tile_complete <- function(path, size_bytes = NA) {
  if (!file.exists(path) || file.size(path) == 0) return(FALSE)
  if (is.na(size_bytes)) return(TRUE)
  file.size(path) == size_bytes
}

#' Fetch overhead power lines from OpenStreetMap
#'
#' @param aoi An `sf`/`sfc` object or `bbox` defining the search window.
#' @param ids Optional OSM way ids; if given, only these ways are returned.
#' @param power OSM `power=*` values to fetch within `aoi`. The default takes
#'   transmission (`line`) and distribution (`minor_line`) ways: both carry
#'   suspended conductors, and a distribution wire crossing the corridor
#'   would otherwise be taught to the classifier as vegetation. Underground
#'   `cable` is deliberately left out. Ignored when `ids` is given.
#' @param overpass_url Overpass endpoint.
#' @return An `sf` LINESTRING data frame (EPSG:4326) with `osm_id`, `name`,
#'   `power`, `voltage_kv`, `operator`, `ref`, `circuits`, `cables`,
#'   `wires` and `tags` (every tag of the way as a JSON string, so nothing
#'   needed later for conflation is lost at fetch). Attributes `osm_timestamp` (the
#'   OSM data snapshot the answer came from) and `osm_query` record the
#'   provenance; [osm_power_structures()] and [osm_buildings()] carry the
#'   same two.
#' @export
osm_power_lines <- function(aoi = NULL, ids = NULL, power = c("line", "minor_line"),
                            overpass_url = "https://overpass-api.de/api/interpreter") {
  if (is.null(ids)) {
    if (is.null(aoi)) rlang::abort("Supply `aoi` or `ids`.")
    sel <- power_line_selector(aoi, power)
  } else {
    sel <- sprintf("way(id:%s);", paste(ids, collapse = ","))
  }
  els <- overpass(paste0("[out:json][timeout:90];", sel, "out geom tags;"), overpass_url)
  if (length(els) == 0) rlang::abort("Overpass returned no power lines.")

  tag <- function(e, k) e$tags[[k]] %||% NA_character_
  # OSM voltage is in volts and may list several circuits ("115000;115000").
  volt <- vapply(els, function(e) {
    v <- suppressWarnings(as.numeric(strsplit(tag(e, "voltage"), ";")[[1]]))
    if (all(is.na(v))) NA_real_ else max(v, na.rm = TRUE) / 1000
  }, 0)

  out <- sf::st_sf(
    osm_id     = vapply(els, function(e) as.character(e$id), ""),
    name       = vapply(els, tag, "", "name"),
    power      = vapply(els, tag, "", "power"),
    voltage_kv = volt,
    operator   = vapply(els, tag, "", "operator"),
    ref        = vapply(els, tag, "", "ref"),
    circuits   = vapply(els, tag, "", "circuits"),
    cables     = vapply(els, tag, "", "cables"),
    wires      = vapply(els, tag, "", "wires"),
    tags       = vapply(els, function(e) as.character(jsonlite::toJSON(e$tags %||% list(), auto_unbox = TRUE)), ""),
    geometry   = sf::st_sfc(lapply(els, function(e) {
      sf::st_linestring(do.call(rbind, lapply(e$geometry, function(p) c(p$lon, p$lat))))
    }), crs = 4326)
  )
  osm_provenance(out, els)
}

#' Fetch power-line support structures (poles, towers) from OpenStreetMap
#'
#' @inheritParams osm_power_lines
#' @return An `sf` POINT data frame (EPSG:4326) with `osm_id`, `type`,
#'   `ref` (the utility's structure number, when mapped) and `tags` (every
#'   tag as a JSON string);
#'   zero rows when the area has none (sf gives an empty geometry column
#'   the class `sfc_GEOMETRY`, so test `nrow()`, not the class).
#' @export
osm_power_structures <- function(aoi, overpass_url = "https://overpass-api.de/api/interpreter") {
  bb <- osm_bbox(aoi)
  els <- overpass(sprintf(
    '[out:json][timeout:90];(node["power"="tower"](%s);node["power"="pole"](%s););out;', bb, bb
  ), overpass_url)
  out <- if (length(els) == 0) {
    sf::st_sf(osm_id = character(), type = character(), ref = character(), tags = character(),
              geometry = empty_sfc("POINT"))
  } else {
    sf::st_sf(
      osm_id   = vapply(els, function(e) as.character(e$id), ""),
      type     = vapply(els, function(e) e$tags$power %||% NA_character_, ""),
      ref      = vapply(els, function(e) e$tags$ref %||% NA_character_, ""),
      tags     = vapply(els, function(e) as.character(jsonlite::toJSON(e$tags %||% list(), auto_unbox = TRUE)), ""),
      geometry = sf::st_sfc(lapply(els, function(e) sf::st_point(c(e$lon, e$lat))), crs = 4326)
    )
  }
  osm_provenance(out, els)
}

#' Fetch building footprints from OpenStreetMap
#'
#' Only closed ways are returned; multipolygon relations (rare for houses)
#' are skipped.
#'
#' @inheritParams osm_power_lines
#' @return An `sf` POLYGON data frame (EPSG:4326) with `osm_id`; zero rows
#'   when the area has none (an empty geometry column is `sfc_GEOMETRY`;
#'   test `nrow()`, not the class).
#' @export
osm_buildings <- function(aoi, overpass_url = "https://overpass-api.de/api/interpreter") {
  els <- overpass(sprintf('[out:json][timeout:90];way["building"](%s);out geom;', osm_bbox(aoi)),
                  overpass_url)
  closed <- Filter(function(e) {
    g <- e$geometry
    length(g) >= 4 && g[[1]]$lon == g[[length(g)]]$lon && g[[1]]$lat == g[[length(g)]]$lat
  }, els)
  out <- if (length(closed) == 0) {
    sf::st_sf(osm_id = character(), geometry = empty_sfc("POLYGON"))
  } else {
    sf::st_sf(
      osm_id   = vapply(closed, function(e) as.character(e$id), character(1)),
      geometry = sf::st_sfc(lapply(closed, function(e) {
        sf::st_polygon(list(do.call(rbind, lapply(e$geometry, function(p) c(p$lon, p$lat)))))
      }), crs = 4326)
    )
  }
  osm_provenance(out, els)
}

# A zero-length EPSG:4326 geometry column for an empty answer. sf gives
# every zero-feature column the class sfc_GEOMETRY (st_cast and subsetting
# can't type it), so the documented type holds for one or more features and
# an empty layer must be recognised by nrow() == 0, not by its class.
empty_sfc <- function(type = c("POINT", "POLYGON", "LINESTRING")) {
  match.arg(type)
  sf::st_sfc(crs = 4326)
}

osm_provenance <- function(out, els) {
  attr(out, "osm_timestamp") <- attr(els, "osm_timestamp")
  attr(out, "osm_query") <- attr(els, "osm_query")
  out
}

# Overpass way selector for one or more power=* values inside the AOI.
power_line_selector <- function(aoi, power) {
  if (length(power) == 0 || any(!nzchar(power))) rlang::abort("`power` needs at least one tag value.")
  if (length(power) == 1) {
    sprintf('way["power"="%s"](%s);', power, osm_bbox(aoi))
  } else {
    sprintf('way["power"~"^(%s)$"](%s);', paste(power, collapse = "|"), osm_bbox(aoi))
  }
}

# Overpass bbox string: south,west,north,east
osm_bbox <- function(aoi) {
  bb <- sf::st_bbox(sf::st_transform(sf::st_as_sfc(sf::st_bbox(aoi)), 4326))
  sprintf("%f,%f,%f,%f", bb["ymin"], bb["xmin"], bb["ymax"], bb["xmax"])
}

overpass <- function(query, overpass_url) {
  body <- vegrisk_request(overpass_url, timeout_s = 120) |>
    httr2::req_body_form(data = query) |>
    httr2::req_perform() |>
    httr2::resp_body_json()
  overpass_elements(body, query)
}

# Overpass reports a server-side timeout or memory abort as HTTP 200 with a
# `remark` and an empty or truncated `elements`. That must not pass as an
# empty area, so it aborts here. The OSM snapshot time travels with the
# elements as an attribute.
overpass_elements <- function(body, query = NULL) {
  if (!is.null(body$remark)) {
    rlang::abort(c("Overpass did not complete the query.", x = body$remark,
                   i = "Try again later, or a smaller area; the result was not cached."))
  }
  els <- body$elements %||% list()
  attr(els, "osm_timestamp") <- body$osm3s$timestamp_osm_base %||% NA_character_
  attr(els, "osm_query") <- query
  els
}
