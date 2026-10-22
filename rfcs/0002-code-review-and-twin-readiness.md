# RFC 0002: Code review and digital-twin readiness, October 2026

| | |
|---|---|
| **Status** | Review complete; findings filed as #49 to #71 |
| **Author** | Matt Jorden (review run with four parallel reviewer lenses plus a regulatory research pass) |
| **Reviewed** | `main` at ef0382e (after PRs #44 to #47) |
| **Companion** | RFC 0001 (the twin), revised the same day; the roadmap in `vignettes/articles/limits-and-roadmap.Rmd` |

## Summary

`vegrisk` was closed out as a portfolio project with a clean tracker. This review asks a different question: what would it take to make it the vegetation layer of a wildfire-risk digital twin for a Colorado utility, as RFC 0001 proposes. Four reviewers read the whole codebase, each with one lens (scientific correctness, engineering and scale, reproducibility and operations, twin readiness), and a research pass established the Colorado regulatory and data context as of October 2026. Every finding below was verified against the code; the two that change published results were re-run by hand.

The short answer: **the science core is the right shape and most of it is sound** (unit-safe distances, lower and upper conductor bounds carried through every metric, "unseen is not clear", minimum 3D reach, spatial cross-validation, scene logs). **Everything around it is shaped as a one-off study**: no stable identity across runs, no time axis, no span or structure entity, one short line held in memory, caches keyed by file name, and a run record that cannot reproduce a run. Three scientific findings also need fixing before the outputs can be called a span's clearance state: the strike test only at the two bounds, vertical-only clearance in a fixed band, and an unfiltered support set behind the upper bound.

The Colorado context raises the stakes. The Public Utilities Commission opened rulemaking 26R-0355E in September 2026 to require Wildfire Mitigation Plans from Xcel and Black Hills every three years, with likelihood-and-consequence assessments tied to utility equipment and an independent check. A vegetation layer that cannot say which run, which inputs and which parameters produced a span's tier will not survive that check.

## Part 1: Findings

Severity: **high** = a wrong answer is plausible on real data or the twin cannot be built on it; **medium** = wrong under realistic conditions; **low** = defensive. Effort: S < 1 day, M < 1 week, L more. "Phase" is the RFC 0001 phase the finding blocks.

### A. Scientific correctness

| # | Finding | Severity | Where | Effort | Phase |
|---|---|---|---|---|---|
| A1 | **Fall-in is tested only at the two conductor bounds.** Reach is convex in conductor elevation with its minimum at the tree's base elevation, so a tree whose base lies between `z_lo` and `z_hi` can strike at an elevation inside the bracket while striking at neither bound. Verified: base 20 m above line ground, 17 m from the outer phase, bracket [5, 40], height 18: reach 22.7 at the lower bound, 26.2 at the upper, 17.0 at 20 m. The segment reads `robust none` when it is bound-dependent. Canyon spans are where this applies; on Sunshine about 5 more possible strike trees in 4 segments (segments already grow-in under the lower bound, so no published tier changes). | high | `R/risk.R` trees block and `min_reach()` | S | 1, 2 |
| A2 | **Grow-in clearance is vertical only, inside a fixed band.** Clearance is `z_lo - (ground + h)` for cells with `dh <= under_line_m`; at Sunshine that band ends 0.5 m beyond the outer phase. A crown 1.5 m outside the outer phase with its top at conductor height is neither in the band nor a strike tree (reach > h). That is the classic side-growth and blow-in contact, and the standards (MVCD, utility clearances) are radial. | high | `R/risk.R` cells block | M | 1, 2 |
| A3 | **Any OSM pole or tower within `search_m`, and every vertex of the study way, is a support at ground + `attach_m`.** A distribution tap pole or a mapper's bend vertex near mid-span over a gully puts the "upper bound" chord below where the conductor can be. Nothing checks that measured bins fall inside the bracket, which would test the support set for free. `taut_upper()` returns a finite value at line ends where `support_chord()` returns `Inf`. | medium-high | `analysis/pipeline.R` supports, `R/risk.R` bounds | S-M | 1, 2 |
| A4 | **Per-point disagreement exclusion leaves a cell observed at a lower canopy height.** A crown top the classifier calls wire while the rules call vegetation drops out; the cell's lower consensus returns set the CHM, so the cell counts as observed with an overstated clearance. The points most likely to look wire-like are the tops reaching toward the conductor. | medium-high | `R/risk.R` corridor_rasters | S | 1 |
| A5 | **Structure-masked area counts as observed and is never reported, and the mask includes every vertex of every context line.** With `minor_line` ways digitised along roads, 8 m discs hide long strips while `frac_observed` stays near 1. | medium | `R/risk.R` assess_risk, pipeline `mask_supports` | S | 1 |
| A6 | **The published Sunshine run fired its own envelope warning.** `envelope_needed` is 13.5 m against `under_line_m = 6`; conductor returns over canopy between 6 and 13.5 m from the centreline stay in the canopy model. The case study does not say so. | medium | `output/sunshine/summary.rds`, `analysis/run_sunshine_canyon.R` | S | 1 |
| A7 | **A joint-use distribution line breaks the wire rule.** Comm cable at 5 to 6 m and neutral at 7 m under primaries at 9 to 11 m fail `wire_min_m = 6` and `layer_m = 4`; they are not candidates, so they do not abstain: they become vegetation labels and canopy. The floor check also rejects measured bins below 4.9 m although the NESC minimum for neutral and communication conductors is lower. | medium-high | `R/labels.R`, `R/risk.R` | M | 1 |
| A8 | **The crown-support filter keeps 2-cell-wide features and erodes narrow crowns**, contrary to its documentation; with `min_encroach_m2 = 5` a single narrow conifer 1 m under the wire can fall below the grow-in threshold. | medium | `R/risk.R` min_support | S-M | 1 |
| A9 | **Colorado spatial CV for wire rests on one fold**: 76% of wire points are in fold 5 and none in fold 4; AP is pooled across five differently calibrated models. "0.20 vs 0.005" and "the large gaps are robust" rest on one held-out block group. | medium | `R/classify.R` cv, `summary.rds$fold_counts` | S | 1, 4 |
| A10 | **The vendor evaluation of the weak-label model is in-sample** (trained and scored on the same points), so the comparison rows are not like-for-like. | low-medium | `analysis/pipeline.R` vendor block | S | 1 |
| A11 | **Line merging splits at every junction**: chainage resets per part, a junction tower projects onto one part only, stub segments appear, and `profile$line_id` can disagree with `segments$line_id`. | low-medium (medium on distribution) | `R/geometry.R`, `R/risk.R` | M | 1 |
| A12 | Fall-in approximations: the phase offset is subtracted from the radial distance to the vertex rather than the perpendicular (conservative); the wind arc is symmetric on a sloping span. | low | `R/risk.R`, `R/wind.R` | S | 2 |
| A13 | The Landsat composite grid is the first readable scene's crop; a scene edge truncates every later scene silently. | low | `R/landsat.R` | S | |
| A14 | Dryness percentiles rank segment means against single-pixel values, under-flagging multi-pixel segments. | low-medium | `R/landsat.R` | S | |
| A15 | A fixed 3 m structure label radius on lattice towers teaches tower steel as vegetation; this likely explains structure AP 0.008 better than "doesn't transfer". | low | `R/labels.R` | S | 1 |
| A16 | Bookkeeping: `plausible_bins` compares with the next surviving bin at any distance; `n_measured` counts bins that interpolation then drops; points between `min_height_m` and `gap_floor_m` in a wire cell get the wire label. | low | `R/risk.R`, `R/labels.R` | S | |

**Verified sound:** the US-survey-feet path end to end; prior correction; tie-aware weighted AP; order-independent folds; the vendor baseline and kappa; the Landsat QA mask and Collection 2 scaling; the hitting-arc derivation, bearing and grid-convergence signs; the support chord and `Inf` past the last support (given a correct support set); conductor-envelope removal; void detection; the minimum-3D reach search.

### B. Engineering and scale

| # | Finding | Severity | Where | Effort | Blocks a scheduled service |
|---|---|---|---|---|---|
| B1 | **Every raster and per-cell table covers the point cloud's bounding box, not the corridor.** A 70 km diagonal line with an 80 m corridor is about 2.5 billion 1 m cells; `tabulate` alone is ~10 GB and `as.data.frame` far more. | high | `R/risk.R` rasterize, `assess_risk` cells, `R/landsat.R` | M | yes |
| B2 | **The whole corridor cloud lives in RAM and is copied several times** (`unnormalize_height`, `feat`, `pred`, `allp`, returned to the caller). ~1e6 points per km at QL1. | high | `R/preprocess.R`, `R/features.R`, `R/risk.R`, pipeline return | L | yes |
| B3 | **`pid` row-order coupling between `las`, `feat` and `pred` is implicit and unchecked**; `las$Zref` is read without checking it exists. The first thing a chunked refactor breaks, silently. | high | `R/features.R`, `R/risk.R`, pipeline | S | no |
| B4 | **Caches and model reuse are keyed by file name or an environment variable, not by inputs.** OSM layers ignore `line_ids`, `window_m` and AOI; the model ignores `half_width_m`, `wire_search_m`, tiles and `k`; Landsat and wind ignore their date ranges. A changed config emits a fresh-looking summary on stale inputs. | high | `analysis/pipeline.R` | M | yes |
| B5 | **`run_case_study()` is a script-scoped function with cwd-relative paths, no config validation and no failure isolation.** A `NULL` `cfg$wire_search_m` silently disables the near-line test; one bad corridor aborts a batch; figures are written into `man/`. | high | `analysis/pipeline.R` | M | yes |
| B6 | **About 26 forest fits per corridor, each with permutation importance, on all cores** (two CV schemes, ablation, vendor reference, final fit); only the final importance is used. Nothing sets thread counts for ranger, data.table or lidR. | high (cost) | `R/classify.R`, pipeline | M | yes at 200 corridors |
| B7 | **Degenerate inputs crash with unhelpful errors** (confirmed by running): zero-length line, empty sf, a line clipped to a POINT by the extent intersection, zero labelled points, NA coordinates; fewer than 31 above-ground points aborts a run that should return "none". | medium-high | `R/geometry.R`, `R/risk.R`, `R/features.R`, pipeline | S | partial |
| B8 | **External queries use the AOI bounding box; no throttle; weather clients bypass `vegrisk_request()` and have no timeout.** A long diagonal line asks Overpass for every building in a rectangle. | medium | `R/fetch.R`, `R/landsat.R`, `R/wind.R` | M | yes for long lines |
| B9 | **State leaves the pipeline as attributes, live SpatRasters and GeoPackages, re-joined by directory.** SpatRasters die across `saveRDS` and workers; attributes are lost by `st_write`; factors become strings; `watchlist.R` pairs files by directory with no run-id check; GPKG writes are not atomic. | medium | `R/risk.R`, `R/wind.R`, pipeline, `analysis/watchlist.R` | M | yes |
| B10 | O(segments x cells) and O(segments x trees) loops; `segment_lines` is quadratic in line length (11.8 s for 100 km); the reach search allocates n_trees x k matrices twice. | medium | `R/risk.R`, `R/wind.R`, `R/landsat.R` | M | at 100 km+ |
| B11 | **Identities are unique within one call only**: `seg_id` restarts at 1 per corridor, `tree_id` has no CRS or zone, segments are equal cuts not spans, `conductor_profile` renumbers lines in union order. | medium | `R/risk.R`, `R/geometry.R` | M | yes for a store |
| B12 | Tile cache keyed by site, mixed CRS across tiles unchecked, `file.rename` result ignored, a TNM item without `sizeInBytes` crashes. | medium | pipeline, `R/fetch.R` | S-M | |
| B13 | No cross-object CRS or id consistency checks between stages (`rasters`, `segments`, `profile`, `structures`). | medium | `R/risk.R`, `R/landsat.R` | S | |
| B14 | Test gaps: no end-to-end synthetic-LAZ test, no `read_corridor` test, no degenerate-geometry tests, no serialisation round-trip, no pipeline or cache-key test. | medium | `tests/` | M | |
| B15 | Packaging: CI on ubuntu and macOS only; `jsonlite` undeclared; no `renv.lock` or container; generic `globalVariables` entries hide real notes. | low-medium | `DESCRIPTION`, workflows | S | |
| B16 | `attr<-` on data.tables breaks the self-reference (confirmed); use `setattr()`. | low | `R/features.R` | S | |
| B17 | One weather record and one grid convergence per run. | low | `R/wind.R` | M | |

### C. Reproducibility, provenance and operations

| # | Finding | Severity | Where | Effort | Blocks auditable operation |
|---|---|---|---|---|---|
| C1 | **The run configuration and resolved parameters are not recorded anywhere.** `cfg` is never written; hard-coded `block_m`, `n_folds`, `seg_m`, `res_m`, `n_per_class`, `num_trees`, `k`, `min_height_m`, Landsat gates, `windward_min`, `min_hours` and seeds exist only in code. Answering "why is segment 17 grow-in" means checking out the SHA. | high | pipeline summary block | M | yes |
| C2 | **No run id on any data artefact; each run overwrites the previous.** On disk now the Nashville GPKG has a different schema from Sunshine's with no marker. | high | pipeline outputs | M | yes |
| C3 | **Multi-file output is non-atomic with no completion marker.** `delete_dsn = TRUE` deletes before writing; a crash between `trees.gpkg` and `summary.rds` leaves `watchlist.R` applying the old run's thresholds to the new trees, silently. | high | pipeline, `analysis/watchlist.R` | M | yes |
| C4 | **Caches are not keyed by what produced them** (OSM, Landsat, wind, model); the wind cell lives in a separate file that a crash can orphan. The Sunshine composite on disk predates the run that used it by 52 hours. | high | pipeline | M | yes |
| C5 | **Source data is neither pinned nor verified**: Overpass queries have no `[date:]`, the committed GeoJSON caches have no sidecars, tiles present by name bypass the size check, no checksums or LAS header identity recorded. | high | `R/fetch.R`, pipeline | M | yes |
| C6 | **The software environment is not recorded or pinned**: no R, GDAL/GEOS/PROJ or package versions, no `renv.lock`, `load_all()` runs a possibly dirty working copy, `git_sha()` never checks for a dirty tree. A newer PROJ can move the line a metre. | high | pipeline, `DESCRIPTION` | M | yes |
| C7 | **Model reuse has no input or code validity check**; `vendor.rds` reuse ignores the transfer model's identity; the Sunshine-then-Nashville run order is undocumented and matters. | medium-high | pipeline | S-M | |
| C8 | **The NWS watchlist is not reproducible**: raw responses discarded, flagged hours not written, no run linkage, an unknown wind unit is treated as km/h, the User-Agent lacks the contact NWS asks for. | medium-high | `analysis/watchlist.R`, `R/wind.R` | S-M | |
| C9 | **Wind history**: no `models=` pin (Open-Meteo archive may blend products), free-tier terms are non-commercial, no timeout, response metadata discarded. | medium-high | `R/wind.R` | S + a licensing decision | |
| C10 | Landsat: partial composites cached up to 20% errors; a shim invents `used = TRUE` for old logs; STAC query not recorded; GDAL error text with SAS tokens can land in `landsat_scenes.csv`; no GDAL HTTP timeouts. | medium | `R/landsat.R`, pipeline | S-M | |
| C11 | Output schema unstable and under-documented: factors lose levels, columns vary with config, feet geometry beside metre columns with no CRS in the CSVs, CRLF line endings, `summary.rds` readable only from R. | medium | pipeline, `R/risk.R` | M | |
| C12 | Non-determinism uncontrolled: thread counts unrecorded, locale-dependent `sort(files)`, no golden test. | medium | `R/classify.R`, `R/preprocess.R` | S-M | |
| C13 | Operations: `message()`-only logging, warnings not persisted, exit 0 on degraded runs, no lockfile, cwd-relative paths. | medium | pipeline | M | yes |
| C14 | API clients: TNM `total` NULL crashes; public Overpass with no pause; ODbL attribution not carried into outputs. | medium-low | `R/fetch.R` | S | |
| C15 | CI never exercises the pipeline or `watchlist.R`; actions pinned by tag. | low-medium | workflows | M | |

**What an auditor cannot reconstruct from `output/` today:** which code (dirty or clean) and package versions ran; the configuration and parameters; which tiles, with what checksums; the OSM snapshot; the Landsat query and scene versions; the wind model and retrieval time; the forecast behind any watchlist; whether the GPKG and the summary came from the same run; and any previous run.

### D. Twin readiness (gaps against RFC 0001)

| # | Gap | Phase | Effort |
|---|---|---|---|
| D1 | **No acquisition date or data vintage anywhere.** `read_corridor()` selects `xyzirnc`, so GPS time is never read; TNM `pub_date` is discarded; `summary.rds` has no acquisition field. `valid_from` has nothing to come from, and Phase 2 needs the flight hour for conductor temperature. | 1 | S |
| D2 | **No stable identity.** `line_id` from merge order, `seg_id` ordinal per run, chainage relative to the clipped window, `osm_id` by nearest feature (arbitrary at junctions), `tree_id` in CRS units. | 1 | M |
| D3 | **Segments are 50 m chainage cuts, not structure-to-structure spans.** Supports only draw the upper-bound chord; at Sunshine 257 to 468 m spans cover 5 to 9 segments each. Sag, ruling span and blowout are span properties; utilities trim and report by span. | 1 | M |
| D4 | **Outputs are overwritten and unversioned**; as-of queries are impossible. | 0/1 | S-M |
| D5 | Caches keyed by path (see B4, C4). | 1 | S |
| D6 | **Single-line, single-window, in-memory architecture**: only the first merged part gets a profile; one weather cell and one grid convergence per site; a random forest per site that recalled 0% elsewhere. | 1 | L |
| D7 | **Distribution lines**: transmission-tuned label floors and windows, single-scalar bounds, an 8 m structure mask that hides 20 to 40% of a pole line, no overhang metric, binary strike saturates, patchy OSM `minor_line` coverage, no vendor classes in DRCOG 2020. | 1 | M-L |
| D8 | **Conductor physics**: no catenary fit, assumed attachment heights, no ruling span, no conductor type (OSM `cables`/`wires` not fetched), no flight temperature (ERA5 temperature not requested), one symmetric phase offset. A cheap first step exists: parabola per measured span plus a conservative maximum-temperature sag, then blowout from a design wind pressure. FAC-003 MVCD is altitude-dependent on the Front Range. | 2 | M, then L |
| D9 | **Vertical units half-guarded**: only the horizontal unit is parsed; Colorado State Plane North (Boulder, Larimer), Central (Denver, Jefferson, Douglas) and South zones in US survey feet will arrive alongside UTM metres. | 0/1 | S |
| D10 | No hand-labelled truth (protocol in Part 3). | 1 | M (GIS labour) |
| D11 | OSM attributes needed for conflation are dropped at fetch: `ref`, `circuits`, `cables`, `wires`, `design`, `material`, `height`, `line_attachment`, node order. | 1 | S |
| D12 | RiskScore is a tier, not a number; no driver decomposition beyond grow-in/fall-in; no consequence. | 3 | M, then L |
| D13 | Run record incomplete (see C1). | 1 | S |

**Entity coverage today:** Structure: no (transient `supports`). Span: no (segments as proxy). ConductorState: partly (`conductor_profile.csv`, bin counts). Equipment: no. Tree: partly (`trees.gpkg`). FuelCell: partly (greenness only). ConditionsCell: partly (one cell). RiskScore: partly (tiers). Action: no. The four fields the RFC requires on every row (`valid_from`/`valid_to`, `source`, confidence, model version) are missing from every output table except `confidence` on segments.

## Part 2: Colorado context (as of 21 October 2026)

Sourced in the research pass; the PUC's own site refused automated access, so PUC claims rest on secondary summaries and Xcel's filings.

- **No statute or rule has required WMPs to date.** Xcel's plans were filed voluntarily. The PUC voted 3-0 on 23 September 2026 to open **rulemaking 26R-0355E**, applying to Xcel (PSCo) and Black Hills: a full WMP every three years, annual progress reports, performance data twice a year, PSPS plans every three years with PSPS as a last resort. Proposed content: assess wildfire likelihood and consequence tied to utility equipment, identify high-risk areas, have the assessments independently checked, compare mitigation options by cost, risk reduction and reliability, and cover inspections, vegetation management, system improvements and emergency preparedness. Initial comments were due 2 November 2026, hearing 23 November. No mention of span-level modelling, LiDAR or digital twins was found in the summaries; "likelihood and consequence tied to equipment" is the hook.
- **Xcel's 2025 to 2027 WMP** (Proceeding 24A-0296E, filed June 2024) was settled unanimously and approved by the PUC on 5 June 2025 at about $1.9B including about 50 miles of targeted undergrounding. Risk model: Technosylva Wildfire Analyst Enterprise plus an independent three-tier territory map (replacing the Wildfire Risk Zone, which covered about 2,100 of 9,500 distribution feeder miles and 2,800 of 5,000 transmission miles). LiDAR is used on distribution lines to build a 3D model for pole-loading and clearance work; about 2,800 transmission miles are inspected visually each year; programmes include Mountain Hazard Tree and Defensible Space Around Poles. First Colorado PSPS was April 2024 (investigated under 24M-0173E); the settlement requires 72/48/24-hour notices. Marshall Fire: Xcel and two telecoms settled on 24 September 2025 for about $640M without admitting fault.
- **Other utilities:** CORE Electric Cooperative's 2026 WMP uses CSFS CO-WRA 2023 layers and Technosylva Wildfire Ops with simulated ignitions every 100 m of line, a six-year vegetation cycle and nine Pano AI stations. Black Hills has a WMP (June 2026) not filed as an application. Colorado Springs Utilities (January 2025), Holy Cross and Tri-State publish plans or fact sheets.
- **Data:** 3DEP projects on the Front Range WUI include `CO_DRCOG_2020_B20` (QL1 and QL2, Leica Terrain Mapper, June 2020 to March 2021, vegetated vertical accuracy 22 cm, **no vegetation classes**, which matches the Sunshine case study), `CO_ArapahoRooseveltPikeNF_D23`, `CO_CONMGaps_D24`, `CO_CameronPeakWildfire_2021_D21`, `CO_EasternColorado_2018_A18`. **HIFLD Open was discontinued in August 2025**; archives exist (source.coop, HSDL) but a current transmission-line source is OSM, EIA or the utility. CSFS CO-WRA 2022 update released July 2023 on a five-year cycle (next about 2027), served through the Colorado Forest Atlas. LANDFIRE LF 2024 is version 2.5.0. Colorado State Plane zones 0501/0502/0503 in US survey feet; NAVD88 vertical.
- **Standards:** NESC 2023 (IEEE C2-2023); NERC FAC-003-5 enforceable since April 2024 (R2 retired, qualified circuits folded into R1); IEEE 738 (current edition to confirm). California's Public Utilities Code 8386-8387 and the Energy Safety 2026-2028 guidelines (adopted February 2025) have a parallel three-year-plan-plus-annual-update structure; no source says Colorado follows California, so the RFC says "similar structure", not "modelled on".
- **Unverified:** the rule text of 26R-0355E, Xcel's PSPS trigger thresholds and trim-cycle length, whether the tier map is public, IEEE 738's current edition, and DRCOG 2020's exact pulse density and compound CRS per work unit.

## Part 3: What to do, in order

The revised roadmap in `vignettes/articles/limits-and-roadmap.Rmd` and RFC 0001 carry the plan; this section says why the order is what it is.

1. **Fix the three science findings that change what a span's state means** (A1, A2, A3), with A4 to A6. These are small, and every later layer inherits them.
2. **Give every row an identity and a time** (D1, D2, D4, C1, C2, C3): acquisition date from GPS time, stable keys in a canonical CRS, append-only versioned outputs, the run manifest. This is the Phase 0/1 foundation and it is mostly S and M work.
3. **Key on spans** (D3, A11, D11): structure table from OSM nodes plus a LiDAR column check, split lines at structures, aggregate station metrics per span, flag implausible span lengths. Protective-device sections arrive later as a versioned grouping.
4. **Make it run over a territory** (B1, B2, B3, B4, B5, B6, B7, B8, B9): chunked processing with buffered windows, corridor-masked rasters, a validated `vegrisk_run(corridor, inputs, params, store)`, content-addressed caches, a regional model with per-corridor prediction only, typed no-data outcomes.
5. **Distribution** (A7, D7): voltage-class parameter presets, a through-canopy conductor detector, structure-type masks, overhang and canopy-above-conductor metrics, honest `bounded` reporting.
6. **Conductor physics** (D8, A12): the cheap conservative sag first, then IEEE 738 with blowout, validated on spans flown twice.
7. **Truth** (D10, A9, A10): the labelling protocol, per-fold spreads, out-of-fold vendor evaluation.
8. **Consequence and a numeric vegetation-contact index** (D12), pre-registered validation.

### Hand-labelling protocol (the gap every reviewer named)

Classes: ASPRS 2 ground, 3 to 5 vegetation, 6 building, 13 guard/shield wire, 14 conductor, 15 transmission tower, 16 wire-structure connector, plus user classes for wood pole, communication wire and *uncertain*. Sampling unit: whole spans, structure to structure, with the full corridor half-width; never random points, which leak like random CV. Strata fixed before looking at model output: transmission vs distribution, structure type, canopy density, terrain, acquisition; at least about 30 spans per stratum and two acquisitions. Labelled spans held out from training, tuning and thresholds, buffered from training blocks by the 30 m feature radius plus the run window. 15 to 20% double-labelled blind with per-class kappa and a written adjudication rule; tool, annotator, date and time recorded. Derived truth per span: conductor elevation per 5 m bin and true minimum clearance. Frozen release with checksums and a label-guide version.

### Minimum run manifest

Written last and atomically as `manifest.json`; readers refuse a run directory without one.

- Identity: `schema_version`, `run_id`, `site_id`, `started_utc`, `finished_utc`, `status` (complete / degraded / failed), `mode` (full / reuse), `reused_from` {run_id, model_md5, inputs_fingerprint}, `hostname`.
- Code and environment: `vegrisk_version`, `git_sha`, `git_dirty`, `git_diff_sha256`, `r_version`, `platform`, `locale`, `tz`, package versions or the `renv.lock` hash, `sf_extSoftVersion` (GDAL, GEOS, PROJ, `PROJ_NETWORK`), thread counts, RNG kind and seeds.
- Configuration: the full `cfg` and every effective parameter with its default filled in.
- Inputs: per tile {file, url, bytes, sha256, tnm_pub_date, las_guid, las_creation_date, crs_wkt}; per OSM layer {file, sha256, osm_timestamp, query, fetched_at, n, overpass_url, date_pin}; Landsat {stac_url, query_json, n_found, scenes[], composite_sha256, composite_params}; wind {url, query, model, retrieved_at, cell, elevation, units, start, end, n_hours, sha256}.
- Models: {path, sha256, fitted_run_id, fitted_at, features, training_fingerprint}; transfer model likewise; fire-weather thresholds.
- Outputs: per file {path, sha256, bytes, rows, columns with type, unit and levels, crs}; captured warnings; step timings; counts.
- Watchlist runs add: parent run id and segment hash, NWS points URL, grid, `updateTime`, `generatedAt`, alert ids, raw JSON hashes, thresholds, bound, user agent.

## Part 4: Issues filed

Filed on 21 October 2026, in this order, each labelled with its RFC phase.

| Issue | Findings | Phase |
|---|---|---|
| #49 fall-in tested only at the two bounds | A1 | 1, 2 |
| #50 vertical-only clearance in a fixed band | A2 | 1, 2 |
| #51 unfiltered support set behind the upper bound | A3 | 1, 2 |
| #52 data vintage: GPS time, project, checksums | D1, C5 | 1 |
| #53 stable identity and structure-to-structure spans | D2, D3, B11, A11, D11 | 1 |
| #54 run manifest, versioned outputs, atomic completion | C1, C2, C3, C6, C13, D4, D13 | 0, 1 |
| #55 chunked, corridor-masked processing | B1, B2, B3, B10 | 1 |
| #56 content-addressed caches and pinned inputs | B4, C4, C5, C7 | 1 |
| #57 `vegrisk_run()` with validation and typed outcomes | B5, B7, B9 | 1 |
| #58 disagreement exclusion leaves a cell observed | A4 | 1 |
| #59 masked area counted as observed | A5 | 1 |
| #60 Sunshine envelope warning | A6 | 1 |
| #61 distribution-line presets | A7, D7 | 1 |
| #62 one regional model, thread budgets | B6 | 1 |
| #63 per-fold CV spread, out-of-fold vendor scoring | A9, A10 | 1, 4 |
| #64 weather clients, Open-Meteo terms, NWS reproducibility | C8, C9, B8 | 1 |
| #65 crown-support filter and label radii | A8, A15, A16 | 1 |
| #66 conductor physics | D8, A12 | 2 |
| #67 output schema, determinism, Landsat hygiene, packaging | C10-C15, B12, B13, B15-B17, A13, A14 | 1 |
| #68 tests before the refactor | B14 | 1 |
| #69 compound CRS and canonical output CRS | D9 | 0, 1 |
| #70 hand-labelled test set | D10 | 1 |
| #71 vegetation-contact index and consequence | D12 | 3 |
