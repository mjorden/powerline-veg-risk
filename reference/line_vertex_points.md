# Line vertices as candidate structure locations

OSM power-line ways are normally drawn with a node at each support
structure, tagged or not.

## Usage

``` r
line_vertex_points(lines)
```

## Arguments

- lines:

  `sf` lines.

## Value

`sf` POINT layer of the lines' vertices.
