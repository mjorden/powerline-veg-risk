# Landsat surface reflectance (Collection 2 Level-2, via the Microsoft
# Planetary Computer STAC API) for canopy greenness and moisture along the
# corridor. LiDAR says where canopy has grown in; Landsat says how green and
# how wet that canopy is in the dry season.

pc_stac <- "https://planetarycomputer.microsoft.com/api/stac/v1"
pc_sas  <- "https://planetarycomputer.microsoft.com/api/sas/v1/token"
pc_env  <- new.env(parent = emptyenv())

# Asset keys are the same for Landsat 4-9 on the Planetary Computer, so one
# code path covers TM, ETM+ and OLI.
landsat_bands <- c(red = "red", nir = "nir08", swir1 = "swir16", qa = "qa_pixel")

#' Find Landsat Collection 2 Level-2 scenes over an area of interest
#'
#' Searches the Microsoft Planetary Computer STAC API (no account or key
#' needed) for surface-reflectance scenes intersecting `aoi` in the given
#' years and months.
#'
#' Pick `months` for the local dry season, when canopy moisture matters for
#' fire (e.g. July-September on the Colorado Front Range, August-October in
#' Tennessee). Landsat 7 is excluded by default: its scan-line corrector
#' failed in 2003 and every later scene has missing stripes.
#'
#' @param aoi An `sf`/`sfc` object (any CRS) or a `bbox`.
#' @param years Integer vector of calendar years.
#' @param months Integer vector of months (1-12) to keep.
#' @param max_cloud Maximum scene cloud cover (percent). Clouds over the
#'   corridor itself are masked per pixel later, so this only drops scenes
#'   that are mostly cloud.
#' @param platforms Landsat platforms to keep.
#' @param stac_url STAC API root.
#' @return A tibble with one row per scene: `id`, `datetime`, `platform`,
#'   `cloud_cover`, and signed-on-read asset URLs `red`, `nir`, `swir1`, `qa`.
#' @export
landsat_scenes <- function(aoi, years, months = 7:9, max_cloud = 50,
                           platforms = c("landsat-8", "landsat-9"),
                           stac_url = pc_stac) {
  bb <- sf::st_bbox(sf::st_transform(sf::st_as_sfc(sf::st_bbox(aoi)), 4326))
  feats <- list()
  for (yr in years) {
    rng <- sprintf("%d-%02d-01T00:00:00Z/%d-%02d-%02dT23:59:59Z", yr, min(months), yr,
                   max(months), month_days(yr, max(months)))
    body <- list(
      collections = list("landsat-c2-l2"),
      bbox = unname(as.numeric(bb[c("xmin", "ymin", "xmax", "ymax")])),
      datetime = rng,
      query = list(`eo:cloud_cover` = list(lt = max_cloud),
                   platform = list(`in` = as.list(platforms))),
      limit = 100
    )
    feats <- c(feats, stac_search(paste0(stac_url, "/search"), body))
  }
  scenes <- parse_landsat_items(feats)
  scenes <- scenes[as.integer(format(scenes$datetime, "%m")) %in% months, ]
  if (nrow(scenes) == 0) rlang::abort("No Landsat scenes found for this AOI, period and cloud limit.")
  scenes[order(scenes$datetime), ]
}

# POST a STAC search and follow "next" links (the Planetary Computer pages
# with a POST body carrying a continuation token).
stac_search <- function(url, body) {
  out <- list()
  repeat {
    resp <- vegrisk_request(url) |>
      httr2::req_body_json(body) |>
      httr2::req_perform() |>
      httr2::resp_body_json()
    out <- c(out, resp$features)
    nxt <- Filter(function(l) identical(l$rel, "next"), resp$links %||% list())
    if (length(nxt) == 0 || length(resp$features) == 0) break
    url <- nxt[[1]]$href
    body <- utils::modifyList(body, nxt[[1]]$body %||% list())
  }
  out
}

