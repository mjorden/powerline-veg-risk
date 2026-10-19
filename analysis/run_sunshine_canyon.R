# Case study 1: Sunshine–Boulder Hydro 115 kV line, Sunshine Canyon, Boulder
# County, Colorado (wildland–urban interface; the 2010 Fourmile Canyon Fire
# burned ~2.5 km to the north-west). Wood H-frames on long canyon spans.
#
#   Rscript analysis/run_sunshine_canyon.R
#
# Downloads ~0.6 GB of USGS 3DEP LiDAR (CO_DRCOG_2020, UTM 13N metres) on
# first run.

source("analysis/pipeline.R")

run_case_study(list(
  id = "sunshine",
  source = "USGS 3DEP 2020 LiDAR (CO_DRCOG_2020)",
  title = "Vegetation risk along the Sunshine\u2013Boulder Hydro 115 kV line",
  line_ids = "1381464850",             # OSM way "Sunshine to Boulder Hydro"
  project = "CO_DRCOG_2020",
  tiles = sprintf("USGS_LPC_CO_DRCOG_2020_B20_%s.laz", c("w0472n4429", "w0472n4430")),
  half_width_m = 45,
  wire_search_m = 12,
  phase_offset_m = 5.5,                # outer phases, from conductor-return offsets
  under_line_m = 6,
  wire_zone_m = 10,
  structure_mask_m = 8,                # H-frame width
  min_ground_clear_m = 4.9,            # NESC 232-1, 115 kV, pedestrian-only land
  attach_m = 20,                       # upper limit on wood H-frame attachment height
  section_m = 100,                     # cross-section where phases cross trees
  vendor_classes = FALSE,              # delivery has no vegetation/building classes
  # Dry-season Landsat 8/9 composite bracketing the 2020 LiDAR flight.
  landsat = list(years = 2019:2021, months = 7:9, dry_index = "ndvi")
))
