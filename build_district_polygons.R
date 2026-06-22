# build_district_polygons.R
# ============================================================================
# Builds the Census school-district + state boundary polygons the app draws,
# matched to the U.S. News district names in data/*_high_schools.json.
#
# Outputs (committed so the Shiny app loads them instantly):
#   data/district_polygons.rds  - one row per matched (state, district)
#   data/state_polygons.rds     - one row per state (single outline)
#
# Two ways to use it:
#   * Standalone full rebuild (every state):   Rscript build_district_polygons.R
#   * As a reusable module (functions only) — e.g. from update_data.R:
#         options(polygons.source.only = TRUE)
#         source("build_district_polygons.R")
#         build_district_polygons(target_states = c("Idaho"), append = TRUE)
#
# Needs network access to the U.S. Census (via tigris). tigris caches downloads,
# so re-runs only re-fetch states it hasn't seen. If the .rds files are missing
# the app still boots (school markers only, no district areas).
# ============================================================================

suppressWarnings(suppressMessages({
  library(jsonlite)
  library(dplyr)
  library(sf)
  library(tigris)
}))

options(tigris_use_cache = TRUE)

TIGER_YEAR <- 2023                              # Census TIGER/Line vintage
state_abbr <- setNames(state.abb, state.name)   # "Utah" -> "UT" (50 states)
TYPE_PRIORITY <- c("unified", "secondary", "elementary")

# ---- Load every school from data/*.json (same stacking logic as global.R) ---
load_all_schools <- function() {
  files <- list.files("data", pattern = "_high_schools\\.json$", full.names = TRUE)
  if (length(files) == 0) stop("No data/*_high_schools.json files found.")
  bind_rows(lapply(files, function(path) {
    df <- fromJSON(path, simplifyDataFrame = TRUE)
    slug <- sub("_high_schools\\.json$", "", basename(path))
    df$state <- tools::toTitleCase(gsub("_", " ", slug))
    df
  }))
}

# ---- Name normalization ----------------------------------------------------
# Smooths over TIGER vs U.S. News naming quirks: case, punctuation, and the
# various "...School District / Public Schools / County / City" qualifiers.
normalize_district <- function(x) {
  x <- tolower(x)
  x <- gsub("[.,]", " ", x)
  x <- gsub("\\b(no\\.?\\s*)?[0-9]+\\b", " ", x)     # district numbering: "No. 58" or bare "58"
  # Census spells out district types that U.S. News drops from the short name
  # (e.g. Kansas "Abilene Unified School District 435" vs U.S. News "Abilene").
  x <- gsub("\\bunified\\b",      " ", x)
  x <- gsub("\\bconsolidated\\b", " ", x)
  x <- gsub("\\bpublic school district\\b", " ", x)
  x <- gsub("\\bpublic schools?\\b",        " ", x)
  x <- gsub("\\bschool system\\b",          " ", x)
  x <- gsub("\\bschool district\\b",        " ", x)
  x <- gsub("\\bschool dist\\b",            " ", x)
  x <- gsub("\\bdistrict\\b",               " ", x)
  x <- gsub("\\bschools\\b",                " ", x)
  x <- gsub("\\bcounty\\b",                 " ", x)
  x <- gsub("\\bcity\\b",                   " ", x)
  x <- gsub("\\s+",                         " ", x)
  trimws(x)
}

