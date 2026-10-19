# Active NWS watches, warnings and advisories at a corridor

Active NWS watches, warnings and advisories at a corridor

## Usage

``` r
nws_alerts(aoi, api = nws_api)
```

## Arguments

- aoi:

  An `sf`/`sfc` object (any CRS) or a `bbox`.

- api:

  NWS API root.

## Value

A tibble: `event` (e.g. `"Red Flag Warning"`), `onset`, `ends`,
`headline`. Zero rows when nothing is active.
