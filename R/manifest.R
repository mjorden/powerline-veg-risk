# Run records (#54): what code, environment, configuration and inputs
# produced a set of outputs, written last and atomically, so a run
# directory without a manifest is known to be incomplete and a reader can
# check that every table came from the same run.

#' The software environment of a run
#'
#' @param packages Packages whose versions to record.
#' @return A list: `r_version`, `platform`, `os`, `locale`, `tz`,
#'   `packages` (named versions), `sf_ext` (GDAL, GEOS, PROJ versions),
#'   `proj_network`, `threads` (data.table, lidR, cores), `rng_kind`.
#' @export
run_environment <- function(packages = c("vegrisk", "sf", "terra", "lidR", "ranger", "data.table",
                                         "httr2", "FNN", "lwgeom", "units")) {
  ver <- vapply(packages, function(p) {
    tryCatch(as.character(utils::packageVersion(p)), error = function(e) NA_character_)
  }, "")
  ext <- tryCatch(sf::sf_extSoftVersion(), error = function(e) character())
  list(
    r_version = R.version.string,
    platform = R.version$platform,
    os = paste(Sys.info()[["sysname"]], Sys.info()[["release"]]),
    locale = Sys.getlocale("LC_COLLATE"),
    tz = Sys.timezone(),
    packages = as.list(ver),
    sf_ext = as.list(ext[intersect(c("GDAL", "GEOS", "PROJ", "proj.4"), names(ext))]),
    proj_network = Sys.getenv("PROJ_NETWORK", unset = ""),
    threads = list(data_table = data.table::getDTthreads(), lidr = lidR::get_lidr_threads(),
                   cores = parallel::detectCores()),
    rng_kind = paste(RNGkind(), collapse = " / ")
  )
}

#' Identity of the git checkout a run used
#'
#' @param dir A directory inside the repository.
#' @return A list: `sha` (short), `dirty` (uncommitted changes to tracked
#'   files), `diff_md5` (MD5 of `git diff` when dirty, else `NA`),
#'   `remote`; every field `NA` outside a repository.
#' @export
git_state <- function(dir = ".") {
  g <- function(...) tryCatch(
    suppressWarnings(system2("git", c("-C", shQuote(dir), ...), stdout = TRUE, stderr = FALSE)),
    error = function(e) character())
  sha <- g("rev-parse", "--short", "HEAD")
  if (!length(sha)) return(list(sha = NA_character_, dirty = NA, diff_md5 = NA_character_, remote = NA_character_))
  status <- g("status", "--porcelain", "--untracked-files=no")
  dirty <- length(status) > 0
  diff_md5 <- if (dirty) {
    tmp <- tempfile()
    writeLines(g("diff"), tmp)
    unname(tools::md5sum(tmp))
  } else NA_character_
  remote <- g("remote", "get-url", "origin")
  list(sha = sha[1], dirty = dirty, diff_md5 = diff_md5,
       remote = if (length(remote)) remote[1] else NA_character_)
}

#' Record of an output or input file
#'
#' @param path File path.
#' @param table Optional data frame the file holds, for row and column
#'   records.
#' @return A list: `file`, `bytes`, `md5`, and with `table` `rows` and
#'   `columns` (name and class).
#' @export
file_record <- function(path, table = NULL) {
  rec <- list(file = basename(path), bytes = file.size(path), md5 = unname(tools::md5sum(path)))
  if (!is.null(table)) {
    if (inherits(table, "sf")) table <- sf::st_drop_geometry(table)
    rec$rows <- nrow(table)
    rec$columns <- lapply(names(table), function(n) list(name = n, class = class(table[[n]])[1]))
  }
  rec
}

#' Resolved default values of a function's arguments
#'
#' Records the defaults a run relied on without naming them, so a later
#' change to a default is visible in the manifest.
#'
#' @param f A function.
#' @param args Argument names to record; by default every argument with a
#'   default.
#' @return A named list of evaluated defaults (`NULL` where none).
#' @export
defaults_of <- function(f, args = NULL) {
  fm <- formals(f)
  # An argument with no default holds the empty symbol, which cannot be
  # bound to a variable, so it is tested in place.
  no_default <- function(a) is.symbol(fm[[a]]) && !nzchar(as.character(fm[[a]]))
  if (is.null(args)) args <- names(fm)[!vapply(names(fm), no_default, TRUE)]
  out <- lapply(args, function(a) {
    if (no_default(a)) return(NULL)
    tryCatch(eval(fm[[a]], envir = environment(f)), error = function(e) deparse(fm[[a]]))
  })
  stats::setNames(out, args)
}

#' Write a run manifest atomically
#'
#' The manifest is the completion marker: it is written to a temporary
#' file and renamed into place last, so a run directory without one is
#' known to be incomplete.
#'
#' @param manifest A list.
#' @param run_dir The run directory.
#' @return The manifest path, invisibly.
#' @export
write_manifest <- function(manifest, run_dir) {
  path <- file.path(run_dir, "manifest.json")
  tmp <- paste0(path, ".tmp")
  jsonlite::write_json(manifest, tmp, auto_unbox = TRUE, pretty = TRUE, digits = NA, null = "null",
                       na = "null", POSIXt = "ISO8601", force = TRUE)
  if (!file.rename(tmp, path)) rlang::abort(sprintf("could not replace %s", path))
  invisible(path)
}

#' Open a finished run
#'
#' Resolves the run directory (the latest by default, from `latest.txt`),
#' refuses one with no manifest or a manifest whose status is not
#' `complete`, and checks that every table carries the manifest's run id.
#'
#' @param site_dir The site's output directory (`output/<site>`).
#' @param run_id A run id, or `NULL` for the latest.
#' @param check Tables to verify: names of GeoPackage files in the run
#'   directory whose `run_id` column must match.
#' @return A list: `run_dir`, `manifest`, `run_id`.
#' @export
read_run <- function(site_dir, run_id = NULL, check = c("segments.gpkg", "trees.gpkg")) {
  if (is.null(run_id)) {
    latest <- file.path(site_dir, "latest.txt")
    if (!file.exists(latest)) rlang::abort(sprintf("%s has no latest.txt; run the site first.", site_dir))
    run_id <- trimws(readLines(latest, warn = FALSE)[1])
  }
  run_dir <- file.path(site_dir, "runs", run_id)
  mpath <- file.path(run_dir, "manifest.json")
  if (!file.exists(mpath)) {
    rlang::abort(sprintf("%s has no manifest.json: the run did not complete.", run_dir))
  }
  manifest <- jsonlite::read_json(mpath)
  if (!identical(manifest$status, "complete")) {
    rlang::abort(sprintf("run %s has status '%s', not complete.", run_id, manifest$status))
  }
  for (f in check) {
    p <- file.path(run_dir, f)
    if (!file.exists(p)) next
    ids <- unique(sf::st_read(p, quiet = TRUE)$run_id)
    if (!identical(ids, run_id)) {
      rlang::abort(sprintf("%s carries run id %s, not %s.", f, paste(ids, collapse = ", "), run_id))
    }
  }
  list(run_dir = run_dir, manifest = manifest, run_id = run_id)
}
