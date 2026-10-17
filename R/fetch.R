# Data acquisition: USGS 3DEP LiDAR tiles (The National Map API) and
# OpenStreetMap power-line geometry (Overpass API).

tnm_api <- "https://tnmaccess.nationalmap.gov/api/v1/products"

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
#'   `title`, `url`, `size_mb`, `pub_date`.
#' @export
tnm_lidar_tiles <- function(aoi, project = NULL, max_items = 100) {
  bb <- sf::st_bbox(sf::st_transform(sf::st_as_sfc(sf::st_bbox(aoi)), 4326))
  offset <- 0
  items <- list()
  repeat {
    resp <- httr2::request(tnm_api) |>
      httr2::req_url_query(
        datasets = "Lidar Point Cloud (LPC)",
        bbox = paste(bb[c("xmin", "ymin", "xmax", "ymax")], collapse = ","),
        max = max_items, offset = offset, outputFormat = "JSON"
      ) |>
      httr2::req_retry(max_tries = 4) |>
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
  if (!is.null(project)) tiles <- tiles[grepl(project, tiles$title), ]
  tiles
}

#' Download LiDAR tiles, skipping files already present
#'
#' @param tiles Output of [tnm_lidar_tiles()].
#' @param dest_dir Directory for the `.laz` files.
#' @return Character vector of local file paths.
#' @export
download_tiles <- function(tiles, dest_dir = "data-raw/laz") {
  dir.create(dest_dir, showWarnings = FALSE, recursive = TRUE)
  paths <- file.path(dest_dir, basename(tiles$url))
  for (i in seq_along(paths)) {
    if (file.exists(paths[i]) && file.size(paths[i]) > 0) next
    message("Downloading ", basename(paths[i]), sprintf(" (%.0f MB)", tiles$size_mb[i]))
    httr2::request(tiles$url[i]) |>
      httr2::req_retry(max_tries = 3) |>
      httr2::req_perform(path = paths[i])
  }
  paths
}

#' Fetch overhead power lines from OpenStreetMap
#'
#' @param aoi An `sf`/`sfc` object or `bbox` defining the search window.
#' @param ids Optional OSM way ids; if given, only these ways are returned.
#' @param overpass_url Overpass endpoint.
#' @return An `sf` LINESTRING data frame (EPSG:4326) with `osm_id`, `name`,
#'   `voltage_kv`, `operator`.
#' @export
osm_power_lines <- function(aoi = NULL, ids = NULL,
                            overpass_url = "https://overpass-api.de/api/interpreter") {
  if (is.null(ids)) {
    if (is.null(aoi)) rlang::abort("Supply `aoi` or `ids`.")
    bb <- sf::st_bbox(sf::st_transform(sf::st_as_sfc(sf::st_bbox(aoi)), 4326))
    sel <- sprintf('way["power"="line"](%f,%f,%f,%f);',
                   bb["ymin"], bb["xmin"], bb["ymax"], bb["xmax"])
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

  sf::st_sf(
    osm_id     = vapply(els, function(e) as.character(e$id), ""),
    name       = vapply(els, tag, "", "name"),
    voltage_kv = volt,
    operator   = vapply(els, tag, "", "operator"),
    geometry   = sf::st_sfc(lapply(els, function(e) {
      sf::st_linestring(do.call(rbind, lapply(e$geometry, function(p) c(p$lon, p$lat))))
    }), crs = 4326)
  )
}

#' Fetch power-line support structures (poles, towers) from OpenStreetMap
#'
#' @inheritParams osm_power_lines
#' @return An `sf` POINT data frame (EPSG:4326) with `osm_id` and `type`.
#' @export
osm_power_structures <- function(aoi, overpass_url = "https://overpass-api.de/api/interpreter") {
  bb <- osm_bbox(aoi)
  els <- overpass(sprintf(
    '[out:json][timeout:90];(node["power"="tower"](%s);node["power"="pole"](%s););out;', bb, bb
  ), overpass_url)
  if (length(els) == 0) {
    return(sf::st_sf(osm_id = character(), type = character(),
                     geometry = sf::st_sfc(crs = 4326)))
  }
  sf::st_sf(
    osm_id   = vapply(els, function(e) as.character(e$id), ""),
    type     = vapply(els, function(e) e$tags$power %||% NA_character_, ""),
    geometry = sf::st_sfc(lapply(els, function(e) sf::st_point(c(e$lon, e$lat))), crs = 4326)
  )
}

#' Fetch building footprints from OpenStreetMap
#'
#' Only closed ways are returned; multipolygon relations (rare for houses)
#' are skipped.
#'
#' @inheritParams osm_power_lines
#' @return An `sf` POLYGON data frame (EPSG:4326) with `osm_id`.
#' @export
osm_buildings <- function(aoi, overpass_url = "https://overpass-api.de/api/interpreter") {
  els <- overpass(sprintf('[out:json][timeout:90];way["building"](%s);out geom;', osm_bbox(aoi)),
                  overpass_url)
  closed <- Filter(function(e) {
    g <- e$geometry
    length(g) >= 4 && g[[1]]$lon == g[[length(g)]]$lon && g[[1]]$lat == g[[length(g)]]$lat
  }, els)
  sf::st_sf(
    osm_id   = vapply(closed, function(e) as.character(e$id), character(1)),
    geometry = sf::st_sfc(lapply(closed, function(e) {
      sf::st_polygon(list(do.call(rbind, lapply(e$geometry, function(p) c(p$lon, p$lat)))))
    }), crs = 4326)
  )
}

# Overpass bbox string: south,west,north,east
osm_bbox <- function(aoi) {
  bb <- sf::st_bbox(sf::st_transform(sf::st_as_sfc(sf::st_bbox(aoi)), 4326))
  sprintf("%f,%f,%f,%f", bb["ymin"], bb["xmin"], bb["ymax"], bb["xmax"])
}

overpass <- function(query, overpass_url) {
  httr2::request(overpass_url) |>
    httr2::req_user_agent("vegrisk R package (github.com/mjorden/powerline-veg-risk)") |>
    httr2::req_body_form(data = query) |>
    httr2::req_retry(max_tries = 4) |>
    httr2::req_perform() |>
    httr2::resp_body_json() |>
    _$elements
}