# Utah override map — preserved verbatim so Utah's 41 traditional districts keep
# matching exactly as verified.
usnews_to_census_district <- c(
  "Alpine District"        = "Alpine School District",
  "Beaver District"        = "Beaver School District",
  "Box Elder District"     = "Box Elder School District",
  "Cache District"         = "Cache County School District",
  "Canyons District"       = "Canyons School District",
  "Carbon District"        = "Carbon School District",
  "Daggett District"       = "Daggett School District",
  "Davis School District"  = "Davis County School District",
  "Duchesne District"      = "Duchesne School District",
  "Emery District"         = "Emery County School District",
  "Garfield District"      = "Garfield School District",
  "Grand District"         = "Grand School District",
  "Granite District"       = "Granite School District",
  "Iron District"          = "Iron School District",
  "Jordan District"        = "Jordan School District",
  "Juab District"          = "Juab School District",
  "Kane District"          = "Kane School District",
  "Logan City District"    = "Logan City School District",
  "Millard District"       = "Millard School District",
  "Morgan District"        = "Morgan School District",
  "Murray District"        = "Murray School District",
  "Nebo District"          = "Nebo School District",
  "North Sanpete District" = "North Sanpete School District",
  "North Summit District"  = "North Summit School District",
  "Ogden City District"    = "Ogden School District",
  "Park City District"     = "Park City School District",
  "Piute District"         = "Piute School District",
  "Provo District"         = "Provo School District",
  "Rich District"          = "Rich School District",
  "Salt Lake District"     = "Salt Lake City School District",
  "San Juan District"      = "San Juan School District",
  "Sevier District"        = "Sevier School District",
  "South Sanpete District" = "South Sanpete School District",
  "South Summit District"  = "South Summit School District",
  "Tintic District"        = "Tintic School District",
  "Tooele District"        = "Tooele School District",
  "Uintah District"        = "Uintah School District",
  "Wasatch District"       = "Wasatch County School District",
  "Washington District"    = "Washington County School District",
  "Wayne District"         = "Wayne School District",
  "Weber District"         = "Weber School District"
)

# ---- Download a state's districts (all three types, combined) ---------------
# Many states (CA, CT, ...) split high-school and elementary into separate
# districts, so unified-only would miss most U.S. News names. We pull all three
# and rank them so that when two share a normalized name we keep the more
# encompassing boundary (unified > secondary > elementary).
get_state_districts <- function(abbr) {
  parts <- lapply(TYPE_PRIORITY, function(ty) {
    out <- tryCatch(
      school_districts(state = abbr, type = ty, cb = TRUE,
                       year = TIGER_YEAR, progress_bar = FALSE),
      error = function(e) {
        message(sprintf("   [%s/%s] download failed: %s",
                        abbr, ty, conditionMessage(e)))
        NULL
      }
    )
    if (!is.null(out) && nrow(out) > 0) {
      out$dtype <- ty
      out[, c("NAME", "dtype")]   # standardize columns (geometry is sticky)
    } else NULL
  })
  parts <- parts[!vapply(parts, is.null, logical(1))]
  if (length(parts) == 0) return(NULL)
  do.call(rbind, parts)
}

# ---- Match one state's U.S. News districts to Census polygons ---------------
match_state <- function(state_name, schools, school_counts) {
  abbr <- state_abbr[[state_name]]
  if (is.null(abbr) || is.na(abbr)) {
    message(sprintf("[%s] no USPS abbreviation; skipping", state_name))
    return(NULL)
  }

  cen <- get_state_districts(abbr)
  if (is.null(cen)) {
    message(sprintf("[%s] no Census districts downloaded; skipping", state_name))
    return(NULL)
  }

  cen$norm <- normalize_district(cen$NAME)
  cen$prio <- match(cen$dtype, TYPE_PRIORITY)
  cen <- cen[order(cen$prio), ]          # higher-priority types first
  cen <- cen[!duplicated(cen$norm), ]    # one polygon per normalized name

  usnews_names <- sort(unique(schools$district[schools$state == state_name]))

  idx <- vapply(usnews_names, function(nm) {
    if (state_name == "Utah" && nm %in% names(usnews_to_census_district)) {
      cn <- usnews_to_census_district[[nm]]
      j  <- which(cen$NAME == cn)
      if (!length(j)) j <- which(cen$norm == normalize_district(cn))
    } else {
      j <- which(cen$norm == normalize_district(nm))
    }
    if (length(j)) j[1] else NA_integer_
  }, integer(1))

  keep    <- !is.na(idx)
  total   <- length(usnews_names)
  matched <- sum(keep)
  message(sprintf("[%-14s] matched %d / %d districts", state_name, matched, total))
  if (matched < total) {
    um <- usnews_names[!keep]
    message("   unmatched (", length(um), "): ",
            paste(utils::head(um, 15), collapse = "; "),
            if (length(um) > 15) " ..." else "")
  }
  if (!matched) return(NULL)

  out <- cen[idx[keep], ]
  out$state           <- state_name
  out$usnews_district <- usnews_names[keep]
  out$n_schools <- school_counts$n_schools[match(
    paste(state_name, out$usnews_district),
    paste(school_counts$state, school_counts$district)
  )]
  out[, c("state", "usnews_district", "n_schools")]   # geometry sticky
}

