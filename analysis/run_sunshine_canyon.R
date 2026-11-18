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
  osm_date = "2026-10-19T14:01:07Z",   # OSM snapshot the cached layers come from (attic query, #56)
  project = "CO_DRCOG_2020",
  tiles = sprintf("USGS_LPC_CO_DRCOG_2020_B20_%s.laz", c("w0472n4429", "w0472n4430")),
  half_width_m = 45,
  wire_search_m = 12,
  phase_offset_m = 5.5,                # outer phases, from conductor-return offsets
  under_line_m = 14,                   # >= phase offset + clearance target (#50); covers the 13.5 m conductor spread (#60)
  wire_zone_m = 15,
  structure_mask_m = 8,                # H-frame width
  min_ground_clear_m = 4.9,            # NESC 232-1, 115 kV, pedestrian-only land
  attach_m = 20,                       # upper limit on wood H-frame attachment height
  section_m = 100,                     # cross-section where phases cross trees
  vendor_classes = FALSE,              # delivery has no vegetation/building classes
  # Dry-season Landsat 8/9 composite bracketing the 2020 LiDAR flight.
  landsat = list(years = 2019:2021, months = 7:9, dry_index = "ndvi"),
  # Eight years of hourly ECMWF IFS wind (9 km), one product throughout;
  # fire weather = top-5% gusts at RH <= 30%. The record once began in 2015
  # with the archive's default product, which turned out to be ERA5 (25 km)
  # for 2015-2016 and IFS from 2017, so its gust percentile mixed the two
  # (#64). ERA5 alone covers more years but flattens the Front Range
  # downslope windstorms: its 95th-percentile gust here is 10.5 m/s against
  # 17 m/s in IFS.
  wind = list(start = "2017-01-01", end = "2024-12-31", model = "ecmwf_ifs", gust_quantile = 0.95, max_rh = 30)
))
