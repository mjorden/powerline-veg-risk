#' @keywords internal
#' @importFrom data.table := .SD .N
#' @importFrom rlang %||%
"_PACKAGE"

.datatable.aware <- TRUE

utils::globalVariables(c(
  ".", "block", "cell", "fold", "height_m", "i.suspended", "label", "pred",
  "random_fold", "suspended", "zhi", "zlo", "Z", "Classification",
  "x", "y", "h", "priority", "importance", "feature", "value", "scheme", "class",
  "across", "z", "X", "Y", "s_m", "z_lo", "z_hi", "ground", "both", "certain",
  "wire", "line_id", "offset_m", "cx", "cy", "wmin", "encroach_lo_m2", "encroach_hi_m2", "prevalence", "ocx", "ocy", "zmin", "i.top", "gap", "nx", "ny", "i.cx", "i.cy", "x.z", "i.zmin", "zb", "i.zb", "screen", "hit", "angle", "share", "near", "lo", "hi", "run"
))
