# Read the corridor point cloud and normalise heights

Clips one or more LAS/LAZ files to a corridor around `lines`, drops
noise (ASPRS 7, 18), bridge decks (17) and withheld points, and converts
elevations to height above ground using a TIN of the delivered ground
class (2). If the delivery has no ground class, ground is classified
with the cloth simulation filter.

## Usage

``` r
read_corridor(files, lines, half_width_m = 40)
```

## Arguments

- files:

  Paths to `.las`/`.laz` files covering the corridor.

- lines:

  `sf` power lines.

- half_width_m:

  Corridor half-width in metres.

## Value

A height-normalised `LAS` with the original elevation kept in column
`Zref` (lidR convention) and heights in `Z`.
