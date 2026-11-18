# Content-addressed caches (#56). Every cached input is stored under a key
# derived from the request that produced it (and from the upstream inputs
# it depends on), next to a sidecar that records that request. A cache
# entry is used only when the sidecar is there, the request it records is
# the one being made, and the file's checksum is the one the sidecar
# recorded; anything else is refetched. A file that exists by name alone
# proves nothing about what produced it.

#' Canonical form and key of a cache request
#'
#' The request is serialised to JSON with names sorted at every level, so
#' the same request gives the same text whatever order the arguments were
#' given in and whether a number arrived as integer or double; the key is
#' a hash of that text.
#'
#' @param kind What is cached (`"osm_line"`, `"landsat_composite"`, ...).
#' @param args A named list: every argument the fetch depends on. Round
#'   coordinates to the precision that matters before passing them.
#' @param upstream Optional named list of upstream identities (checksums,
#'   keys of other cache entries) the result depends on.
#' @return A list: `key` (16 hex characters), `request` (the canonical
#'   JSON text).
#' @export
cache_key <- function(kind, args, upstream = NULL) {
  if (!is.character(kind) || length(kind) != 1 || !grepl("^[A-Za-z0-9_]+$", kind)) {
    rlang::abort("`kind` must be one word of letters, digits and underscores.")
  }
  if (length(args) && is.null(names(args))) rlang::abort("`args` must be a named list.")
  request <- canonical_json(list(kind = kind, args = args, upstream = upstream))
  list(key = substr(rlang::hash(request), 1, 16), request = request)
}

# JSON with every object's names sorted, so equal requests give equal text.
canonical_json <- function(x) {
  as.character(jsonlite::toJSON(sort_names(x), auto_unbox = TRUE, digits = NA, null = "null",
                                na = "null", POSIXt = "ISO8601", Date = "ISO8601", force = TRUE))
}

sort_names <- function(x) {
  if (is.list(x) && !is.data.frame(x)) {
    if (!is.null(names(x)) && all(nzchar(names(x)))) x <- x[order(names(x))]
    x <- lapply(x, sort_names)
  }
  if (is.factor(x)) x <- as.character(x)
  x
}

#' Get a cached input, fetching and caching it when there is no valid entry
#'
#' The entry lives at `<dir>/<kind>-<key>.<ext>` with a sidecar
#' `<...>.meta.json`. The data file is written to a temporary name and
#' renamed into place, and the sidecar is written last, so a crash leaves
#' either a complete entry or no entry. An entry without a sidecar, whose
#' sidecar records a different request, or whose checksum no longer matches
#' the sidecar is not used.
#'
#' @inheritParams cache_key
#' @param dir Cache directory (created if needed).
#' @param fetch A function of no arguments that produces the object. It may
#'   set attribute `cache_skip` (a reason) on its result to have it returned
#'   for this run but not cached.
#' @param read A function `(path, meta)` that reads the data file; `meta` is
#'   the sidecar as a list (its `source` field holds what `extra` recorded).
#' @param write A function `(x, path)` that writes the object to `path`.
#'   `path` is a temporary name, so give the format explicitly (`driver =`,
#'   `filetype =`) rather than relying on the extension.
#' @param ext File extension of the data file.
#' @param refresh `"missing"` fetches only when there is no valid entry;
#'   `"always"` fetches and replaces the entry; `"never"` aborts instead of
#'   fetching, for a run that must use only what is on disk.
#' @param extra Optional function `(x)` returning a named list to record in
#'   the sidecar's `source` field (a snapshot time, a scene list).
#' @return The object, with attribute `cache`: a list `path`, `key`, `hit`
#'   (`TRUE` when read from the cache), `cached` (`FALSE` when the fetch
#'   asked not to be cached) and `meta` (the sidecar).
#' @export
cache_get <- function(kind, args, dir, fetch, read, write, ext, upstream = NULL,
                      refresh = c("missing", "always", "never"), extra = NULL) {
  refresh <- match.arg(refresh)
  k <- cache_key(kind, args, upstream)
  dir.create(dir, showWarnings = FALSE, recursive = TRUE)
  path <- file.path(dir, sprintf("%s-%s.%s", kind, k$key, ext))
  meta_path <- paste0(path, ".meta.json")

  if (refresh != "always") {
    state <- cache_state(path, meta_path, k$request)
    if (state$valid) {
      x <- read(path, state$meta)
      attr(x, "cache") <- list(path = path, key = k$key, hit = TRUE, cached = TRUE, meta = state$meta)
      return(x)
    }
    if (!is.null(state$reason)) message(sprintf("cache %s: %s; refetching", basename(path), state$reason))
    if (refresh == "never") {
      rlang::abort(c(sprintf("No valid cache entry for %s and refresh = \"never\".", basename(path)),
                     i = state$reason %||% "no entry on disk"))
    }
  }

  x <- fetch()
  skip <- attr(x, "cache_skip")
  if (!is.null(skip)) {
    attr(x, "cache_skip") <- NULL
    attr(x, "cache") <- list(path = path, key = k$key, hit = FALSE, cached = FALSE, meta = NULL,
                             skipped = skip)
    return(x)
  }
  tmp <- paste0(path, ".tmp")
  if (file.exists(tmp)) unlink(tmp)
  write(x, tmp)
  if (!file.exists(tmp)) rlang::abort(sprintf("`write` did not create %s.", tmp))
  if (file.exists(meta_path)) unlink(meta_path) # an old sidecar must never describe the new file
  if (!file.rename(tmp, path)) rlang::abort(sprintf("could not replace %s", path))
  meta <- list(
    schema_version = 1L, kind = kind, key = k$key, request = k$request,
    args = args, upstream = upstream,
    fetched_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
    vegrisk_version = as.character(utils::packageVersion("vegrisk")),
    file = file_record(path),
    n = if (is.data.frame(x)) nrow(x) else NULL,
    source = if (!is.null(extra)) extra(x) else NULL
  )
  write_json_atomic(meta, meta_path)
  attr(x, "cache") <- list(path = path, key = k$key, hit = FALSE, cached = TRUE, meta = meta)
  x
}

