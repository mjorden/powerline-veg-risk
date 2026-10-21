# How the screen works

`vegrisk` takes USGS 3DEP point clouds (LAS/LAZ) and OpenStreetMap
power-line geometry and produces a segment-by-segment screen for the two
vegetation failure modes utilities manage:

- **Grow-in:** canopy growing up into the clearance envelope beneath the
  conductors.
- **Fall-in:** “strike trees” beside the line that are tall enough to
  reach a conductor if they fall.

This article is the long version of the README: what each stage does,
why it is built that way, and where the data come from.

## Pipeline

    3DEP tiles (TNM API) ─┐
                          ├─ clip to corridor ─ height-normalise (TIN on class 2)
    OSM lines (Overpass) ─┘                │
                                           ▼
              per-point features: multi-scale eigenvalue shape (k = 10, 30),
              echo structure, intensity percentile, height
                                           │
              weak labels from GIS + geometry (3DEP has no wire classes)
                                           │
              random forest (ranger), class-weighted, prior-corrected;
              spatially blocked CV vs random CV; feature ablation;
              vendor-class ground truth where it exists
                                           │
              conductor elevation: measured where seen, bounded elsewhere
                                           │
              canopy model from consensus vegetation, conductor returns removed
                                           │
              per 50 m segment: clearance encroachment + 3D strike trees
              under both conductor bounds, with a confidence label
                                           │
              optional: Landsat dry-season greenness of the grown-in canopy;
              fire-weather wind direction against each strike tree