# STAC features (parsed JSON) -> scene table. Scenes missing any band are
# dropped.
parse_landsat_items <- function(feats) {
  keep <- Filter(function(f) all(landsat_bands %in% names(f$assets)), feats)
  href <- function(key) vapply(keep, function(f) f$assets[[key]]$href, "")
  tibble::tibble(
    id          = vapply(keep, function(f) f$id, ""),
    datetime    = as.POSIXct(vapply(keep, function(f) f$properties$datetime, ""),
                             format = "%Y-%m-%dT%H:%M:%OS", tz = "UTC"),
    platform    = vapply(keep, function(f) f$properties$platform %||% NA_character_, ""),
    cloud_cover = vapply(keep, function(f) as.numeric(f$properties$`eo:cloud_cover` %||% NA), 0),
    red         = href(landsat_bands[["red"]]),
    nir         = href(landsat_bands[["nir"]]),
    swir1       = href(landsat_bands[["swir1"]]),
    qa          = href(landsat_bands[["qa"]])
  )
}

month_days <- function(year, month) {
  d <- as.Date(sprintf("%d-%02d-01", year + (month == 12), month %% 12 + 1)) - 1
  as.integer(format(d, "%d"))
}

# Planetary Computer blobs need a short-lived SAS token; one token covers the
# whole collection, so it is cached until shortly before it expires.
pc_sign <- function(href, collection = "landsat-c2-l2") {
  tok <- pc_env[[collection]]
  if (is.null(tok) || Sys.time() > tok$expiry - 300) {
    resp <- vegrisk_request(paste0(pc_sas, "/", collection)) |>
      httr2::req_perform() |>
      httr2::resp_body_json()
    expiry <- as.POSIXct(resp$`msft:expiry`, format = "%Y-%m-%dT%H:%M:%OS", tz = "UTC")
    if (is.na(expiry)) expiry <- Sys.time() + 1800
    tok <- list(token = resp$token, expiry = expiry)
    pc_env[[collection]] <- tok
  }
  paste0(href, if (grepl("?", href, fixed = TRUE)) "&" else "?", tok$token)
}

#' Clear-sky land pixels from a Landsat Collection 2 QA_PIXEL band
#'
#' A pixel is kept when none of these bits are set: fill (0), dilated cloud
#' (1), cirrus (2), cloud (3), cloud shadow (4), snow (5), water (7). Water
#' is dropped too: its negative NDVI would read as very dry canopy.
#'
#' @param qa Integer vector of QA_PIXEL values.
#' @return Logical vector, `TRUE` for usable pixels (`NA` stays `NA`).
#' @keywords internal
qa_clear <- function(qa) {
  bitwAnd(as.integer(qa), 0xBFL) == 0L
}

# Collection 2 Level-2 surface reflectance scaling; DNs outside the USGS valid
# range (7273-43636, i.e. reflectance 0-1) are saturated or fill.
sr_scale <- function(dn) {
  dn[dn < 7273 | dn > 43636] <- NA
  dn * 2.75e-05 - 0.2
}

norm_diff <- function(a, b) (a - b) / (a + b)

