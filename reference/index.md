# Package index

## Data acquisition

- [`tnm_lidar_tiles()`](https://mjorden.github.io/powerline-veg-risk/reference/tnm_lidar_tiles.md)
  : Find USGS 3DEP LiDAR point-cloud tiles intersecting an area of
  interest
- [`download_tiles()`](https://mjorden.github.io/powerline-veg-risk/reference/download_tiles.md)
  : Download LiDAR tiles, skipping files already present
- [`osm_power_lines()`](https://mjorden.github.io/powerline-veg-risk/reference/osm_power_lines.md)
  : Fetch overhead power lines from OpenStreetMap
- [`osm_power_structures()`](https://mjorden.github.io/powerline-veg-risk/reference/osm_power_structures.md)
  : Fetch power-line support structures (poles, towers) from
  OpenStreetMap
- [`osm_buildings()`](https://mjorden.github.io/powerline-veg-risk/reference/osm_buildings.md)
  : Fetch building footprints from OpenStreetMap

## Corridor point cloud

- [`read_corridor()`](https://mjorden.github.io/powerline-veg-risk/reference/read_corridor.md)
  : Read the corridor point cloud and normalise heights
- [`line_corridor()`](https://mjorden.github.io/powerline-veg-risk/reference/line_corridor.md)
  : Build a corridor polygon around power lines
- [`las_m_per_unit()`](https://mjorden.github.io/powerline-veg-risk/reference/las_m_per_unit.md)
  : Metres per horizontal CRS unit of a LAS object or file header

## Classification

- [`point_features()`](https://mjorden.github.io/powerline-veg-risk/reference/point_features.md)
  : Compute per-point classification features
- [`rule_proxy_features`](https://mjorden.github.io/powerline-veg-risk/reference/rule_proxy_features.md)
  : Features that directly encode the wire-labelling rule
- [`weak_labels()`](https://mjorden.github.io/powerline-veg-risk/reference/weak_labels.md)
  : Assign weak labels to featurised points
- [`assign_blocks()`](https://mjorden.github.io/powerline-veg-risk/reference/assign_blocks.md)
  : Assign points to spatial blocks and CV folds
- [`train_point_classifier()`](https://mjorden.github.io/powerline-veg-risk/reference/train_point_classifier.md)
  : Train a random-forest point classifier
- [`cv_point_classifier()`](https://mjorden.github.io/powerline-veg-risk/reference/cv_point_classifier.md)
  : Cross-validate the point classifier: spatial blocks vs random folds
- [`classify_probs()`](https://mjorden.github.io/powerline-veg-risk/reference/classify_probs.md)
  : Prior-corrected class probabilities
- [`evaluate_vendor_classes()`](https://mjorden.github.io/powerline-veg-risk/reference/evaluate_vendor_classes.md)
  : Score labels against vendor-delivered ASPRS classes
- [`predict_points()`](https://mjorden.github.io/powerline-veg-risk/reference/predict_points.md)
  : Classify all featurised points

## Conductor model and risk

- [`segment_lines()`](https://mjorden.github.io/powerline-veg-risk/reference/segment_lines.md)
  : Split power lines into equal-length segments
- [`line_vertex_points()`](https://mjorden.github.io/powerline-veg-risk/reference/line_vertex_points.md)
  : Line vertices as candidate structure locations
- [`corridor_rasters()`](https://mjorden.github.io/powerline-veg-risk/reference/corridor_rasters.md)
  : Build terrain and vegetation-only canopy height rasters
- [`conductor_profile()`](https://mjorden.github.io/powerline-veg-risk/reference/conductor_profile.md)
  : Model conductor elevation along the line
- [`assess_risk()`](https://mjorden.github.io/powerline-veg-risk/reference/assess_risk.md)
  : Locate trees and score grow-in / fall-in risk per segment

## Canopy greenness and moisture (Landsat)

- [`landsat_scenes()`](https://mjorden.github.io/powerline-veg-risk/reference/landsat_scenes.md)
  : Find Landsat Collection 2 Level-2 scenes over an area of interest
- [`landsat_composite()`](https://mjorden.github.io/powerline-veg-risk/reference/landsat_composite.md)
  : Median dry-season NDVI and NDMI composite from Landsat scenes
- [`canopy_dryness()`](https://mjorden.github.io/powerline-veg-risk/reference/canopy_dryness.md)
  : Dry-season greenness and moisture of grown-in canopy, per segment

## Fire-weather wind

- [`wind_history()`](https://mjorden.github.io/powerline-veg-risk/reference/wind_history.md)
  : Hourly historical wind and humidity for a corridor
- [`fire_wind_hours()`](https://mjorden.github.io/powerline-veg-risk/reference/fire_wind_hours.md)
  : Select dry, high-wind ("fire-weather") hours
- [`wind_fall_exposure()`](https://mjorden.github.io/powerline-veg-risk/reference/wind_fall_exposure.md)
  : Which strike trees the fire-weather winds would throw into the line
- [`nws_forecast()`](https://mjorden.github.io/powerline-veg-risk/reference/nws_forecast.md)
  : Hourly National Weather Service forecast for a corridor
- [`nws_alerts()`](https://mjorden.github.io/powerline-veg-risk/reference/nws_alerts.md)
  : Active NWS watches, warnings and advisories at a corridor
- [`forecast_watchlist()`](https://mjorden.github.io/powerline-veg-risk/reference/forecast_watchlist.md)
  : Segments to watch under the coming fire weather

## Figures

- [`plot_canopy_dryness()`](https://mjorden.github.io/powerline-veg-risk/reference/plot_canopy_dryness.md)
  : Map of dry-season canopy greenness and dry grown-in segments
- [`plot_cross_section()`](https://mjorden.github.io/powerline-veg-risk/reference/plot_cross_section.md)
  : Cross-section of classified points perpendicular to the line
- [`plot_cv()`](https://mjorden.github.io/powerline-veg-risk/reference/plot_cv.md)
  : Cross-validation metrics: spatial-block vs random folds
- [`plot_importance()`](https://mjorden.github.io/powerline-veg-risk/reference/plot_importance.md)
  : Permutation importance of the top features
- [`plot_profile()`](https://mjorden.github.io/powerline-veg-risk/reference/plot_profile.md)
  : Ground and conductor profile along the line
- [`plot_risk_map()`](https://mjorden.github.io/powerline-veg-risk/reference/plot_risk_map.md)
  : Map of canopy height, segment priority, and strike trees
- [`plot_wind_exposure()`](https://mjorden.github.io/powerline-veg-risk/reference/plot_wind_exposure.md)
  : Strike trees the fire-weather winds would throw into the line
