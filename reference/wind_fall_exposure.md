# Which strike trees the fire-weather winds would throw into the line

For each potential strike tree from
[`assess_risk()`](https://mjorden.github.io/powerline-veg-risk/reference/assess_risk.md),
works out the arc of fall directions that reach a conductor, then the
share of fire-weather hours whose wind would push the tree into that
arc.

## Usage

``` r
wind_fall_exposure(
  risk,
  profile,
  wind_hours,
  phase_offset_m = 3,
  growth_m = 0,
  spread_deg = 15,
  windward_min = 0.5,
  min_hours = 24
)
```

## Arguments

- risk:

  Output of
  [`assess_risk()`](https://mjorden.github.io/powerline-veg-risk/reference/assess_risk.md).

- profile:

  Output of
  [`conductor_profile()`](https://mjorden.github.io/powerline-veg-risk/reference/conductor_profile.md)
  (line geometry).

- wind_hours:

  Output of
  [`fire_wind_hours()`](https://mjorden.github.io/powerline-veg-risk/reference/fire_wind_hours.md).

- phase_offset_m, growth_m:

  As used in
  [`assess_risk()`](https://mjorden.github.io/powerline-veg-risk/reference/assess_risk.md).

- spread_deg:

  Allowance (degrees, each side) for fall directions that deviate from
  the wind direction.

- windward_min:

  Share of fire-weather hours at or above which a strike tree counts as
  *windward* of the line.

- min_hours:

  Fewer fire-weather hours than this gives a warning: the hit shares
  then rest on a handful of hours. With none at all, every wind column
  is `NA`, not zero.

## Value

`risk` with added tree columns `bearing_deg` (grid bearing from the tree
to the line), `arc_lo_deg`, `arc_hi_deg` (half-width of the hitting arc
under each conductor bound; `NA` when it cannot reach), `wind_hit_lo`,
`wind_hit_hi` (share of fire-weather hours that would throw it into the
line), and segment columns `wind_strike_lo`, `wind_strike_hi` (the
wind-weighted strike-tree count: the sum of `wind_hit_*` over strike
trees, i.e. how many trees the winds of a typical fire-weather hour
would throw towards the line *if* they fell; no failure probability is
involved), `n_strike_windward_lo`, `n_strike_windward_hi` and
`n_fire_weather_hours` (so the hour count survives `st_write()`). The
fire-wind summary is stored in `attr(risk$segments, "wind")`.

## Details

A tree of height `h` whose base is a horizontal distance `d` from the
outer phase, with the conductor `dz` above its base, reaches the
conductor horizontally out to `R = sqrt(h^2 - dz^2)`. It hits if it
falls within `acos(d / R)` of the direction straight at the line, the
same 3D test as the fall-in screen, resolved by direction. Windthrown
trees fall roughly downwind, so a fire-weather hour counts against the
tree when the direction the wind blows *towards* lies inside that arc,
widened by `spread_deg` on each side for the scatter of real fall
directions.

Wind directions are rotated from true north to grid north (meridian
convergence at the corridor) before they are compared with tree
bearings.