#' Median dry-season NDVI and NDMI composite from Landsat scenes
#'
#' Reads only the window around `aoi` from each scene's cloud-optimised
#' GeoTIFFs, masks cloud, shadow, snow and water with [qa_clear()], converts
#' to surface reflectance, and takes the per-pixel median over all clear
#' observations.
#'
#' - **NDVI** = (NIR - red) / (NIR + red): greenness / live leaf area.
#' - **NDMI** = (NIR - SWIR1) / (NIR + SWIR1): canopy water content, the
#'   closer of the two to fuel moisture.
#'
#' Both are relative indicators. They are not fuel-moisture measurements and
#' have no fire-danger thresholds; compare pixels within one composite, not
#' across sites or seasons.
#'
#' @param scenes Output of [landsat_scenes()].
#' @param aoi `sf`/`sfc` area to read (any CRS), normally the corridor.
#' @param buffer_m Extra margin read around `aoi`, in metres.
#' @return A `SpatRaster` on the Landsat 30 m grid (UTM) with layers `ndvi`,
#'   `ndmi` and `n_obs` (clear observations per pixel). Attributes `scenes`
#'   (ids used) and `dates` record what went into it; `scene_log` is a data
#'   frame of every scene offered (`id`, `datetime`, `used`, `skip_reason`:
#'   `NA` when used, `"no coverage"` when the scene misses the AOI, else
#'   the read error), so a composite thinned by transient failures can be
#'   told from one that used every scene.
#' @export
landsat_composite <- function(scenes, aoi, buffer_m = 100) {
  if (nrow(scenes) == 0) rlang::abort("No scenes to composite.")
  stacks <- list()
  used <- character()
  skip_reason <- rep(NA_character_, nrow(scenes))
  template <- NULL
  for (i in seq_len(nrow(scenes))) {
    sc <- scenes[i, ]
    r <- tryCatch(read_landsat_window(sc, aoi, buffer_m, template), error = function(e) {
      msg <- conditionMessage(e)
      skip_reason[i] <<- if (grepl("does not cover the AOI", msg, fixed = TRUE)) "no coverage" else msg
      warning(sprintf("Skipping Landsat scene %s: %s", sc$id, msg), call. = FALSE)
      NULL
    })
    if (is.null(r)) next
    if (is.null(template)) template <- r[[1]]
    stacks[[length(stacks) + 1]] <- r
    used <- c(used, sc$id)
  }
  if (length(stacks) == 0) rlang::abort("None of the Landsat scenes could be read.")
  ndvi <- terra::rast(lapply(stacks, `[[`, "ndvi"))
  ndmi <- terra::rast(lapply(stacks, `[[`, "ndmi"))
  out <- c(terra::app(ndvi, stats::median, na.rm = TRUE),
           terra::app(ndmi, stats::median, na.rm = TRUE),
           sum(!is.na(ndvi)))
  names(out) <- c("ndvi", "ndmi", "n_obs")
  attr(out, "scenes") <- used
  attr(out, "dates") <- as.Date(scenes$datetime[match(used, scenes$id)])
  attr(out, "scene_log") <- data.frame(id = scenes$id, datetime = scenes$datetime,
                                       used = scenes$id %in% used, skip_reason = skip_reason,
                                       stringsAsFactors = FALSE)
  out
}

# One scene: crop each band to the AOI window, mask, scale, index. Scenes
# after the first are resampled (nearest) onto the first scene's grid; WRS
# paths in one UTM zone share the 30 m grid, so this is exact there.
read_landsat_window <- function(sc, aoi, buffer_m, template = NULL) {
  open <- function(key) terra::rast(paste0("/vsicurl/", pc_sign(sc[[key]])))
  qa <- open("qa")
  crs <- sf::st_crs(terra::crs(qa))
  win <- sf::st_buffer(sf::st_transform(sf::st_as_sfc(sf::st_bbox(aoi)), crs),
                       buffer_m / crs_m_per_unit(crs))
  e <- terra::ext(sf::st_bbox(win)[c("xmin", "xmax", "ymin", "ymax")])
  if (!terra::relate(terra::ext(qa), e, "intersects")) rlang::abort("scene does not cover the AOI")
  crop <- function(x) terra::crop(x, e, snap = "out")
  qa <- crop(qa)
  b <- lapply(c(red = "red", nir = "nir", swir1 = "swir1"), function(k) crop(open(k)))
  ok <- terra::app(qa, qa_clear)
  sr <- lapply(b, function(x) terra::mask(terra::app(x, sr_scale), ok, maskvalues = c(0, NA)))
  r <- c(norm_diff(sr$nir, sr$red), norm_diff(sr$nir, sr$swir1))
  names(r) <- c("ndvi", "ndmi")
  if (!is.null(template)) {
    if (!terra::same.crs(r, template)) r <- terra::project(r, template, method = "near")
    else if (!terra::compareGeom(r, template, stopOnError = FALSE)) r <- terra::resample(r, template, method = "near")
  }
  r
}

