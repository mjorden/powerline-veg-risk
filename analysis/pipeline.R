# Shared end-to-end pipeline for the case studies. Each site script builds a
# config list and calls run_case_study(cfg). Outputs go to output/<id>/,
# figures to man/figures/<id>_*.png, cached OSM layers to data-raw/<id>/.

devtools::load_all(quiet = TRUE)
suppressPackageStartupMessages({
  library(sf)
  library(data.table)
})

# Write-then-rename, so a crash mid-write never leaves a truncated RDS that
# a VEGRISK_REUSE run would read as a complete one (#30).
save_rds <- function(x, path) {
  tmp <- paste0(path, ".tmp")
  saveRDS(x, tmp)
  if (!file.rename(tmp, path)) stop("could not replace ", path, call. = FALSE)
  invisible(path)
}
git_sha <- function() {
  tryCatch(system2("git", c("rev-parse", "--short", "HEAD"), stdout = TRUE, stderr = FALSE),
           error = function(e) NA_character_, warning = function(w) NA_character_)
}

run_case_study <- function(cfg) {
  out <- file.path("output", cfg$id)
  raw <- file.path("data-raw", cfg$id)
  dir.create(out, showWarnings = FALSE, recursive = TRUE)
  dir.create(raw, showWarnings = FALSE, recursive = TRUE)
  fig <- function(name) file.path("man/figures", paste0(cfg$id, "_", name, ".png"))
  t0 <- Sys.time()
  # Every artefact of this run carries the same id; a reused model carries
  # the id of the run that fitted it.
  run_id <- paste0(format(t0, "%Y%m%dT%H%M%SZ", tz = "UTC"), "-", git_sha())
  step <- function(...) message(sprintf("[%s %5.0fs] ", cfg$id, as.numeric(Sys.time() - t0, units = "secs")), ...)
  # OSM layers are cached as GeoJSON with a sidecar recording the OSM
  # snapshot time and the query. An empty answer is not cached: Overpass
  # aborts are refused upstream (#8), but a genuinely empty area is still
  # re-queried next run rather than frozen.
  cache <- function(path, expr) {
    if (file.exists(path)) return(st_read(path, quiet = TRUE))
    x <- expr
    if (nrow(x) == 0) {
      warning(sprintf("%s: OSM returned nothing; not cached, will be re-queried next run.", basename(path)),
              call. = FALSE)
      return(x)
    }
    st_write(x, path, quiet = TRUE)
    jsonlite::write_json(list(osm_timestamp = attr(x, "osm_timestamp"), query = attr(x, "osm_query"),
                              fetched_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
                              n = nrow(x)),
                         paste0(path, ".meta.json"), auto_unbox = TRUE, pretty = TRUE)
    x
  }

  # --- 1. Inputs --------------------------------------------------------------
  lines <- cache(file.path(raw, "osm_line.geojson"), osm_power_lines(ids = cfg$line_ids))
  files <- file.path("data-raw/laz", cfg$id, cfg$tiles)
  if (!all(file.exists(files))) { # query The National Map only when tiles are missing
    tiles <- tnm_lidar_tiles(st_buffer(st_transform(lines, 4326), 0.001), project = cfg$project)
    tiles <- tiles[basename(tiles$url) %in% cfg$tiles, ]
    missing <- setdiff(cfg$tiles, basename(tiles$url))
    if (length(missing)) stop("Tiles not found on The National Map: ", paste(missing, collapse = ", "),
                              ". A missing tile would leave a hole in the corridor.", call. = FALSE)
    files <- download_tiles(tiles, dirname(files[1]))
  }
  # Tile identity and vintage: header record plus MD5 of every file (#52).
  tiles_info <- las_file_info(files)
  step(sprintf("tiles: %d files, %s points, created %s, %s, GPS time %s",
               nrow(tiles_info), format(sum(tiles_info$n_points), big.mark = ","),
               paste(unique(format(tiles_info$created)), collapse = " / "),
               paste(unique(tiles_info$system), collapse = " / "), unique(tiles_info$gps_time_type)[1]))
  crs <- st_crs(lidR::readLASheader(files[1]))
  m <- crs_m_per_unit(crs)
  extent <- st_as_sfc(st_bbox(lidR::readLAScatalog(files, progress = FALSE)))
  st_crs(extent) <- crs

  study <- st_transform(lines, crs)
  if (!is.null(cfg$window_m)) { # chainage window along the merged line
    g <- merge_lines(st_geometry(study))[1]
    if (!is.null(cfg$start_north) && cfg$start_north) {
      xy <- st_coordinates(g)
      if (xy[1, 2] < xy[nrow(xy), 2]) g <- st_sfc(st_linestring(xy[nrow(xy):1, 1:2]), crs = crs)
    }
    len <- as.numeric(st_length(g)) * m
    # The window is cut from one merged way; keep that way's tags.
    study <- st_sf(st_drop_geometry(study)[1, , drop = FALSE],
                   geometry = lwgeom::st_linesubstring(g, cfg$window_m[1] / len, cfg$window_m[2] / len))
  }
  study <- study[, intersect(c("osm_id", "name", "voltage_kv", "operator"), names(study))]
  st_agr(study) <- "constant"
  study <- st_intersection(study, st_buffer(extent, -cfg$half_width_m / m))
  aoi <- st_buffer(study, 100 / m)
  structures <- cache(file.path(raw, "osm_structures.geojson"), osm_power_structures(aoi))
  buildings  <- cache(file.path(raw, "osm_buildings.geojson"), osm_buildings(aoi))
  # Every mapped line in the area: rights-of-way are often shared, and the
  # other circuits' conductors need wire labels too.
  context <- cache(file.path(raw, "osm_lines_context.geojson"), osm_power_lines(aoi))
  step(sprintf("line in study area: %.0f m; %d mapped structures; %d buildings",
               sum(as.numeric(st_length(study))) * m, nrow(structures), nrow(buildings)))

  # --- 2. Corridor point cloud ------------------------------------------------
  las <- read_corridor(files, study, half_width_m = cfg$half_width_m)
  step("corridor points: ", format(lidR::npoints(las), big.mark = ","))
  vintage <- lidar_vintage(las)
  step(sprintf("flown %s to %s UTC (median %s; %s)",
               format(vintage$from, "%Y-%m-%d %H:%M"), format(vintage$to, "%Y-%m-%d %H:%M"),
               format(vintage$median, "%Y-%m-%d %H:%M"), vintage$gps_time_type))

  # --- 3. Features, weak labels, classifier -----------------------------------
  feat <- point_features(las)
  feat <- weak_labels(feat, crs, st_transform(context, crs), structures, buildings,
                      wire_search_m = cfg$wire_search_m)
  feat <- assign_blocks(feat, crs, block_m = 100, n_folds = 5)
  step("featurised ", format(nrow(feat), big.mark = ","), " above-ground points")
  print(table(feat$label, useNA = "ifany"))
  print(table(fold = feat$fold, label = feat$label))

  # VEGRISK_REUSE=1 reuses the saved model, its cross-validation and the
  # vendor evaluation (the slow, deterministic part) and recomputes the rest.
  # model.rds holds the model *and* the CV results it was fitted alongside,
  # written in one atomic step, so a rerun can never pair a new model with
  # an old run's metrics; summary.rds records which run it came from (#30).
  fit_path <- file.path(out, "model.rds")
  reuse <- Sys.getenv("VEGRISK_REUSE") == "1" && file.exists(fit_path)
  if (reuse) {
    fit <- readRDS(fit_path)
    if (is.null(fit$cv)) stop(fit_path, " predates the run record (#30); run once without VEGRISK_REUSE.",
                              call. = FALSE)
    model <- fit$model
    cv <- fit$cv
    metrics <- cv$metrics
    cv_summary <- cv$summary
    reused_from <- list(run_id = fit$run_id, fitted_at = fit$fitted_at,
                        model_md5 = unname(tools::md5sum(fit_path)))
    step("reusing model and cross-validation from run ", fit$run_id)
  } else {
    cv <- cv_point_classifier(feat)
    ablation <- cv_point_classifier(feat, drop_features = rule_proxy_features)
    ablation$metrics <- ablation$metrics[ablation$metrics$scheme == "spatial_block", ]
    ablation$metrics$scheme <- "spatial_ablation"
    ablation$summary <- ablation$summary[ablation$summary$scheme == "spatial_block", ]
    ablation$summary$scheme <- "spatial_ablation"
    metrics <- rbind(cv$metrics, ablation$metrics)
    cv_summary <- rbind(cv$summary, ablation$summary)
    step("cross-validation done")
    model <- train_point_classifier(feat)
    fit <- list(run_id = run_id, fitted_at = t0, git_sha = git_sha(), model = model,
                cv = list(metrics = metrics, summary = cv_summary,
                          confusion = cv$confusion, fold_counts = cv$fold_counts))
    save_rds(fit, fit_path)
    reused_from <- NULL
  }
  print(metrics, digits = 3)
  print(cv_summary, digits = 3)
  fwrite(metrics, file.path(out, "cv_metrics.csv"))
  fwrite(cv_summary, file.path(out, "cv_summary.csv"))
  pred <- predict_points(model, feat)
  print(table(predicted = pred$pred, weak_label = pred$label, useNA = "ifany"))

  vc <- las$Classification[feat$pid]
  has_vendor <- isTRUE(cfg$vendor_classes)
  vendor_bldg <- if (has_vendor) vc == 6L else NULL

  # --- 4. Conductor model -----------------------------------------------------
  segments <- segment_lines(study, crs, seg_m = 50, ways = lines)
  # Structures and spans along the unclipped way: the stable keys (#53).
  structures_tbl <- line_structures(lines, structures, crs)
  spans <- line_spans(lines, structures, crs)
  step(sprintf("spans: %d between %d confirmed structures on %d way(s); %d implausibly long (missing structure?)",
               nrow(spans), sum(structures_tbl$confirmed), length(unique(spans$way_id)), sum(spans$implausible)))
  rasters <- corridor_rasters(las, pred, res_m = 1, drop = vendor_bldg)
  # Supports for the upper bound: vertices of the *unclipped* line that a
  # tagged pole or tower confirms (#51); every vertex only when none is
  # tagged. Supports outside the data are dropped downstream.
  all_supports <- line_supports(lines, structures, crs)
  supports <- all_supports[all_supports$use, ]
  step(sprintf("supports: %d line vertices, %d confirmed by tagged structures, %d used for the upper bound",
               nrow(all_supports), sum(all_supports$confirmed), nrow(supports)))
  # Masking is the conservative direction: every tagged structure and every
  # vertex of every circuit sharing the corridor.
  mask_supports <- st_sf(geometry = c(st_geometry(st_transform(structures, crs)),
                                      st_geometry(line_vertex_points(st_transform(lines, crs))),
                                      st_geometry(line_vertex_points(st_transform(context, crs)))))
  profile <- conductor_profile(pred, segments, rasters$dtm, supports = supports,
                               search_m = cfg$wire_search_m, structure_mask_m = cfg$structure_mask_m,
                               min_ground_clear_m = cfg$min_ground_clear_m, attach_m = cfg$attach_m)
  step(sprintf("conductor measured along %.0f%% of the line; upper bound unknown along %.0f%%",
               100 * mean(profile$src == "measured"), 100 * mean(is.infinite(profile$z_hi))))
  bl <- colSums(attr(profile, "bins")[, -1])
  step(sprintf("conductor bins: %d with returns; rejected %d (too few points), %d (below code minimum), %d (implausible slope); %d measured, %d of them above the support chord",
               bl[["n_bins"]], bl[["n_too_few"]], bl[["n_below_floor"]], bl[["n_implausible"]], bl[["n_measured"]],
               bl[["n_above_upper_bound"]]))
  # Parameters that assess_risk() and wind_fall_exposure() must agree on
  # come from the config once (#21).
  growth_m <- if (is.null(cfg$growth_m)) 0 else cfg$growth_m

  # Conductor envelope from where conductor returns actually are, capped at
  # the grow-in zone so side trees keep their tops for the fall-in test.
  pr_all <- line_project(as.matrix(feat[, .(X, Y)]), profile, m)
  rule_wire <- feat$label %in% "wire" & pr_all$dist_m <= cfg$wire_search_m
  envelope_needed <- if (any(rule_wire)) {
    stats::quantile(abs(pr_all$offset_m[rule_wire]), 0.98, names = FALSE) + 2
  } else cfg$under_line_m
  envelope_m <- min(envelope_needed, cfg$under_line_m)
  if (envelope_needed > cfg$under_line_m) {
    warning(sprintf(paste("Conductor returns reach %.1f m from the centreline but under_line_m is %g m;",
                          "outer-phase returns beyond it will be scored as trees. Widen under_line_m."),
                    envelope_needed, cfg$under_line_m), call. = FALSE)
  }
  step("conductor-return offsets from OSM centreline (m); envelope ", round(envelope_m, 1), " m:")
  if (any(rule_wire)) print(quantile(pr_all$offset_m[rule_wire], c(0.02, 0.25, 0.5, 0.75, 0.98)), digits = 2)

  # Geometric conductor zone, independent of every labelling method: inside
  # the envelope, where the conductor is measured, within 3 m of it or above.
  zabs <- las$Zref[feat$pid] * m
  conductor_zone <- profile$src[pr_all$vertex] == "measured" & pr_all$dist_m <= envelope_m &
    zabs >= profile$z_lo[pr_all$vertex] - 3

  # --- 5. Classifier vs vendor ground truth -------------------------------------
  # The vendor evaluation is reused only when it was computed from the model
  # being reused (same run id); otherwise it is recomputed.
  vendor <- NULL
  vendor_path <- file.path(out, "vendor.rds")
  if (reuse && file.exists(vendor_path)) {
    v <- readRDS(vendor_path)
    if (identical(v$model_run_id, fit$run_id)) vendor <- v$vendor
    else step("vendor evaluation on disk is from another run; recomputing")
  }
  if (is.null(vendor) && has_vendor) {
    sc <- !conductor_zone  # same scored set for every method
    cut_vc <- function(x) cut(x, c(-Inf, 1, 2, 5, 6, Inf),
                              labels = c("unclassified", "ground", "vegetation", "building", "other"))
    raw_wire <- function(model) {
      p <- stats::predict(model, as.data.frame(
        feat[, model$forest$independent.variable.names, with = FALSE]))$predictions
      if ("wire" %in% colnames(p)) p[, "wire"] else rep(0, nrow(p))  # model never saw wire
    }
    wire_skill <- function(lab, p) data.frame(
      wire_recall = mean(lab[feat$label %in% "wire"] == "wire"),
      wire_ap = avg_precision(p, feat$label %in% "wire"),
      wire_prevalence = mean(feat$label %in% "wire"))
    vendor <- list(
      conductor_zone_vendor_class = table(cut_vc(vc[conductor_zone])),
      rule_wire_vendor_class = table(cut_vc(vc[feat$label %in% "wire"])),
      weak  = evaluate_vendor_classes(feat$label[sc], vc[sc]),
      model = evaluate_vendor_classes(pred$pred[sc], vc[sc]),
      model_wire = wire_skill(pred$pred, raw_wire(model))
    )
    if (!is.null(cfg$transfer_from)) {
      path <- file.path("output", cfg$transfer_from, "model.rds")
      other_fit <- readRDS(path)
      if (is.null(other_fit$model)) stop(path, " predates the run record (#30); re-run ",
                                         cfg$transfer_from, " first.", call. = FALSE)
      other <- other_fit$model
      p <- classify_probs(other, feat)  # with the other site's class prior
      lab <- factor(colnames(p)[max.col(p, "first")], levels = label_levels)
      vendor$transfer <- evaluate_vendor_classes(lab[sc], vc[sc])
      vendor$transfer_wire <- wire_skill(lab, raw_wire(other))  # AP is prior-free
      vendor$transfer_model <- list(path = path, run_id = other_fit$run_id,
                                    fitted_at = other_fit$fitted_at, md5 = unname(tools::md5sum(path)))
    }
    # Vendor-supervised reference (vegetation/building only), spatial CV.
    vfeat <- data.table::copy(feat)
    vfeat[, label := factor(ifelse(vc %in% 3:5, "vegetation", ifelse(vc == 6L, "building", NA)),
                            levels = label_levels)]
    vfeat[conductor_zone, label := NA]
    ref <- cv_point_classifier(vfeat, random = FALSE)
    vendor$reference <- ref$metrics
    vendor$reference_summary <- ref$summary
    save_rds(list(model_run_id = fit$run_id, vendor = vendor), vendor_path)

    step("vendor classes in the conductor zone, and of rule-labelled conductor returns:")
    print(vendor$conductor_zone_vendor_class)
    print(vendor$rule_wire_vendor_class)
    step("vs vendor (outside conductor zone): baseline / weak labels / model / transfer")
    for (nm in c("weak", "model", "transfer")) if (!is.null(vendor[[nm]])) {
      if (nm == "weak") {
        print(vendor$weak$baseline$metrics, digits = 3)
        print(vendor$weak$baseline$summary, digits = 3)
      }
      print(vendor[[nm]]$metrics, digits = 3)
      print(vendor[[nm]]$summary, digits = 3)
    }
    step("wire skill (rule labels): model / transfer")
    print(rbind(model = vendor$model_wire, transfer = vendor$transfer_wire), digits = 3)
    step("vendor-supervised reference (spatial CV):")
    print(vendor$reference, digits = 3)
    print(vendor$reference_summary, digits = 3)
  }

  # --- 6. Risk ----------------------------------------------------------------
  screen <- function(pr, drop = NULL, exclude = TRUE) {
    r <- corridor_rasters(las, pr, res_m = 1, profile = if (exclude) profile,
                          envelope_m = envelope_m, drop = drop)
    list(rasters = r, risk = assess_risk(r, profile, segments, phase_offset_m = cfg$phase_offset_m,
                                         growth_m = growth_m,
                                         under_line_m = cfg$under_line_m, wire_zone_m = cfg$wire_zone_m,
                                         structures = mask_supports, structure_mask_m = cfg$structure_mask_m,
                                         coverage_m = cfg$half_width_m))
  }
  ours <- screen(pred, drop = vendor_bldg)
  rasters <- ours$rasters
  risk <- ours$risk
  # Valid-from for every segment: the flight window of its own returns.
  if (!is.null(vintage$time)) {
    fw <- segment_flight_window(vintage$time[feat$pid], profile$seg_id[pr_all$vertex])
    risk$segments <- merge(risk$segments, fw, by = "seg_id", all.x = TRUE)
  }
  step(sprintf("excluded %s wire-like conductor-envelope points from the canopy model",
               format(rasters$n_conductor_excluded, big.mark = ",")))
  print(table(optimistic = risk$segments$priority, pessimistic = risk$segments$priority_lo))
  step(sprintf("strike trees: %d at some plausible conductor height, %d at every plausible height (%d / %d at the lower / upper bound alone)",
               sum(risk$trees$strike_possible), sum(risk$trees$strike_certain),
               sum(risk$trees$strike_lo), sum(risk$trees$strike_hi)))
  print(table(risk$segments$confidence))
  step(sprintf("LiDAR coverage: %d uncertain points excluded; segment coverage median %.2f, min %.2f (under line min %.2f); %d 'no data'",
               ours$rasters$n_uncertain_excluded, stats::median(risk$segments$frac_observed),
               min(risk$segments$frac_observed), min(risk$segments$frac_observed_under),
               sum(risk$segments$priority_lo == "no data")))

  # Same screen on canopy models built from the vendor's vegetation classes:
  # as delivered, and with the same conductor exclusion (separates the
  # exclusion effect from the classifier effect).
  vendor_screens <- NULL
  if (has_vendor) {
    vv <- vc %in% 3:5
    vpred <- data.table::copy(pred)
    vpred[, `:=`(pred = factor(ifelse(vv, "vegetation", "building"), levels = label_levels),
                 label = factor(ifelse(vv, "vegetation", "building"), levels = label_levels))]
    vendor_screens <- list(
      as_delivered = table(screen(vpred, exclude = FALSE)$risk$segments$priority),
      with_exclusion = table(screen(vpred)$risk$segments$priority),
      ours = table(risk$segments$priority)
    )
    step("segment priority (optimistic tier): vendor as delivered / vendor + exclusion / ours")
    print(do.call(rbind, vendor_screens))
  }
  print(st_drop_geometry(risk$segments)[1:min(8, nrow(risk$segments)), ], digits = 3)

  # --- 6b. Landsat canopy greenness / moisture (optional) ----------------------
  # cfg$landsat = list(years, months, dry_index): a dry-season median composite
  # over the corridor, read only where LiDAR says canopy has grown in.
  dryness <- NULL
  if (!is.null(cfg[["landsat"]])) {
    lc <- cfg[["landsat"]]
    comp_path <- file.path(out, "landsat_composite.tif")
    scenes_path <- file.path(out, "landsat_scenes.csv")
    # landsat_scenes.csv lists every scene found, with `used` and
    # `skip_reason`. A composite that lost scenes to read errors (not to
    # "no coverage") is used this run but not cached, so a network blip
    # cannot become permanent (#30).
    if (file.exists(comp_path) && file.exists(scenes_path)) {
      comp <- terra::rast(comp_path)
      scene_log <- fread(scenes_path)
      if (!"used" %in% names(scene_log)) scene_log[, `:=`(used = TRUE, skip_reason = NA_character_)]
      used <- scene_log[used == TRUE]
      attr(comp, "scenes") <- used$id
      attr(comp, "dates") <- as.Date(used$datetime)
      attr(comp, "scene_log") <- as.data.frame(scene_log)
    } else {
      corridor_area <- st_buffer(study, cfg$half_width_m / m)
      scenes <- landsat_scenes(corridor_area, years = lc$years, months = lc$months)
      comp <- landsat_composite(scenes, corridor_area)
      scene_log <- merge(scenes[, c("id", "datetime", "platform", "cloud_cover")],
                         attr(comp, "scene_log")[, c("id", "used", "skip_reason")], by = "id")
      errored <- !scene_log$used & !scene_log$skip_reason %in% "no coverage"
      max_err <- if (is.null(lc$max_error_frac)) 0.2 else lc$max_error_frac
      if (mean(errored) > max_err) {
        warning(sprintf(paste("Landsat: %d of %d scenes failed to read; the composite is used for this run",
                              "but not cached. Re-run, or raise landsat$max_error_frac to accept it."),
                        sum(errored), nrow(scene_log)), call. = FALSE)
      } else {
        terra::writeRaster(comp, comp_path, overwrite = TRUE)
        fwrite(scene_log, scenes_path)
      }
    }
    scene_counts <- c(found = nrow(scene_log), used = sum(scene_log$used),
                      no_coverage = sum(scene_log$skip_reason %in% "no coverage"),
                      error = sum(!scene_log$used & !scene_log$skip_reason %in% "no coverage"))
    dryness <- canopy_dryness(comp, rasters, profile, risk, zone_m = cfg$under_line_m,
                              corridor_m = cfg$half_width_m,
                              structures = mask_supports, structure_mask_m = cfg$structure_mask_m,
                              dry_index = if (is.null(lc$dry_index)) "ndvi" else lc$dry_index)
    li <- attr(dryness$segments, "landsat")
    step(sprintf("Landsat: %d of %d dry-season scenes used (%d no coverage, %d read errors); %d scored canopy pixels (excluded: %d under %.0f%% canopy, %d under %.0f%% coverage, %d under %d clear looks)",
                 scene_counts[["used"]], scene_counts[["found"]], scene_counts[["no_coverage"]],
                 scene_counts[["error"]], li$n_ref_px,
                 li$n_px_excluded[["canopy_frac"]], 100 * li$min_canopy_frac,
                 li$n_px_excluded[["coverage"]], 100 * li$min_coverage,
                 li$n_px_excluded[["n_obs"]], li$min_obs))
    print(table(grow_in = dryness$segments$priority == "grow-in",
                dry_canopy = dryness$segments$dry_canopy, useNA = "ifany"))
    risk$segments <- dryness$segments
    plot_canopy_dryness(dryness, file = fig("canopy_dryness"))
  }

  # --- 6c. Fire-weather wind (optional) -----------------------------------------
  # cfg$wind = list(start, end, gust_quantile, max_rh, spread_deg): which
  # strike trees the dry, high-wind hours of the record would throw into the
  # line. The hourly record is cached; analysis/watchlist.R applies the same
  # geometry to the live NWS forecast.
  if (!is.null(cfg[["wind"]])) { # [[ ]]: cfg$wind would partial-match window_m
    wc <- cfg[["wind"]]
    wind_path <- file.path(out, "wind_hourly.csv")
    if (file.exists(wind_path)) {
      wind <- fread(wind_path)
      wind$time <- as.POSIXct(wind$time, tz = "UTC")
      ll <- readRDS(file.path(out, "wind_cell.rds"))
      attr(wind, "lon") <- ll[1]
      attr(wind, "lat") <- ll[2]
    } else {
      wind <- wind_history(study, wc$start, wc$end)
      fwrite(wind, wind_path)
      saveRDS(c(attr(wind, "lon"), attr(wind, "lat")), file.path(out, "wind_cell.rds"))
    }
    fw <- fire_wind_hours(wind, gust_quantile = if (is.null(wc$gust_quantile)) 0.95 else wc$gust_quantile,
                          max_rh = if (is.null(wc$max_rh)) 30 else wc$max_rh)
    attr(fw, "lon") <- attr(wind, "lon")
    attr(fw, "lat") <- attr(wind, "lat")
    risk <- wind_fall_exposure(risk, profile, fw, phase_offset_m = cfg$phase_offset_m,
                               growth_m = growth_m,
                               spread_deg = if (is.null(wc$spread_deg)) 15 else wc$spread_deg)
    wi <- attr(risk$segments, "wind")
    step(sprintf("wind: %d fire-weather hours of %d (gust >= %.1f m/s, RH <= %g%%); grid convergence %.2f deg",
                 wi$n_hours, wi$n_record, wi$min_gust_ms, wi$max_rh, wi$convergence_deg))
    for (b in c("lo", "hi")) {
      s <- risk$trees[[paste0("strike_", b)]]
      h <- risk$trees[[paste0("wind_hit_", b)]][s]
      step(sprintf("  %s bound: %d strike trees, %d windward (>= %.0f%% of hours), wind-weighted count %.1f",
                   b, sum(s), sum(h >= wi$windward_min), 100 * wi$windward_min, sum(h)))
    }
    plot_wind_exposure(risk, rasters, bound = "lo", file = fig("wind_exposure"))
  }

  # Span roll-up: the 50 m stations summarised per structure-to-structure span.
  risk$spans <- span_summary(risk$segments, spans, lines)
  print(st_drop_geometry(risk$spans)[, c("span_id", "length_m", "n_segments", "priority", "priority_lo",
                                          "confidence", "n_strike_possible", "n_strike_certain")], digits = 3)
  st_write(risk$segments, file.path(out, "segments.gpkg"), delete_dsn = TRUE, quiet = TRUE)
  st_write(risk$trees, file.path(out, "trees.gpkg"), delete_dsn = TRUE, quiet = TRUE)
  st_write(risk$spans, file.path(out, "spans.gpkg"), delete_dsn = TRUE, quiet = TRUE)
  st_write(structures_tbl, file.path(out, "structures.gpkg"), delete_dsn = TRUE, quiet = TRUE)
  fwrite(st_drop_geometry(risk$segments), file.path(out, "segments.csv"))
  fwrite(st_drop_geometry(risk$spans), file.path(out, "spans.csv"))
  fwrite(profile, file.path(out, "conductor_profile.csv"))
  summary <- list(run = list(id = run_id, started = t0, git_sha = git_sha(),
                             model_run_id = fit$run_id, reused_from = reused_from),
                  lidar = list(project = cfg$project, tiles = tiles_info,
                               gps_time_type = vintage$gps_time_type, n_timed = vintage$n,
                               flight_from = vintage$from, flight_median = vintage$median, flight_to = vintage$to),
                  metrics = metrics, cv_summary = cv_summary,
                  confusion = cv$confusion, fold_counts = cv$fold_counts,
                  importance = model$variable.importance, vendor = vendor,
                  vendor_screens = vendor_screens,
                  envelope_m = envelope_m, envelope_needed = envelope_needed,
                  label_table = table(feat$label, useNA = "ifany"), pred_table = table(pred$pred),
                  frac_measured = mean(profile$src == "measured"),
                  conductor_bins = attr(profile, "bins"),
                  frac_unbounded = mean(is.infinite(profile$z_hi)),
                  priority = table(risk$segments$priority),
                  priority_by_confidence = table(risk$segments$priority, risk$segments$confidence),
                  n_strike = c(lo = sum(risk$trees$strike_lo), hi = sum(risk$trees$strike_hi),
                               possible = sum(risk$trees$strike_possible), certain = sum(risk$trees$strike_certain)),
                  supports = c(vertices = nrow(all_supports), confirmed = sum(all_supports$confirmed), used = nrow(supports)),
                  spans = list(n = nrow(spans), n_implausible = sum(spans$implausible),
                               priority = table(risk$spans$priority), confidence = table(risk$spans$confidence),
                               canonical_crs = canonical_crs(risk$segments)$epsg),
                  n_conductor_excluded = rasters$n_conductor_excluded,
                  landsat = if (!is.null(dryness)) attr(dryness$segments, "landsat"),
                  landsat_scenes = if (!is.null(dryness)) scene_counts,
                  wind = if (!is.null(attr(risk$segments, "wind"))) {
                    w <- attr(risk$segments, "wind")
                    w$dir_from_deg <- NULL  # the hours are in wind_hourly.csv
                    w
                  },
                  dry_grow_in = if (!is.null(dryness)) {
                    c(hi = sum(dryness$segments$dry_grow_in, na.rm = TRUE),
                      lo = sum(dryness$segments$dry_grow_in_lo, na.rm = TRUE))
                  })
  save_rds(summary, file.path(out, "summary.rds"))

  # --- 7. Figures -------------------------------------------------------------
  plot_risk_map(rasters, risk, supports, title = cfg$title, source = cfg$source,
                file = fig("risk_map"))
  plot_profile(profile, risk, attach_m = cfg$attach_m, file = fig("conductor_profile"))
  plot_cross_section(las, pred, study, fig("cross_section"),
                     at = cfg$section_m / (sum(as.numeric(st_length(study))) * m),
                     half_len_m = cfg$half_width_m - 5)
  plot_cv(metrics, fig("cv_metrics"))
  plot_importance(model, fig("importance"))
  step("done")
  invisible(list(feat = feat, pred = pred, las = las, model = model, risk = risk,
                 profile = profile, summary = summary))
}
