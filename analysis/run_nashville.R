# Case study 2: TVA Maury–Davidson 500 kV line, west Nashville, Davidson
# County, Tennessee. Steel lattice towers, bundled conductors, a managed
# right-of-way through wooded hills. 2 km window starting 1.5 km south of
# the Davidson substation.
#
#   Rscript analysis/run_nashville.R
#
# Downloads ~0.3 GB of USGS 3DEP LiDAR (TN_DavidsonCounty_D22, Tennessee
# State Plane, US survey feet - exercises the unit handling) on first run.
# This delivery classifies vegetation (3-5) and buildings (6), which are used
# as independent ground truth for the classifier.

source("analysis/pipeline.R")

run_case_study(list(
  id = "nashville",
  source = "USGS 3DEP 2022 LiDAR (TN_DavidsonCounty_D22)",
  title = "Vegetation risk along the TVA Maury\u2013Davidson 500 kV line",
  line_ids = "19556523",               # OSM way "Maury - Davidson", 500 kV
  window_m = c(1500, 3500),            # chainage from the Davidson (north) end
  start_north = TRUE,
  project = "TN_DavidsonCounty_D22",
  tiles = sprintf("USGS_LPC_TN_DavidsonCounty_D22_%s.laz",
                  c("155020", "155060", "155100", "155140", "169020")),
  half_width_m = 60,                   # ~27 m half right-of-way + strike zone
  wire_search_m = 20,                  # outer phases ~10-12 m off centreline
  phase_offset_m = 11,
  under_line_m = 21,                   # outer-phase returns reach ~19 m off centreline
  wire_zone_m = 25,
  structure_mask_m = 18,               # lattice tower base + arms
  min_ground_clear_m = 8.5,            # NESC 232-1 order of magnitude for 500 kV
  attach_m = 45,                       # upper limit on lattice attachment height
  section_m = 1000,
  vendor_classes = TRUE,
  transfer_from = "sunshine"           # score the Colorado model here
))
