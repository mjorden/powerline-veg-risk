# Shared end-to-end pipeline for the case studies. Each site script builds a
# config list and calls run_case_study(cfg). Outputs go to output/<id>/,
# figures to man/figures/<id>_*.png, cached OSM layers to data-raw/<id>/.

devtools::load_all(quiet = TRUE)
suppressPackageStartupMessages({
  library(sf)
  library(data.table)
})

run_case_study <- function(cfg) {
  out <- file.path("output", cfg$id)
  raw <- file.path("data-raw", cfg$id)
  dir.create(out, showWarnings = FALSE, recursive = TRUE)
  dir.create(raw, showWarnings = FALSE, recursive = TRUE)
  fig <- function(name) file.path("man/figures", paste0(cfg$id, "_", name, ".png"))
  t0 <- Sys.time()
  step <- function(...) message(sprintf("[%s %5.0fs] ", cfg$id, as.numeric(Sys.time() - t0, units = "secs")), ...)
  cache <- function(path, expr) {
    if (file.exists(path)) return(st_read(path, quiet = TRUE))
    x <- expr
    st_write(x, path, quiet = TRUE)
    x
  }

  # --- 1. Inputs --------------------------------------------------------------
  lines <- cache(file.path(raw, "osm_line.geojson"), osm_power_lines(ids = cfg$line_ids))
  files <- file.path("data-raw/laz", cfg$id, cfg$tiles)
  if (!all(file.exists(files))) { # query The National Map only when tiles are missing
    tiles <- tnm_lidar_tiles(st_buffer(st_transform(lines, 4326), 0.001), project = cfg$project)
    tiles <- tiles[basename(tiles$url) %in% cfg$tiles, ]
    files <- download_tiles(tiles, dirname(files[1]))
  }
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
    study <- st_sf(geometry = lwgeom::st_linesubstring(g, cfg$window_m[1] / len, cfg$window_m[2] / len))
  }
  study <- st_intersection(st_geometry(study), st_buffer(extent, -cfg$half_width_m / m))
  study <- st_sf(geometry = study)
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

  # --- 3. Features, weak labels, classifier -----------------------------------
  feat <- point_features(las)
  feat <- weak_labels(feat, crs, st_transform(context, crs), structures, buildings,
                      wire_search_m = cfg$wire_search_m)
  feat <- assign_blocks(feat, crs, block_m = 100, n_folds = 5)
  step("featurised ", format(nrow(feat), big.mark = ","), " above-ground points")
  print(table(feat$label, useNA = "ifany"))
  print(table(fold = feat$fold, label = feat$label))

  # VEGRISK_REUSE=1 reuses the saved model, cross-validation and vendor
  # evaluation (the slow, deterministic part) and recomputes the rest.
  reuse <- Sys.getenv("VEGRISK_REUSE") == "1" &&
    all(file.exists(file.path(out, c("summary.rds", "model.rds"))))
  if (reuse) {
    old <- readRDS(file.path(out, "summary.rds"))
    metrics <- old$metrics
    cv <- list(confusion = old$confusion, fold_counts = old$fold_counts)
    model <- readRDS(file.path(out, "model.rds"))
    step("reusing saved model and cross-validation results")
  } else {
    cv <- cv_point_classifier(feat)
    ablation <- cv_point_classifier(feat, drop_features = rule_proxy_features)
    ablation$metrics <- ablation$metrics[ablation$metrics$scheme == "spatial_block", ]
    ablation$metrics$scheme <- "spatial_ablation"
    metrics <- rbind(cv$metrics, ablation$metrics)
    step("cross-validation done")
    model <- train_point_classifier(feat)
    saveRDS(model, file.path(out, "model.rds"))
  }
  print(metrics, digits = 3)
  fwrite(metrics, file.path(out, "cv_metrics.csv"))
  pred <- predict_points(model, feat)
  print(table(predicted = pred$pred, weak_label = pred$label, useNA = "ifany"))

  vc <- las$Classification[feat$pid]
  has_vendor <- isTRUE(cfg$vendor_classes)
  vendor_bldg <- if (has_vendor) vc == 6L else NULL

  # --- 4. Conductor model -----------------------------------------------------
  segments <- segment_lines(study, crs, seg_m = 50)
  rasters <- corridor_rasters(las, pred, res_m = 1, drop = vendor_bldg)
  # Supports: tagged OSM poles/towers plus the vertices of the *unclipped*
  # line (OSM mappers put a node at each structure; clipping adds end points
  # that are not structures). Supports outside the data are dropped.
  supports <- st_sf(geometry = c(st_geometry(st_transform(structures, crs)),
                                 st_geometry(line_vertex_points(st_transform(lines, crs)))))
  # Masking also covers the towers of other circuits sharing the corridor.
  mask_supports <- st_sf(geometry = c(st_geometry(supports),
                                      st_geometry(line_vertex_points(st_transform(context, crs)))))
  profile <- conductor_profile(pred, segments, rasters$dtm, supports = supports,
                               search_m = cfg$wire_search_m, structure_mask_m = cfg$structure_mask_m,
                               min_ground_clear_m = cfg$min_ground_clear_m, attach_m = cfg$attach_m)
  step(sprintf("conductor measured along %.0f%% of the line; upper bound unknown along %.0f%%",
               100 * mean(profile$src == "measured"), 100 * mean(is.infinite(profile$z_hi))))

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
  vendor <- NULL
  if (reuse && !is.null(old$vendor)) {
    vendor <- old$vendor
  } else if (has_vendor) {
    sc <- !conductor_zone  # same scored set for every method
    cut_vc <- function(x) cut(x, c(-Inf, 1, 2, 5, 6, Inf),
                              labels = c("unclassified", "ground", "vegetation", "building", "other"))
    raw_wire <- function(model) stats::predict(model, as.data.frame(
      feat[, model$forest$independent.variable.names, with = FALSE]))$predictions[, "wire"]
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
      other <- readRDS(path)
      p <- classify_probs(other, feat)  # with the other site's class prior
      lab <- factor(colnames(p)[max.col(p, "first")], levels = label_levels)
      vendor$transfer <- evaluate_vendor_classes(lab[sc], vc[sc])
      vendor$transfer_wire <- wire_skill(lab, raw_wire(other))  # AP is prior-free
      vendor$transfer_model <- list(path = path, mtime = file.mtime(path))
    }
    # Vendor-supervised reference (vegetation/building only), spatial CV.
    vfeat <- data.table::copy(feat)
    vfeat[, label := factor(ifelse(vc %in% 3:5, "vegetation", ifelse(vc == 6L, "building", NA)),
                            levels = label_levels)]
    vfeat[conductor_zone, label := NA]
    vendor$reference <- cv_point_classifier(vfeat, random = FALSE)$metrics

    step("vendor classes in the conductor zone, and of rule-labelled conductor returns:")
    print(vendor$conductor_zone_vendor_class)
    print(vendor$rule_wire_vendor_class)
    step("vs vendor (outside conductor zone): baseline / weak labels / model / transfer")
    for (nm in c("weak", "model", "transfer")) if (!is.null(vendor[[nm]])) {
      if (nm == "weak") print(vendor$weak$baseline, digits = 3)
      print(vendor[[nm]]$metrics, digits = 3)
    }
    step("wire skill (rule labels): model / transfer")
    print(rbind(model = vendor$model_wire, transfer = vendor$transfer_wire), digits = 3)
    step("vendor-supervised reference (spatial CV):")
    print(vendor$reference, digits = 3)
  }

  # --- 6. Risk ----------------------------------------------------------------
  screen <- function(pr, drop = NULL, exclude = TRUE) {
    r <- corridor_rasters(las, pr, res_m = 1, profile = if (exclude) profile,
                          envelope_m = envelope_m, drop = drop)
    list(rasters = r, risk = assess_risk(r, profile, segments, phase_offset_m = cfg$phase_offset_m,
                                         under_line_m = cfg$under_line_m, wire_zone_m = cfg$wire_zone_m,
                                         structures = mask_supports, structure_mask_m = cfg$structure_mask_m))
  }
  ours <- screen(pred, drop = vendor_bldg)
  rasters <- ours$rasters
  risk <- ours$risk
  step(sprintf("excluded %s wire-like conductor-envelope points from the canopy model",
               format(rasters$n_conductor_excluded, big.mark = ",")))
  print(table(optimistic = risk$segments$priority, pessimistic = risk$segments$priority_lo))
  print(table(risk$segments$confidence))

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
  if (!is.null(cfg$landsat)) {
    lc <- cfg$landsat
    comp_path <- file.path(out, "landsat_composite.tif")
    scenes_path <- file.path(out, "landsat_scenes.csv")
    if (file.exists(comp_path) && file.exists(scenes_path)) {
      comp <- terra::rast(comp_path)
      used <- fread(scenes_path)
      attr(comp, "scenes") <- used$id
      attr(comp, "dates") <- as.Date(used$datetime)
    } else {
      corridor_area <- st_buffer(study, cfg$half_width_m / m)
      scenes <- landsat_scenes(corridor_area, years = lc$years, months = lc$months)
      comp <- landsat_composite(scenes, corridor_area)
      terra::writeRaster(comp, comp_path, overwrite = TRUE)
      fwrite(scenes[scenes$id %in% attr(comp, "scenes"), c("id", "datetime", "platform", "cloud_cover")],
             scenes_path)
    }
    dryness <- canopy_dryness(comp, rasters, profile, risk, zone_m = cfg$under_line_m,
                              corridor_m = cfg$half_width_m,
                              structures = mask_supports, structure_mask_m = cfg$structure_mask_m,
                              dry_index = if (is.null(lc$dry_index)) "ndvi" else lc$dry_index)
    li <- attr(dryness$segments, "landsat")
    step(sprintf("Landsat: %d dry-season scenes; %d scored canopy pixels (excluded: %d under %.0f%% canopy, %d under %.0f%% coverage, %d under %d clear looks)",
                 length(attr(comp, "scenes")), li$n_ref_px,
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
  if (!is.null(cfg$wind)) {
    wc <- cfg$wind
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
                               spread_deg = if (is.null(wc$spread_deg)) 15 else wc$spread_deg)
    wi <- attr(risk$segments, "wind")
    step(sprintf("wind: %d fire-weather hours of %d (gust >= %.1f m/s, RH <= %g%%); grid convergence %.2f deg",
                 wi$n_hours, wi$n_record, wi$min_gust_ms, wi$max_rh, wi$convergence_deg))
    for (b in c("lo", "hi")) {
      s <- risk$trees[[paste0("strike_", b)]]
      h <- risk$trees[[paste0("wind_hit_", b)]][s]
      step(sprintf("  %s bound: %d strike trees, %d windward (>= %.0f%% of hours), %.1f expected per fire-weather hour",
                   b, sum(s), sum(h >= wi$windward_min), 100 * wi$windward_min, sum(h)))
    }
    plot_wind_exposure(risk, rasters, bound = "lo", file = fig("wind_exposure"))
  }

  st_write(risk$segments, file.path(out, "segments.gpkg"), delete_dsn = TRUE, quiet = TRUE)
  st_write(risk$trees, file.path(out, "trees.gpkg"), delete_dsn = TRUE, quiet = TRUE)
  fwrite(st_drop_geometry(risk$segments), file.path(out, "segments.csv"))
  fwrite(profile, file.path(out, "conductor_profile.csv"))
  summary <- list(metrics = metrics, confusion = cv$confusion, fold_counts = cv$fold_counts,
                  importance = model$variable.importance, vendor = vendor,
                  vendor_screens = vendor_screens, envelope_m = envelope_m,
                  label_table = table(feat$label, useNA = "ifany"), pred_table = table(pred$pred),
                  frac_measured = mean(profile$src == "measured"),
                  frac_unbounded = mean(is.infinite(profile$z_hi)),
                  priority = table(risk$segments$priority),
                  priority_by_confidence = table(risk$segments$priority, risk$segments$confidence),
                  n_strike = c(lo = sum(risk$trees$strike_lo), hi = sum(risk$trees$strike_hi)),
                  n_conductor_excluded = rasters$n_conductor_excluded,
                  landsat = if (!is.null(dryness)) attr(dryness$segments, "landsat"),
                  wind = if (!is.null(attr(risk$segments, "wind"))) {
                    w <- attr(risk$segments, "wind")
                    w$dir_from_deg <- NULL  # the hours are in wind_hourly.csv
                    w
                  },
                  dry_grow_in = if (!is.null(dryness)) {
                    c(hi = sum(dryness$segments$dry_grow_in, na.rm = TRUE),
                      lo = sum(dryness$segments$dry_grow_in_lo, na.rm = TRUE))
                  })
  saveRDS(summary, file.path(out, "summary.rds"))

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
