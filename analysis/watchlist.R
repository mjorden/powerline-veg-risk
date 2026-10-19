# Segments to watch under the coming fire weather, from a finished case study.
#
#   Rscript analysis/watchlist.R sunshine
#
# Needs output/<site>/ from a run whose config set `wind` (and optionally
# `landsat`). Pulls the live NWS hourly forecast and active alerts for the
# corridor and applies the climatological fire-weather thresholds; nothing
# is reprocessed. Writes output/<site>/watchlist.csv.

devtools::load_all(quiet = TRUE)
suppressPackageStartupMessages(library(sf))

site <- commandArgs(trailingOnly = TRUE)[1]
if (is.na(site)) site <- "sunshine"
out <- file.path("output", site)
summary <- readRDS(file.path(out, "summary.rds"))
if (is.null(summary$wind)) stop("Run the case study with a `wind` config first.")

segments <- st_read(file.path(out, "segments.gpkg"), quiet = TRUE)
trees <- st_read(file.path(out, "trees.gpkg"), quiet = TRUE)
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

wl <- forecast_watchlist(risk, fc, alerts, bound = "lo")
hours <- attr(wl, "hours")
if (nrow(hours) == 0) {
  message("No forecast hour meets the fire-weather criteria and no Red Flag Warning is active.")
} else {
  message(sprintf("%d flagged hour(s); %d segment(s) to watch:", nrow(hours), nrow(wl)))
  print(as.data.frame(wl))
}
data.table::fwrite(wl, file.path(out, "watchlist.csv"))