# Is the entry on disk usable for this request? A sidecar is required; the
# request it records must be this one; the file must be the one it
# describes.
cache_state <- function(path, meta_path, request) {
  if (!file.exists(path) && !file.exists(meta_path)) return(list(valid = FALSE, reason = NULL))
  if (!file.exists(meta_path)) return(list(valid = FALSE, reason = "data file has no sidecar"))
  if (!file.exists(path)) return(list(valid = FALSE, reason = "sidecar has no data file"))
  meta <- tryCatch(jsonlite::read_json(meta_path, simplifyVector = TRUE), error = function(e) NULL)
  if (is.null(meta) || !identical(meta$request, request)) {
    return(list(valid = FALSE, reason = "sidecar records a different request"))
  }
  md5 <- unname(tools::md5sum(path))
  if (!identical(meta$file$md5, md5)) {
    return(list(valid = FALSE, reason = sprintf("checksum %s is not the sidecar's %s", md5, meta$file$md5)))
  }
  list(valid = TRUE, meta = meta)
}

write_json_atomic <- function(x, path) {
  tmp <- paste0(path, ".tmp")
  jsonlite::write_json(x, tmp, auto_unbox = TRUE, pretty = TRUE, digits = NA, null = "null", na = "null",
                       POSIXt = "ISO8601", Date = "ISO8601", force = TRUE)
  if (!file.rename(tmp, path)) rlang::abort(sprintf("could not replace %s", path))
  invisible(path)
}

#' Refresh policy for a cache kind from the environment
#'
#' `VEGRISK_REFRESH` names the kinds to refetch, comma-separated, or `all`;
#' `VEGRISK_OFFLINE=1` forbids fetching.
#'
#' @param kind The cache kind.
#' @return `"missing"`, `"always"` or `"never"`, for [cache_get()].
#' @export
cache_policy <- function(kind) {
  if (Sys.getenv("VEGRISK_OFFLINE") == "1") return("never")
  want <- trimws(strsplit(Sys.getenv("VEGRISK_REFRESH"), ",")[[1]])
  if ("all" %in% want || kind %in% want) "always" else "missing"
}

#' Fingerprint of a classifier's training inputs
#'
#' What a saved model may be reused for: the labelled points it was fitted
#' on, the parameters that produced those labels and features, the tiles
#' they came from, and the package version. Each part is hashed separately
#' so a mismatch can say which part changed.
#'
#' @param feat The labelled features table (`X`, `Y`, `Z`, `label`).
#' @param params A named list of the parameters the labels and features
#'   depend on.
#' @param tiles Checksums (or other identities) of the point-cloud files.
#' @return A list: `hash` (of everything), `points`, `params`, `tiles`,
#'   `version` (each a hash), `n_points`, `vegrisk_version`.
#' @export
training_fingerprint <- function(feat, params = list(), tiles = NULL) {
  need <- c("X", "Y", "Z", "label")
  if (!all(need %in% names(feat))) {
    rlang::abort(sprintf("`feat` needs columns %s.", paste(need, collapse = ", ")))
  }
  pts <- data.frame(X = round(as.numeric(feat$X), 3), Y = round(as.numeric(feat$Y), 3),
                    Z = round(as.numeric(feat$Z), 3), label = as.character(feat$label),
                    stringsAsFactors = FALSE)
  ord <- order(pts$X, pts$Y, pts$Z, pts$label)
  pts <- pts[ord, , drop = FALSE]
  parts <- list(
    points = rlang::hash(list(X = pts$X, Y = pts$Y, Z = pts$Z, label = pts$label)),  # no row names
    params = rlang::hash(canonical_json(params)),
    tiles = rlang::hash(sort(as.character(tiles %||% character()))),
    version = rlang::hash(as.character(utils::packageVersion("vegrisk")))
  )
  c(list(hash = rlang::hash(unlist(parts))), parts,
    list(n_points = nrow(pts), vegrisk_version = as.character(utils::packageVersion("vegrisk"))))
}

#' Compare a saved training fingerprint with the current one
#'
#' @param saved,current Fingerprints from [training_fingerprint()].
#' @return `TRUE` when they match; otherwise a character vector naming the
#'   parts that differ (`points`, `params`, `tiles`, `version`).
#' @export
fingerprint_diff <- function(saved, current) {
  if (is.null(saved)) return("fingerprint (model predates it)")
  parts <- c("points", "params", "tiles", "version")
  bad <- parts[!vapply(parts, function(p) identical(saved[[p]], current[[p]]), TRUE)]
  if (length(bad) == 0 && identical(saved$hash, current$hash)) TRUE else if (length(bad)) bad else "hash"
}
