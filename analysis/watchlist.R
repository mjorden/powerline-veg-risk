# Segments to watch under the coming fire weather, from a finished case study.
#
#   Rscript analysis/watchlist.R sunshine
#
# Needs a complete run of the site (output/<site>/latest.txt, or a run id as
# the second argument) whose config set `wind` (and optionally `landsat`).
# The run is opened with read_run(), which refuses a run without a manifest
# and checks that the tables carry the run's id (#54). Pulls the live NWS
# hourly forecast and active alerts for the corridor and applies the
# climatological fire-weather thresholds; nothing is reprocessed. Writes
# output/<site>/watchlist.csv (the latest list, with the settings it was
# made with and the parent run id in every row) and a folder
# output/<site>/watchlists/<utc>_<run id>/ that holds everything the list
# was made from (#64): the list, the flagged forecast hours, the NWS
# /points, gridpoint and alerts responses exactly as received, and
# meta.json with their checksums and retrieval times, the parent run and
# the checksum of the segments it was applied to. Earlier lists are kept. A
# list with nothing flagged is one row saying so, not an empty file.
#
# Set VEGRISK_CONTACT (or options(vegrisk.contact = )) to the address the
# NWS should use to reach you; it goes into the User-Agent.

devtools::load_all(quiet = TRUE)
suppressPackageStartupMessages(library(sf))

args <- commandArgs(trailingOnly = TRUE)
site <- args[1]
if (is.na(site)) site <- "sunshine"
out <- file.path("output", site)
run <- read_run(out, run_id = if (length(args) >= 2) args[2] else NULL)
message(sprintf("run %s (%s, %s)", run$run_id, run$manifest$mode, run$manifest$finished_utc))
summary <- readRDS(file.path(run$run_dir, "summary.rds"))
if (is.null(summary$wind)) stop("Run the case study with a `wind` config first.")

segments <- st_read(file.path(run$run_dir, "segments.gpkg"), quiet = TRUE)
trees <- st_read(file.path(run$run_dir, "trees.gpkg"), quiet = TRUE)
attr(segments, "wind") <- summary$wind
risk <- list(segments = segments, trees = trees)

fc <- nws_forecast(segments)
alerts <- nws_alerts(segments)
message(sprintf("NWS %s grid %s: %d forecast hours, %s to %s UTC; %d active alert(s)%s",
                attr(fc, "office"), attr(fc, "grid"), nrow(fc),
                format(min(fc$time), "%a %d %b %H:%M"), format(max(fc$time), "%a %d %b %H:%M"),
                nrow(alerts), if (nrow(alerts)) paste0(": ", paste(unique(alerts$event), collapse = ", ")) else ""))
message(sprintf("Fire-weather thresholds (from the %d-hour record): gust >= %.1f m/s, RH <= %g%%",
                summary$wind$n_record, summary$wind$min_gust_ms, summary$wind$max_rh))
message(sprintf("Forecast peak gust %.1f m/s; minimum RH %.0f%%",
                max(fc$gust_ms, na.rm = TRUE), min(fc$rh_pct, na.rm = TRUE)))

now <- Sys.time()
bound <- "lo"  # pessimistic (code-minimum) conductor, as in the wind-exposure map
wl <- forecast_watchlist(risk, fc, alerts, bound = bound, now = now)
hours <- attr(wl, "hours")
st <- attr(wl, "settings")
if (nrow(hours) == 0) {
  message("No forecast hour meets the fire-weather criteria and no Red Flag Warning is active.")
} else {
  message(sprintf("%d flagged hour(s); %d segment(s) to watch:", nrow(hours), nrow(wl)))
  print(as.data.frame(wl))
}

# What this list was made with, in every row, so the CSV stands on its own.
meta <- data.frame(
  generated_at = format(now, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
  parent_run_id = run$run_id, vegrisk_version = as.character(packageVersion("vegrisk")),
  segments_md5 = unname(tools::md5sum(file.path(run$run_dir, "segments.gpkg"))),
  nws_office = attr(fc, "office"), nws_grid = attr(fc, "grid"),
  nws_updated = if (is.null(attr(fc, "updated"))) NA_character_ else attr(fc, "updated"),
  forecast_from = format(min(fc$time), "%Y-%m-%dT%H:%MZ", tz = "UTC"),
  forecast_to = format(max(fc$time), "%Y-%m-%dT%H:%MZ", tz = "UTC"),
  past_hours_dropped = st$n_past_hours_dropped,
  min_gust_ms = st$min_gust_ms, max_rh_pct = st$max_rh, spread_deg = st$spread_deg,
  bound = bound, n_flagged_hours = nrow(hours),
  active_alerts = if (nrow(alerts)) paste(unique(alerts$event), collapse = "; ") else "",
  stringsAsFactors = FALSE)
rows <- if (nrow(wl) > 0) as.data.frame(wl) else {
  data.frame(seg_id = NA_integer_, first_hour = as.POSIXct(NA, tz = "UTC"), n_hours = 0L,
             max_gust_ms = NA_real_, min_rh_pct = NA_real_, n_trees_exposed = 0L,
             red_flag = FALSE, dry_grow_in = NA)
}
rows$note <- if (nrow(wl) > 0) "" else "no segments flagged"
out_rows <- cbind(rows, meta[rep(1, nrow(rows)), , drop = FALSE])
# Everything the list was made from, in one folder per list.
wl_dir <- file.path(out, "watchlists", sprintf("%s_%s", format(now, "%Y%m%dT%H%M%SZ", tz = "UTC"), run$run_id))
dir.create(wl_dir, recursive = TRUE, showWarnings = FALSE)
data.table::fwrite(out_rows, file.path(wl_dir, "watchlist.csv"), eol = "\n")
data.table::fwrite(as.data.frame(hours), file.path(wl_dir, "flagged_hours.csv"), eol = "\n")
data.table::fwrite(as.data.frame(fc), file.path(wl_dir, "forecast_hours.csv"), eol = "\n")
raw <- c(attr(fc, "raw"), attr(alerts, "raw"))
responses <- lapply(names(raw), function(nm) {
  path <- file.path(wl_dir, paste0("nws_", nm, ".json"))
  writeBin(charToRaw(enc2utf8(raw[[nm]]$body)), path)
  list(file = basename(path), url = raw[[nm]]$url, retrieved = raw[[nm]]$retrieved,
       md5 = unname(tools::md5sum(path)), bytes = file.size(path))
})
names(responses) <- names(raw)
jsonlite::write_json(
  list(meta = as.list(meta), settings = lapply(st, function(x) if (inherits(x, "POSIXt")) format(x, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC") else x),
       user_agent = vegrisk_user_agent(), responses = responses,
       files = list(watchlist = unname(tools::md5sum(file.path(wl_dir, "watchlist.csv"))),
                    flagged_hours = unname(tools::md5sum(file.path(wl_dir, "flagged_hours.csv"))),
                    forecast_hours = unname(tools::md5sum(file.path(wl_dir, "forecast_hours.csv"))))),
  file.path(wl_dir, "meta.json"), auto_unbox = TRUE, pretty = TRUE, null = "null", digits = NA)
# The latest list is replaced in one step, so a reader never sees half of it.
tmp <- file.path(out, "watchlist.csv.tmp")
data.table::fwrite(out_rows, tmp, eol = "\n")
if (!file.rename(tmp, file.path(out, "watchlist.csv"))) stop("could not replace watchlist.csv", call. = FALSE)
message("wrote ", wl_dir)
