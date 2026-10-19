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

## Figures

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
