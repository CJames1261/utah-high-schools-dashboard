# build_district_polygons.R
# ============================================================================
# One-time builder for data/district_polygons.rds — the combined Census school
# district boundaries for every state present in data/*_high_schools.json,
# matched to the U.S. News district names the app uses.
#
# RE-RUN THIS whenever you add a new state JSON to data/:
#     Rscript build_district_polygons.R
#
# Needs network access to the U.S. Census (via tigris). The output .rds is
# committed to the repo so the Shiny app (global.R) loads it instantly at
# RE-RUN THIS whenever you add a new state JSON to data/:
#     Rscript build_district_polygons.R
#
# Needs network access to the U.S. Census (via tigris). The output .rds is
# committed to the repo so the Shiny app (global.R) loads it instantly at
# startup with NO live downloads. If the file is missing the app still boots,
# it just shows school markers without district areas.
# ============================================================================

library(jsonlite)
library(dplyr)
library(sf)
library(tigris)

options(tigris_use_cache = TRUE)

TIGER_YEAR <- 2023   # Census TIGER/Line vintage for the boundaries

# ---- 1. Load all schools (same stacking logic as global.R) -----------------
school_files <- list.files("data", pattern = "_high_schools\\.json$",
                           full.names = TRUE)
if (length(school_files) == 0) stop("No data/*_high_schools.json files found.")

schools <- bind_rows(lapply(school_files, function(path) {
  df <- fromJSON(path, simplifyDataFrame = TRUE)
  slug <- sub("_high_schools\\.json$", "", basename(path))
  df$state <- tools::toTitleCase(gsub("_", " ", slug))
  df
}))

states_present <- sort(unique(schools$state))
school_counts  <- schools %>% count(state, district, name = "n_schools")
message(sprintf("Building district polygons for %d state(s): %s",
                length(states_present), paste(states_present, collapse = ", ")))

# state name -> USPS abbreviation (base R datasets cover all 50 states).
state_abbr <- setNames(state.abb, state.name)

# ---- 2. Name normalization (identical to the old global.R helper) ----------
# Smooths over TIGER vs U.S. News naming quirks: case, and trailing
# "School District" / "District" / "County" / "City" tokens.
normalize_district <- function(x) {
  x <- tolower(x)
  x <- gsub("[.,]", " ", x)                          # Dist. / St. -> word forms
  # Strip the various "...School District / Public Schools / School System"
  # suffixes (longest phrases first) plus the County/City qualifiers, so the
  # U.S. News and Census spellings of the same district collapse to one token.
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

# Utah override map — preserved verbatim from the original global.R so Utah's
# 41 traditional districts keep matching exactly as they did before.
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

# ---- 3. Download a state's districts (all three types, combined) ------------
# Many states (CA, CT, ...) split high-school and elementary into separate
# districts, so unified-only would miss most U.S. News names. We pull all three
# and rank them so that when two types share a normalized name we keep the more
# encompassing boundary (unified > secondary > elementary).
TYPE_PRIORITY <- c("unified", "secondary", "elementary")

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

# ---- 4. Match one state's U.S. News districts to Census polygons ------------
match_state <- function(state_name) {
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

# ---- 5. Build, combine, save -----------------------------------------------
parts <- lapply(states_present, match_state)
parts <- parts[!vapply(parts, is.null, logical(1))]
if (length(parts) == 0) stop("No districts matched for any state — aborting.")

district_polygons <- do.call(rbind, parts)
district_polygons <- st_transform(district_polygons, crs = 4326)

dir.create("data", showWarnings = FALSE)
saveRDS(district_polygons, "data/district_polygons.rds")

# ---- 6. Summary + Utah sanity check ----------------------------------------
per_state <- as.data.frame(table(district_polygons$state))
names(per_state) <- c("state", "polygons")
message("\n--- district_polygons.rds written ---")
print(per_state, row.names = FALSE)
message(sprintf("Total: %d district polygons across %d state(s).",
                nrow(district_polygons), length(unique(district_polygons$state))))

ut_n <- sum(district_polygons$state == "Utah")
message(sprintf("Utah check: %d polygons (expected 41).", ut_n))
if (ut_n != 41) {
  message("WARNING: Utah polygon count changed from the expected 41 — review the ",
          "Utah override map and Census name matches above.")
}