#' Dry-season greenness and moisture of grown-in canopy, per segment
#'
#' Joins a Landsat composite to the LiDAR screen. The LiDAR canopy height
#' model decides *which* 30 m pixels to read and how much each one counts:
#'
#' 1. The CHM is cleaned the way [assess_risk()] cleans it: cells within
#'    `structure_mask_m` of a support are unknown, and canopy needs
#'    `min_support` canopy cells in its 3 x 3 window (removes 1-2 cell poles
#'    and stray returns). Each Landsat pixel's canopy fraction is then the
#'    share of its *observed* 1 m cells at or above `cover_min_m`, and its
#'    coverage is the share of its whole 30 m footprint that the LiDAR
#'    observed. A pixel is scored only if it is canopy-dominated
#'    (`min_canopy_frac`), mostly observed (`min_coverage`: a pixel on the
#'    corridor edge or inside a bend otherwise rests on a sliver of canopy
#'    and its reflectance describes land outside the LiDAR clip) and has
#'    enough clear looks (`min_obs`).
#' 2. A segment's value is the mean of its pixels' indices weighted by how
#'    many of the segment's canopy cells *within `zone_m` of the line* fall
#'    in each pixel, so it describes the canopy under the conductors rather
#'    than the forest beside the right-of-way.
#' 3. Each segment value is ranked against every scored pixel in the
#'    corridor (a percentile, `*_pct`). `dry_canopy` flags segments in the
#'    lowest `dry_quantile` of `dry_index`. A segment resting on fewer than
#'    `min_canopy_px` pixels, or on less than `min_canopy_m2` of canopy,
#'    keeps its indices but gets no percentile: one mixed 30 m pixel cannot
#'    carry a ranking.
#'
#' `dry_grow_in` combines the two screens: grow-in under the optimistic
#' conductor bound and dry canopy; `dry_grow_in_lo` uses the pessimistic
#' tier. This is a prioritisation within one corridor, not a fire-danger
#' rating: low NDVI over canopy can also mean thin or recently trimmed crowns,
#' and a 30 m pixel straddling a 20-40 m right-of-way always mixes the
#' corridor's canopy with its edges.
#'
#' @param composite Output of [landsat_composite()].
#' @param rasters Output of [corridor_rasters()] (supplies the CHM).
#' @param profile Output of [conductor_profile()] (supplies the line
#'   geometry and segment ids).
#' @param risk Output of [assess_risk()].
#' @param zone_m Distance from the centreline within which canopy counts as
#'   grown in; normally `under_line_m` from [assess_risk()].
#' @param corridor_m Half-width of the corridor the point cloud was clipped
#'   to (`half_width_m` in [read_corridor()]). CHM cells farther from the line
#'   are outside the data and are excluded from canopy fractions, including
#'   the inside of bends that the terrain model's convex hull fills. `NULL`
#'   uses the farthest canopy return from the line.
#' @param cover_min_m Canopy height counted as cover.
#' @param structures,structure_mask_m As in [assess_risk()]: support points
#'   (OSM nodes and line vertices) whose surroundings are treated as unknown
#'   rather than canopy or bare ground. Pass the same objects as to
#'   [assess_risk()] so both screens describe the same canopy.
#' @param min_support As in [assess_risk()]: a cell counts as canopy only if
#'   at least this many cells of its 3 x 3 window are canopy. `0` disables
#'   the filter.
#' @param min_canopy_frac Minimum canopy fraction (of observed cells) for a
#'   Landsat pixel to be scored.
#' @param min_coverage Minimum share of a pixel's 30 m footprint observed by
#'   the LiDAR for it to be scored.
#' @param min_obs Minimum clear Landsat observations behind a pixel for it to
#'   be scored.
#' @param dry_index `"ndvi"` or `"ndmi"`: the index used for `dry_canopy`.
#' @param dry_quantile Percentile (0-1) at or below which a segment is
#'   `dry_canopy`.
#' @param min_canopy_m2,min_canopy_px Segments with less grown-in canopy than
#'   this (in scored pixels), or spread over fewer scored pixels, get their
#'   indices but no percentile or `dry_canopy`.
#' @param min_ref_px Minimum scored pixels in the corridor needed to compute
#'   percentiles; below it the `*_pct` columns are `NA`.
#' @return A list: `segments` (the risk segments with added columns
#'   `canopy_px`, `canopy_m2`, `ndvi`, `ndmi`, `ndvi_pct`, `ndmi_pct`,
#'   `dry_canopy`, `dry_grow_in`, `dry_grow_in_lo`) and `pixels` (`sf`
#'   points at Landsat pixel centres with `ndvi`, `ndmi`, `n_obs`,
#'   `canopy_frac`, `coverage`, `scored`). `attr(segments, "landsat")`
#'   records the gates and how many pixels each one excluded.
#' @export
canopy_dryness <- function(composite, rasters, profile, risk, zone_m = 6, corridor_m = NULL,
                           cover_min_m = 2, structures = NULL, structure_mask_m = 8,
                           min_support = 6, min_canopy_frac = 0.5, min_coverage = 0.8,
                           min_obs = 3, dry_index = c("ndvi", "ndmi"), dry_quantile = 0.25,
                           min_canopy_m2 = 5, min_canopy_px = 2, min_ref_px = 20) {
  dry_index <- match.arg(dry_index)
  chm <- rasters$chm
  crs <- sf::st_crs(terra::crs(chm))
  m <- crs_m_per_unit(crs)

  # Landsat grid in the LiDAR CRS. For a UTM point cloud this is a datum
  # shift of ~1 m; for a state-plane cloud the 30 m footprints are rotated
  # slightly, which nearest-neighbour resampling at 30 m keeps tolerable.
  ls <- terra::project(composite, terra::crs(chm), method = "near", res = 30 / m)
  ls <- terra::crop(ls, chm, snap = "out")

  # Empty CHM cells are bare ground inside the corridor. Outside it they are
  # unknown and stay out of the canopy fraction: the DTM is a TIN over the
  # ground points' convex hull, so it also fills the inside of every bend in
  # the line, and only distance from the line marks the corridor's edge.
  # Cells where conductor returns were removed are unknown too.
  xy <- terra::crds(chm, na.rm = FALSE)
  pr <- line_project(xy, profile, m)
  if (is.null(corridor_m)) corridor_m <- max(pr$dist_m[!is.na(terra::values(chm)[, 1])])
  canopy <- terra::ifel(is.na(chm), 0, chm >= cover_min_m)
  canopy <- terra::mask(canopy, rasters$dtm)
  canopy[pr$dist_m > corridor_m] <- NA
  if (!is.null(rasters$unobserved)) canopy <- terra::mask(canopy, rasters$unobserved, maskvalues = TRUE)
  # Coverage is judged before the structure mask: a tower pad is observed
  # ground, not a data gap, even though it is neither canopy nor bare.
  observed <- terra::ifel(is.na(canopy), 0, 1)
  if (!is.null(structures) && nrow(structures) > 0) {
    mask <- sf::st_union(sf::st_buffer(sf::st_transform(sf::st_geometry(structures), crs),
                                       structure_mask_m / m))
    canopy <- terra::mask(canopy, terra::vect(mask), inverse = TRUE, updatevalue = NA)
  }
  if (min_support > 0) {
    support <- terra::focal(canopy == 1, w = 3, fun = "sum", na.rm = TRUE)
    canopy <- terra::ifel(is.na(canopy), NA, terra::ifel(support >= min_support, canopy, 0))
  }
  frac <- terra::resample(canopy, ls, method = "average")
  # Observed cells over the whole footprint, including the part of a pixel
  # that lies beyond the CHM's extent (no source cells there = unobserved).
  cells_per_px <- prod(terra::res(ls) / terra::res(chm))
  coverage <- terra::resample(observed, ls, method = "sum") / cells_per_px
  coverage <- terra::ifel(is.na(coverage), 0, coverage)
  names(frac) <- "canopy_frac"
  names(coverage) <- "coverage"

  px <- terra::as.data.frame(c(ls, frac, coverage), xy = TRUE, cells = TRUE, na.rm = FALSE)
  px <- px[!is.na(px$ndvi) & !is.na(px$canopy_frac), ]
  gates <- list(canopy_frac = px$canopy_frac >= min_canopy_frac,
                coverage = px$coverage >= min_coverage,
                n_obs = !is.na(px$n_obs) & px$n_obs >= min_obs)
  px$scored <- Reduce(`&`, gates)
  # How many pixels each gate removed on its own, for the provenance record.
  n_excluded <- vapply(gates, function(g) sum(!g), 0L)

  # Grown-in canopy cells (1 m), tagged with their segment and Landsat pixel.
  v <- terra::values(canopy)[, 1]
  grown <- which(!is.na(v) & v == 1 & pr$dist_m <= zone_m)
  cc <- data.frame(seg_id = profile$seg_id[pr$vertex[grown]],
                   cell = terra::cellFromXY(ls, xy[grown, , drop = FALSE]))
  cc <- cc[cc$cell %in% px$cell[px$scored], ]
  cell_area <- prod(terra::res(chm)) * m^2

  ref <- px[px$scored, ]
  pct <- function(v, key) {
    if (nrow(ref) < min_ref_px) return(rep(NA_real_, length(v)))
    stats::ecdf(ref[[key]])(v)
  }

  seg <- risk$segments
  seg_stats <- lapply(seg$seg_id, function(s) {
    w <- table(cc$cell[cc$seg_id == s])
    if (length(w) == 0) {
      return(data.frame(canopy_px = 0L, canopy_m2 = 0, ndvi = NA_real_, ndmi = NA_real_))
    }
    v <- px[match(as.integer(names(w)), px$cell), ]
    data.frame(canopy_px = length(w), canopy_m2 = sum(w) * cell_area,
               ndvi = stats::weighted.mean(v$ndvi, w), ndmi = stats::weighted.mean(v$ndmi, w))
  })
  seg_stats <- do.call(rbind, seg_stats)
  for (k in names(seg_stats)) seg[[k]] <- seg_stats[[k]]
  # A few square metres of canopy, or a single mixed pixel, can't carry a
  # ranking: report the index, leave the percentile undefined.
  thin <- seg$canopy_m2 < min_canopy_m2 | seg$canopy_px < min_canopy_px
  seg$ndvi_pct <- ifelse(thin, NA_real_, pct(seg$ndvi, "ndvi"))
  seg$ndmi_pct <- ifelse(thin, NA_real_, pct(seg$ndmi, "ndmi"))
  seg$dry_canopy <- seg[[paste0(dry_index, "_pct")]] <= dry_quantile
  seg$dry_grow_in <- seg$priority == "grow-in" & seg$dry_canopy
  seg$dry_grow_in_lo <- seg$priority_lo == "grow-in" & seg$dry_canopy

  pixels <- sf::st_as_sf(px[, c("x", "y", "ndvi", "ndmi", "n_obs", "canopy_frac", "coverage", "scored")],
                         coords = c("x", "y"), crs = crs)
  attr(seg, "landsat") <- list(scenes = attr(composite, "scenes"), dates = attr(composite, "dates"),
                               n_ref_px = nrow(ref), n_px_excluded = n_excluded,
                               dry_index = dry_index, dry_quantile = dry_quantile,
                               min_canopy_frac = min_canopy_frac, min_coverage = min_coverage,
                               min_obs = min_obs, min_canopy_px = min_canopy_px,
                               structure_mask_m = if (!is.null(structures)) structure_mask_m,
                               min_support = min_support,
                               min_canopy_m2 = min_canopy_m2, corridor_m = corridor_m)
  list(segments = seg, pixels = pixels)
}
