# End-to-end case study: Sunshine–Boulder Hydro 115 kV line, Sunshine
# Canyon, Boulder County, Colorado (wildland–urban interface; the 2010
# Fourmile Canyon Fire burned ~2.5 km to the north-west).
#
#   Rscript analysis/run_sunshine_canyon.R
#
# Downloads ~0.6 GB of USGS 3DEP LiDAR (CO_DRCOG_2020) on first run.

devtools::load_all(quiet = TRUE)
suppressPackageStartupMessages({
  library(sf)
  library(data.table)
})
dir.create("output", showWarnings = FALSE)
dir.create("man/figures", showWarnings = FALSE, recursive = TRUE)
t0 <- Sys.time()
step <- function(...) message(sprintf("[%5.0fs] ", as.numeric(Sys.time() - t0, units = "secs")), ...)

# --- 1. Inputs --------------------------------------------------------------
line_ids <- "1381464850" # OSM way: "Sunshine to Boulder Hydro", 115 kV
cache <- function(path, expr) {
  if (file.exists(path)) return(st_read(path, quiet = TRUE))
  x <- expr
  st_write(x, path, quiet = TRUE)
  x
}
lines <- cache("data-raw/osm_line.geojson", osm_power_lines(ids = line_ids))

tile_ids <- c("w0472n4429", "w0472n4430") # ~1.5 km of the line
files <- file.path("data-raw/laz", sprintf("USGS_LPC_CO_DRCOG_2020_B20_%s.laz", tile_ids))
if (!all(file.exists(files))) { # query The National Map only when tiles are missing
  tiles <- tnm_lidar_tiles(st_buffer(st_transform(lines, 26913), 50), project = "CO_DRCOG_2020")
  files <- download_tiles(tiles[grepl(paste(tile_ids, collapse = "|"), tiles$title), ])
}

ctg_crs <- st_crs(lidR::readLASheader(files[1]))
extent <- st_as_sfc(st_bbox(lidR::readLAScatalog(files, progress = FALSE)))
st_crs(extent) <- ctg_crs
lines_utm <- st_intersection(st_transform(lines, ctg_crs), st_buffer(extent, -60))
aoi <- st_buffer(lines_utm, 100)
structures <- cache("data-raw/osm_structures.geojson", osm_power_structures(aoi))
buildings  <- cache("data-raw/osm_buildings.geojson", osm_buildings(aoi))
step("line length in study area: ", round(sum(st_length(lines_utm))), " m; ",
     nrow(structures), " mapped structures; ", nrow(buildings), " buildings")

# --- 2. Corridor point cloud --------------------------------------------------
las <- read_corridor(files, lines_utm, half_width_m = 45)
step("corridor points: ", format(lidR::npoints(las), big.mark = ","))

# --- 3. Features, weak labels, classifier ------------------------------------
feat <- point_features(las)
feat <- weak_labels(feat, ctg_crs, lines_utm, structures, buildings)
feat <- assign_blocks(feat, ctg_crs, block_m = 100, n_folds = 5)
step("featurised ", format(nrow(feat), big.mark = ","), " above-ground points; weak labels:")
print(table(feat$label, useNA = "ifany"))

print(cv_fold <- table(fold = feat$fold, label = feat$label))

cv <- cv_point_classifier(feat)
ablation <- cv_point_classifier(feat, drop_features = rule_proxy_features)
ablation$metrics <- ablation$metrics[ablation$metrics$scheme == "spatial_block", ]
ablation$metrics$scheme <- "spatial_ablation"
metrics <- rbind(cv$metrics, ablation$metrics)
step("cross-validation done")
print(metrics, digits = 3)
print(cv$confusion)
fwrite(metrics, "output/cv_metrics.csv")

model <- train_point_classifier(feat)
pred <- predict_points(model, feat)
step("classified points:")
print(table(predicted = pred$pred, weak_label = pred$label, useNA = "ifany"))

# QA: how far are LiDAR-detected wires from the OSM centreline?
m <- las_m_per_unit(las)
w <- pred[pred == "wire"]
osm_offset <- m * as.numeric(st_distance(st_as_sf(w[, .(X, Y)], coords = c("X", "Y"), crs = ctg_crs),
                                         st_union(lines_utm)))
step(sprintf("wire-point offset from OSM centreline: median %.1f m, 95th pct %.1f m",
             median(osm_offset), quantile(osm_offset, 0.95)))
print(quantile(osm_offset, c(0.1, 0.25, 0.5, 0.75, 0.9)), digits = 2)

# --- 4. Risk -------------------------------------------------------------------
segments <- segment_lines(lines_utm, ctg_crs, seg_m = 50)
rasters <- corridor_rasters(las, pred, res_m = 1)
# Structures: tagged OSM poles/towers plus the line's vertices (OSM mappers
# put a node at each structure; on this line they coincide with the H-frames
# visible in the point cloud). Vertices come from the *unclipped* line - the
# clip to the study area adds end points that are not structures; supports
# outside the data are dropped inside conductor_profile(). Outer phases sit
# ~5.5 m either side of the centreline (measured from conductor returns).
supports <- st_sf(geometry = c(st_geometry(st_transform(structures, ctg_crs)),
                               st_geometry(line_vertex_points(st_transform(lines, ctg_crs)))))
profile <- conductor_profile(pred, segments, rasters$dtm, supports = supports)
step(sprintf("conductor measured along %.0f%% of the line; upper bound unknown along %.0f%%",
             100 * mean(profile$src == "measured"), 100 * mean(is.infinite(profile$z_hi))))
risk <- assess_risk(rasters, profile, segments, phase_offset_m = 5.5, structures = supports)
step("risk assessed")
print(table(optimistic = risk$segments$priority, pessimistic = risk$segments$priority_lo))
print(table(risk$segments$confidence))
print(st_drop_geometry(risk$segments)[1:10, ], digits = 3)

st_write(risk$segments, "output/segments.gpkg", delete_dsn = TRUE, quiet = TRUE)
st_write(risk$trees, "output/trees.gpkg", delete_dsn = TRUE, quiet = TRUE)
fwrite(st_drop_geometry(risk$segments), "output/segments.csv")
fwrite(profile, "output/conductor_profile.csv")
saveRDS(list(metrics = metrics, confusion = cv$confusion, fold_counts = cv$fold_counts,
             importance = model$variable.importance, osm_offset = osm_offset,
             label_table = table(feat$label, useNA = "ifany"),
             pred_table = table(pred$pred)),
        "output/model_summary.rds")

# --- 5. Figures ------------------------------------------------------------------
plot_risk_map(rasters, risk, supports,
              title = "Vegetation risk along the Sunshine\u2013Boulder Hydro 115 kV line",
              file = "man/figures/risk_map.png")
plot_profile(profile, risk, "man/figures/conductor_profile.png")
# Section ~100 m along the line, where the three phases cross over trees.
plot_cross_section(las, pred, lines_utm, "man/figures/cross_section.png",
                   at = 100 / as.numeric(sum(st_length(lines_utm))))
plot_cv(metrics, "man/figures/cv_metrics.png")
plot_importance(model, "man/figures/importance.png")
step("done")
