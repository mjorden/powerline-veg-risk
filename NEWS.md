# vegrisk (development version)

- Fall-in is tested over the whole conductor bracket, not only at its two bounds: trees carry `reach_min_m`, `strike_possible` and `strike_certain`, and the pessimistic / optimistic tiers use those (#49).
- Grow-in clearance is radial (horizontal beyond the phase offset, vertical up to the conductor); `assess_risk()` refuses an `under_line_m` narrower than `phase_offset_m + clearance_target_m` and its default is 8 m (#50).
- `line_supports()` keeps only line vertices that a tagged structure confirms for the upper conductor bound; `conductor_profile()` counts measured bins above the support chord; `taut_upper()` reports an unknown bound past the outermost straddling chord (#51).

# vegrisk 0.1.0

First and closing release of a portfolio project: a segment-by-segment vegetation-risk screen for overhead power lines from public data.

## What it does

- **Inputs:** USGS 3DEP LiDAR tiles (The National Map API) and OpenStreetMap line, structure and building geometry (Overpass), with cached, provenance-stamped OSM layers.
- **Corridor point cloud:** clip, noise and bridge removal, TIN height normalisation; every distance in metres whatever the CRS, including US survey feet deliveries.
- **Point classification:** multi-scale eigenvalue, echo, intensity and height features; weak labels from GIS and geometry (air-gap and along-line run tests for wire, with abstention for unmapped conductors); a class-weighted, prior-corrected random forest; spatially blocked cross-validation reported against random folds; a rule-proxy ablation; scoring against vendor ASPRS classes where a delivery has them.
- **Conductor model:** elevation measured from classified returns where the LiDAR saw the wires, bracketed between the code-minimum clearance and the chord between supports elsewhere; every metric computed under both bounds with a confidence label.
- **Risk:** canopy height model from consensus vegetation with conductor returns removed; clearance encroachment per segment; strike trees by minimum 3D reach from base to conductor; unobserved ground never read as clear.
- **Optional layers:** Landsat Collection 2 dry-season NDVI / NDMI of the grown-in canopy (Planetary Computer STAC); ERA5 fire-weather winds (Open-Meteo) turned into a windward strike-tree count per segment; an NWS forecast and Red Flag Warning watchlist.
- **Figures:** risk map, conductor profile, cross-section, cross-validation, importance, canopy dryness and wind exposure, in a mid-century earth-tone style by default.
- **Reproducibility:** run ids, atomic model and summary files, a recorded reuse path, a Landsat scene log, stable tree ids and OSM identity on segments.

## Case studies

- Sunshine Canyon, Colorado (115 kV, conductor barely sampled): 3 robust grow-in candidates, 27 bound-dependent segments.
- West Nashville, Tennessee (500 kV, conductor measured end to end): no grow-in, 24 strike trees in 7 segments, 32 segments seen to be clear; vendor vegetation classes shown to contain the conductors.

See the pkgdown articles for methods, both case studies, and the limits and roadmap.