| Step | Function | File |
|----|----|----|
| Find / download 3DEP tiles, fetch OSM layers | [`tnm_lidar_tiles()`](https://mjorden.github.io/powerline-veg-risk/reference/tnm_lidar_tiles.md), [`download_tiles()`](https://mjorden.github.io/powerline-veg-risk/reference/download_tiles.md), [`osm_power_lines()`](https://mjorden.github.io/powerline-veg-risk/reference/osm_power_lines.md), [`osm_power_structures()`](https://mjorden.github.io/powerline-veg-risk/reference/osm_power_structures.md), [`osm_buildings()`](https://mjorden.github.io/powerline-veg-risk/reference/osm_buildings.md) | `R/fetch.R` |
| Corridor clip, noise removal, height normalisation, CRS-unit safety | [`read_corridor()`](https://mjorden.github.io/powerline-veg-risk/reference/read_corridor.md), [`line_corridor()`](https://mjorden.github.io/powerline-veg-risk/reference/line_corridor.md), [`las_m_per_unit()`](https://mjorden.github.io/powerline-veg-risk/reference/las_m_per_unit.md) | `R/preprocess.R` |
| Point features | [`point_features()`](https://mjorden.github.io/powerline-veg-risk/reference/point_features.md) | `R/features.R` |
| Weak labels | [`weak_labels()`](https://mjorden.github.io/powerline-veg-risk/reference/weak_labels.md) | `R/labels.R` |
| Classifier and validation | [`train_point_classifier()`](https://mjorden.github.io/powerline-veg-risk/reference/train_point_classifier.md), [`cv_point_classifier()`](https://mjorden.github.io/powerline-veg-risk/reference/cv_point_classifier.md), [`classify_probs()`](https://mjorden.github.io/powerline-veg-risk/reference/classify_probs.md), [`predict_points()`](https://mjorden.github.io/powerline-veg-risk/reference/predict_points.md), [`evaluate_vendor_classes()`](https://mjorden.github.io/powerline-veg-risk/reference/evaluate_vendor_classes.md) | `R/classify.R` |
| Conductor model and risk | [`conductor_profile()`](https://mjorden.github.io/powerline-veg-risk/reference/conductor_profile.md), [`corridor_rasters()`](https://mjorden.github.io/powerline-veg-risk/reference/corridor_rasters.md), [`assess_risk()`](https://mjorden.github.io/powerline-veg-risk/reference/assess_risk.md) | `R/risk.R` |
| Dry-season canopy greenness and moisture (optional) | [`landsat_scenes()`](https://mjorden.github.io/powerline-veg-risk/reference/landsat_scenes.md), [`landsat_composite()`](https://mjorden.github.io/powerline-veg-risk/reference/landsat_composite.md), [`canopy_dryness()`](https://mjorden.github.io/powerline-veg-risk/reference/canopy_dryness.md) | `R/landsat.R` |
| Fire-weather wind: windward strike trees, forecast watchlist (optional) | [`wind_history()`](https://mjorden.github.io/powerline-veg-risk/reference/wind_history.md), [`fire_wind_hours()`](https://mjorden.github.io/powerline-veg-risk/reference/fire_wind_hours.md), [`wind_fall_exposure()`](https://mjorden.github.io/powerline-veg-risk/reference/wind_fall_exposure.md), [`nws_forecast()`](https://mjorden.github.io/powerline-veg-risk/reference/nws_forecast.md), [`nws_alerts()`](https://mjorden.github.io/powerline-veg-risk/reference/nws_alerts.md), [`forecast_watchlist()`](https://mjorden.github.io/powerline-veg-risk/reference/forecast_watchlist.md) | `R/wind.R` |
| Figures | [`plot_risk_map()`](https://mjorden.github.io/powerline-veg-risk/reference/plot_risk_map.md), [`plot_profile()`](https://mjorden.github.io/powerline-veg-risk/reference/plot_profile.md), [`plot_cross_section()`](https://mjorden.github.io/powerline-veg-risk/reference/plot_cross_section.md), [`plot_cv()`](https://mjorden.github.io/powerline-veg-risk/reference/plot_cv.md), [`plot_importance()`](https://mjorden.github.io/powerline-veg-risk/reference/plot_importance.md), [`plot_canopy_dryness()`](https://mjorden.github.io/powerline-veg-risk/reference/plot_canopy_dryness.md), [`plot_wind_exposure()`](https://mjorden.github.io/powerline-veg-risk/reference/plot_wind_exposure.md) | `R/plot.R` |
| Case studies | `run_case_study(cfg)` + one config script per site | `analysis/` |

## Design decisions

**Distances are always metres.** Point clouds stay in their native CRS,
and every parameter is converted with
[`las_m_per_unit()`](https://mjorden.github.io/powerline-veg-risk/reference/las_m_per_unit.md).
The Nashville tiles are in US survey feet; without the conversion every
buffer would silently shrink 3.28×. Geographic CRSs are rejected. The
features table records the CRS it was built in, and the labelling and
blocking steps refuse a different one.

**Labels are weak, and the code says so.** No public 3DEP project labels
power lines (see the [limits
article](https://mjorden.github.io/powerline-veg-risk/articles/limits-and-roadmap.md)),
so training labels come from GIS layers and geometry:

- **building:** OSM footprints, shrunk 1 m inward so crowns overhanging
  eaves don’t count as roof.
- **structure:** OSM pole and tower nodes.
- **wire:** an air-gap test (an elevated layer with empty space beneath
  it across a 3×3 m window) plus an **along-line run test** in
  chainage/offset coordinates: each conductor row must extend ≥ 12 m
  along *any* mapped line in the area, so second circuits on a shared
  right-of-way are labelled too. Crown tops are compact and fail.
- **vegetation:** everything else.

Elevated suspended candidates that fail the wire test, or that lie
beyond `wire_search_m` of any mapped line, **abstain** (NA) rather than
becoming “vegetation”, so missed and unmapped conductors aren’t taught
as trees. The mapped lines include OSM `power=minor_line` (distribution)
as well as `power=line`.

**Predictors are an allow-list.**
[`point_features()`](https://mjorden.github.io/powerline-veg-risk/reference/point_features.md)
records which columns are features; a joined column or a previous
model’s predictions can never become a predictor by accident.

**Validation is spatial, and the gap is reported.** Folds are 100 m
spatial blocks, numbered by position so the folds do not depend on the
order the tiles were read; random folds are reported alongside.
Precision is measured at real class prevalence, and the headline metric
is average precision against its no-skill value. An ablation drops the
features that most directly encode the labelling rule (height and echo
structure). The multi-scale shape features are kept in the ablation, and
they too partly stand in for the air-gap and run tests, so the ablation
shows how much the model leans on the most direct proxies, not that it
has learned something independent of the rules.

**Class weighting is undone at prediction time.** The forest trains with
inverse-frequency case weights, i.e. under equal priors;
[`classify_probs()`](https://mjorden.github.io/powerline-veg-risk/reference/classify_probs.md)
multiplies by the true prevalence and renormalises. Without that, the
Colorado model called about 25,000 vegetation points “wire”.

**Conductor elevation is bounded, not guessed.**
[`conductor_profile()`](https://mjorden.github.io/powerline-veg-risk/reference/conductor_profile.md)
uses classified conductor returns where they pass sanity checks: more
than one mask radius from a structure (guy wires and crossarms are
linear too), a robust low quantile per 5 m bin, above the code minimum,
and at a plausible slope to neighbouring bins. Elsewhere it brackets the
conductor:

- **lower bound:** ground + NESC minimum clearance.
- **upper bound:** the chord between the supports either side, at
  ground + a maximum attachment height. A conductor sags below the chord
  between its attachments. Where the next support lies outside the data,
  the upper bound is reported as unknown.

Every risk metric is computed under both bounds, and each segment is
labelled `measured`, `robust` (same answer under both bounds) or
`bound-dependent`.

**Conductor returns are removed from the canopy model, but trees are
not.** Conductors that cross canopy aren’t “suspended”, so the rules
label them vegetation, and they would put “trees” at wire height under
the whole line.
[`corridor_rasters()`](https://mjorden.github.io/powerline-veg-risk/reference/corridor_rasters.md)
removes points inside the conductor envelope at or above the measured
conductor elevation only if they are wire-like:

- locally linear, or
- suspended: nothing in the 1.5 m layer just beneath the conductor band
  across a 3×3 m neighbourhood. Bundled 500 kV conductors form ribbons
  rather than lines, so this second test matters.

A crown that reaches wire height has foliage beneath it and stays, so it
is still flagged. The envelope comes from where conductor returns
actually are and is capped at the grow-in zone, so tall trees beside the
line keep their tops for the fall-in test. Cells emptied by the removal
are treated as unobserved, not bare ground.

**Unseen is not clear.** A cell with no canopy counts as bare ground
only if the LiDAR saw it. Two kinds of cell are unobserved instead:

- cells whose only above-ground returns were left out of the canopy
  model as uncertain: the unlabelled margins beside wires, structures
  and buildings, abstained near-line candidates, points the classifier
  and rules disagree on, and conductor-envelope removals;
- voids with no return of any class within 5 m, such as a missing tile,
  water or a dropout. The TIN terrain model bridges these, so without
  the check they would read as bare ground.

Each segment reports `frac_observed` (across the corridor) and
`frac_observed_under` (the grow-in zone). A segment that would be `none`
but has less than 75% of either observed is tiered `no data` (confidence
`low coverage` when that holds under both bounds), and the risk map
draws those grey and dotted. The pipeline also stops if a configured
tile is missing from The National Map.

**Fall-in uses 3D geometry and terrain.** A tree pivoting at its base
sweeps a sphere of radius *h*. It can strike if the 3D distance from its
base to the nearest point of the conductor (DTM at the tree, modelled
conductor elevation, measured outer-phase offset) is ≤ *h*. “Nearest” is
the minimum over every conductor vertex within the tree’s reach, not the
vertex at the tree’s own station: on a sloping or sagging span the
conductor a few metres along the line is often closer. Trees inside the
grow-in zone count as grow-in, not strike.

**Structures are masked.** Towers, H-frames and crossarms otherwise look
like tall trees under the conductors. Cells within a structure-sized
radius of OSM structure nodes and line vertices (for every circuit in
the corridor) are masked (known structures: not scored, but not counted
as data gaps), and features one or two cells wide are removed with a 3×3
crown-support filter.

**LiDAR says where canopy has grown in; Landsat says how green and wet
it is.** The grow-in screen ranks canopy by its distance to the
conductor, not by how readily it would carry fire to the line. An
optional Landsat step adds that:

- **Data:** Landsat 8/9 Collection 2 Level-2 surface reflectance, from
  the Microsoft Planetary Computer STAC API (no key needed). Only the
  corridor window of each cloud-optimised GeoTIFF is read.
- **Composite:** a per-pixel median over every clear dry-season
  observation in the chosen years. `QA_PIXEL` masks fill, cloud, dilated
  cloud, cirrus, shadow, snow and water. Water is masked because its
  negative NDVI would read as very dry canopy. Two indices come out:
  **NDVI** (greenness) and **NDMI** (NIR against SWIR1: canopy water
  content, the closer of the two to fuel moisture). Every scene offered
  is logged with whether it was used and why not, and a composite that
  lost scenes to read errors is not cached.
- **LiDAR picks the pixels.** A 30 m pixel is wider than many
  rights-of-way, so most pixels mix trees with cleared ground. Each
  pixel gets a canopy fraction from the 1 m CHM, and pixels under 50%
  canopy, less than 80% observed by the LiDAR, or with fewer than three
  clear looks are not scored. A segment’s value is the mean of its
  pixels, weighted by how many of the segment’s canopy cells *inside the
  grow-in zone* fall in each one. It describes the trees under the
  wires, not the forest beside them.
- **Relative, not absolute.** Neither index has a fire-danger threshold.
  Each segment is ranked against every scored canopy pixel in the
  corridor, and `dry_canopy` marks the lowest quarter. `dry_grow_in` is
  dry *and* grown in under the optimistic conductor bound;
  `dry_grow_in_lo` uses the pessimistic tier.

**Weather can’t tell segments apart, but wind direction can.**
Fire-weather grids are 2.5–25 km wide, so every segment of a short line
gets the same wind. The spatial signal comes from combining wind
*direction* with where each strike tree stands. Windthrown trees fall
roughly downwind, so a tree on the upwind side of the line in dry,
high-wind hours matters more than the same tree on the downwind side.

- **Fire-weather hours:** ten years of hourly ERA5 reanalysis
  (Open-Meteo, no key). Hours count as fire weather when gusts are in
  the record’s top 5% and relative humidity is ≤ 30%.
- **Hitting arc, from the existing reach test.** A tree of height *h*,
  with its base a horizontal distance *d* from the outer phase and the
  conductor *dz* above its base at the vertex it reaches, reaches
  horizontally *R* = √(*h*² − *dz*²) at conductor height. It hits if it
  falls within acos(*d*/*R*) of straight at the line. There is no
  arbitrary angle cutoff, apart from a ±15° allowance for the scatter of
  real fall directions.
- **Per tree:** the share of fire-weather hours whose wind would throw
  it into that arc (`wind_hit_lo` / `wind_hit_hi`). **Per segment:** the
  windward strike-tree count, and the *wind-weighted strike-tree count*
  (the sum of those shares: how many trees the winds of a typical
  fire-weather hour would throw towards the line *if they fell*; no
  failure probability is involved). Wind directions are rotated from
  true to grid north first.
- **Forecast watchlist:** `analysis/watchlist.R` applies the same
  thresholds and geometry to the live NWS 7-day hourly forecast and
  active Red Flag Warnings. It lists the segments whose strike trees the
  coming winds would throw, plus dry grown-in segments, and when.

## Reproduce

``` r

# R >= 4.3
install.packages(c("lidR", "sf", "terra", "lwgeom", "ranger", "FNN", "data.table",
                   "httr2", "units", "withr", "ggplot2", "scales", "patchwork", "devtools"))
```

``` bash
Rscript analysis/run_sunshine_canyon.R   # ~0.6 GB of 3DEP LiDAR on first run
Rscript analysis/run_nashville.R         # ~0.3 GB; uses the Colorado model for the transfer test
Rscript analysis/watchlist.R sunshine    # live NWS forecast against a finished run (needs `wind` in the config)
Rscript -e 'devtools::test()'           # unit tests: synthetic geometry + lidR example data, no network
```

Cross-validation is the slow part (minutes on mains power, much longer
on battery). Set `VEGRISK_REUSE=1` to reuse a site’s saved model and
validation results and recompute only labels and risk; the reuse is
recorded in `summary.rds` (`run$reused_from`), and the model and its
cross-validation are stored together so a rerun can never pair one run’s
model with another’s metrics. The OSM layers used are cached in
`data-raw/<site>/*.geojson` with the OSM snapshot time, so reruns are
reproducible even if OSM changes. Outputs go to `output/<site>/`:
`segments.gpkg`, `trees.gpkg`, `segments.csv`, `conductor_profile.csv`,
`cv_metrics.csv`, `cv_summary.csv`, `summary.rds`. A site config with
`landsat = list(years, months)` also writes `landsat_composite.tif` and
`landsat_scenes.csv`; `wind = list(start, end)` writes and reuses
`wind_hourly.csv`; the watchlist writes `watchlist.csv`.

## Data

- **LiDAR:** U.S. Geological Survey 3D Elevation Program, public domain:
  `CO_DRCOG_2020_B20` tiles `w0472n4429`, `w0472n4430`;
  `TN_DavidsonCounty_D22` tiles `155020`, `155060`, `155100`, `155140`,
  `169020`.
- **Power lines, structures, buildings:** © OpenStreetMap contributors,
  ODbL.
- **Landsat:** U.S. Geological Survey Landsat 8–9 Collection 2 Level-2
  surface reflectance, public domain, accessed through the Microsoft
  Planetary Computer.
- **Historical wind:** Copernicus ERA5 reanalysis via the
  [Open-Meteo](https://open-meteo.com/) historical weather API, CC BY
  4.0.
- **Forecasts and alerts:** U.S. National Weather Service API
  (api.weather.gov), public domain.
