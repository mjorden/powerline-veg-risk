# vegrisk: LiDAR Vegetation Encroachment and Fall-In Risk for Power Line Corridors

Builds a vegetation-risk screen for overhead power lines from public
data: USGS 3DEP airborne LiDAR (LAS/LAZ) and OpenStreetMap
transmission-line geometry. Clips the point cloud to a line corridor,
height-normalises it, trains a random-forest point classifier on local
geometric (eigenvalue) features with spatially blocked cross-validation,
and summarises grow-in and fall-in ("strike tree") risk per line
segment.

## Author

**Maintainer**: Matt Jorden <matthew.jorden@gmail.com>