# ---- True Census state outlines for a set of states -------------------------
build_state_outlines <- function(target_states, fallback_districts = NULL) {
  out <- tryCatch({
    st <- states(cb = TRUE, year = TIGER_YEAR, progress_bar = FALSE)
    st <- st[st$NAME %in% target_states, ]
    st$state <- st$NAME
    st_transform(st[, "state"], crs = 4326)
  }, error = function(e) {
    message("states() download failed (", conditionMessage(e),
            "); dissolving district polygons per state instead.")
    if (is.null(fallback_districts) || nrow(fallback_districts) == 0) return(NULL)
    fallback_districts %>% group_by(state) %>%
      summarise(.groups = "drop") %>% select(state)
  })
  if (is.null(out)) return(NULL)
  out[, "state"]
}

# Merge freshly-built polygons for `todo` states into an existing .rds: drop any
# existing rows for those states (so a re-run refreshes them) and rbind the new.
# With append = FALSE, return only the new polygons (full rebuild).
.merge_polys <- function(path, new_polys, todo, append) {
  if (!append || !file.exists(path)) return(new_polys)
  old <- readRDS(path)
  old <- old[!old$state %in% todo, ]
  if (is.null(new_polys) || nrow(new_polys) == 0) return(old)
  if (nrow(old) == 0) return(new_polys)
  rbind(old, st_transform(new_polys, st_crs(old)))
}

# ---- Main entry: build (or incrementally extend) the polygon files ----------
# target_states = NULL  -> every state present in data/.
#               = c(..) -> only those states.
# append = TRUE -> merge into the existing .rds files, replacing rows for the
#   target states (existing states are left untouched — nothing re-downloaded).
build_district_polygons <- function(target_states = NULL, append = FALSE) {
  schools       <- load_all_schools()
  school_counts <- schools %>% count(state, district, name = "n_schools")
  present       <- sort(unique(schools$state))
  todo <- if (is.null(target_states)) present else intersect(target_states, present)

  if (length(todo) == 0) {
    message("build_district_polygons(): no matching states to process.")
    return(invisible(NULL))
  }
  message(sprintf("Building polygons for %d state(s): %s",
                  length(todo), paste(todo, collapse = ", ")))

  parts  <- lapply(todo, function(s) match_state(s, schools, school_counts))
  parts  <- parts[!vapply(parts, is.null, logical(1))]
  new_dp <- if (length(parts)) st_transform(do.call(rbind, parts), 4326) else NULL
  new_sp <- build_state_outlines(todo, new_dp)

  dir.create("data", showWarnings = FALSE)
  district_polygons <- .merge_polys("data/district_polygons.rds", new_dp, todo, append)
  state_polygons    <- .merge_polys("data/state_polygons.rds",    new_sp, todo, append)

  if (is.null(district_polygons) || nrow(district_polygons) == 0)
    stop("No districts matched — nothing written.")

  saveRDS(district_polygons, "data/district_polygons.rds")
  saveRDS(state_polygons,    "data/state_polygons.rds")

  per_state <- as.data.frame(table(district_polygons$state))
  names(per_state) <- c("state", "polygons")
  message(sprintf("\n--- district_polygons.rds: %d polygons across %d state(s) ---",
                  nrow(district_polygons), length(unique(district_polygons$state))))
  print(per_state, row.names = FALSE)
  message(sprintf("--- state_polygons.rds: %d state outline(s) ---", nrow(state_polygons)))
  if ("Utah" %in% district_polygons$state) {
    ut_n <- sum(district_polygons$state == "Utah")
    message(sprintf("Utah check: %d polygons (expected 41).%s", ut_n,
                    if (ut_n != 41) "  *** review Utah override/matches ***" else ""))
  }
  invisible(list(district_polygons = district_polygons,
                 state_polygons    = state_polygons))
}

# ---- Standalone execution (full rebuild of every state) ---------------------
# Skipped when sourced as a module (update_data.R sets the option first).
if (!isTRUE(getOption("polygons.source.only"))) {
  build_district_polygons(target_states = NULL, append = FALSE)
}
