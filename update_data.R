#!/usr/bin/env Rscript
# update_data.R
# ============================================================================
# MASTER data pipeline — run this whenever you add (or re-scrape) a state JSON
# in data/. It is INCREMENTAL: it only does the expensive work for data that
# isn't already done, so you never re-geocode addresses or re-download polygons
# you already have.
#
#   Rscript update_data.R              # do the work
#   Rscript update_data.R --dry-run    # just report what's pending, change nothing
#
# What it does, in order:
#   1. Stacks every data/*_high_schools.json into one school table.
#   2. Geocodes ONLY the addresses not yet in data/school_addresses_geocode.csv
#      (plus any earlier failures), via Census -> ArcGIS -> OSM, and appends the
#      results back to that CSV. (The Shiny app joins schools to this CSV at
#      startup, so appending here is how new coordinates reach the app.)
#   3. Builds district + state polygons for ONLY the states not already in
#      data/district_polygons.rds, appending them (existing states untouched).
#   4. Writes data/master_data.csv — one flat CSV of every school's scraped
#      fields joined with its geocoded coordinates (the full dataset).
#   5. Prints a coverage summary and flags anything still missing.
#
# The geocoding cascade mirrors geo_coding_script.R; the polygon logic is reused
# from build_district_polygons.R (sourced as a module). Adding a state is now:
# drop its JSON in data/, run this script, done.
# ============================================================================

suppressWarnings(suppressMessages({
  library(jsonlite)
  library(dplyr)
  library(tidygeocoder)
}))

# Reuse the polygon module's functions (load_all_schools, build_district_polygons,
# ...) without triggering its standalone full rebuild. This also loads sf/tigris.
options(polygons.source.only = TRUE)
source("build_district_polygons.R")

GEO_CSV <- "data/school_addresses_geocode.csv"
args    <- commandArgs(trailingOnly = TRUE)
DRY_RUN <- any(args %in% c("--dry-run", "--dry", "-n"))

if (DRY_RUN) message(">>> DRY RUN — reporting only, no files will be changed.\n")

# ---------------------------------------------------------------------------
# 1. Load every school
# ---------------------------------------------------------------------------
schools <- load_all_schools()                      # from build_district_polygons.R
present_states <- sort(unique(schools$state))
message(sprintf("[1/4] Loaded %d schools across %d states: %s",
                nrow(schools), length(present_states),
                paste(present_states, collapse = ", ")))

# ---------------------------------------------------------------------------
# 2. Incremental geocoding
# ---------------------------------------------------------------------------
read_geo <- function() {
  if (!file.exists(GEO_CSV))
    return(data.frame(address = character(), latitude = numeric(),
                      longitude = numeric(), stringsAsFactors = FALSE))
  e <- read.csv(GEO_CSV, stringsAsFactors = FALSE, check.names = FALSE)
  for (col in c("latitude", "longitude"))
    if (col %in% names(e)) e[[col]] <- suppressWarnings(as.numeric(e[[col]]))
  e[, c("address", "latitude", "longitude")]
}

# Census -> ArcGIS -> OSM, geocoding only the addresses still missing at each
# step (same waterfall as geo_coding_script.R).
geocode_cascade <- function(addr) {
  df  <- data.frame(address = addr, stringsAsFactors = FALSE)
  res <- as.data.frame(tidygeocoder::geocode(
    df, address = address, method = "census", lat = "latitude", long = "longitude"))

  retry <- function(res, method) {
    miss <- which(is.na(res$latitude) | is.na(res$longitude))
    if (!length(miss)) return(res)
    message(sprintf("    %s: %d address(es) still missing", method, length(miss)))
    g <- as.data.frame(tidygeocoder::geocode(
      data.frame(address = res$address[miss], stringsAsFactors = FALSE),
      address = address, method = method, lat = "la", long = "lo"))
    res$latitude[miss]  <- dplyr::coalesce(res$latitude[miss],  g$la)
    res$longitude[miss] <- dplyr::coalesce(res$longitude[miss], g$lo)
    res
  }
  res <- retry(res, "arcgis")
  res <- retry(res, "osm")
  res[, c("address", "latitude", "longitude")]
}

existing <- read_geo()
all_addr <- unique(schools$address)
# Geocode addresses we've never seen, plus any earlier rows that still have no
# coordinates (a retry can recover transient failures).
never_seen <- setdiff(all_addr, existing$address)
failed     <- existing$address[is.na(existing$latitude) | is.na(existing$longitude)]
to_geocode <- intersect(union(never_seen, failed), all_addr)

message(sprintf("[2/4] Geocoding: %d new + %d earlier-missing = %d address(es) to do (%d already done).",
                length(never_seen), length(intersect(failed, all_addr)),
                length(to_geocode), length(setdiff(all_addr, to_geocode))))

if (length(to_geocode) == 0) {
  message("      Nothing to geocode.")
} else if (DRY_RUN) {
  message("      [dry run] would geocode ", length(to_geocode), " address(es) and append to ", GEO_CSV)
} else {
  geocoded <- tryCatch(geocode_cascade(to_geocode), error = function(e) {
    message("      !! geocoding failed: ", conditionMessage(e))
    NULL
  })
  if (!is.null(geocoded)) {
    keep     <- existing[!existing$address %in% to_geocode, , drop = FALSE]
    combined <- rbind(keep, geocoded)
    combined <- combined[!duplicated(combined$address), ]
    write.csv(combined, GEO_CSV, row.names = FALSE)
    got <- sum(!is.na(geocoded$latitude) & !is.na(geocoded$longitude))
    message(sprintf("      Geocoded %d/%d; %s now has %d rows (%d still missing coords).",
                    got, length(to_geocode), GEO_CSV, nrow(combined),
                    sum(is.na(combined$latitude) | is.na(combined$longitude))))
  }
}

# ---------------------------------------------------------------------------
# 3. Incremental polygons (only states without polygons yet)
# ---------------------------------------------------------------------------
existing_poly_states <- if (file.exists("data/district_polygons.rds"))
  unique(readRDS("data/district_polygons.rds")$state) else character(0)
new_poly_states <- setdiff(present_states, existing_poly_states)

message(sprintf("[3/4] Polygons: %d state(s) already built; %d new -> %s",
                length(existing_poly_states), length(new_poly_states),
                if (length(new_poly_states)) paste(new_poly_states, collapse = ", ") else "none"))

if (length(new_poly_states) == 0) {
  message("      Nothing to build.")
} else if (DRY_RUN) {
  message("      [dry run] would download + match polygons for: ",
          paste(new_poly_states, collapse = ", "))
} else {
  build_district_polygons(target_states = new_poly_states, append = TRUE)
}

# ---------------------------------------------------------------------------
# 4. Master dataset: data/master_data.csv
# ---------------------------------------------------------------------------
# One flat CSV combining every school's scraped fields with its geocoded
# coordinates — the same table the Shiny app assembles at startup. Regenerated
# on every run so it always reflects the current JSONs + geocodes.
final_geo <- read_geo()
master    <- dplyr::left_join(schools, final_geo[!duplicated(final_geo$address), ],
                              by = "address")
# Lead with the identifier + location columns, keep the rest in their JSON order.
front  <- intersect(c("state", "school_name", "district", "address",
                      "latitude", "longitude"), names(master))
master <- master[, c(front, setdiff(names(master), front))]

if (DRY_RUN) {
  message(sprintf("[4/4] [dry run] would write data/master_data.csv (%d rows x %d cols)",
                  nrow(master), ncol(master)))
} else {
  write.csv(master, "data/master_data.csv", row.names = FALSE, na = "")
  message(sprintf("[4/4] Wrote data/master_data.csv (%d rows x %d cols).",
                  nrow(master), ncol(master)))
}

# ---------------------------------------------------------------------------
# Coverage summary
# ---------------------------------------------------------------------------
with_coords <- sum(!is.na(master$latitude) & !is.na(master$longitude))
poly_states <- if (file.exists("data/district_polygons.rds"))
  unique(readRDS("data/district_polygons.rds")$state) else character(0)

message("\n================ SUMMARY ================")
message(sprintf("Schools .................. %d across %d states", nrow(schools), length(present_states)))
message(sprintf("Schools with coordinates . %d / %d (%.1f%%)",
                with_coords, nrow(schools), 100 * with_coords / nrow(schools)))
message(sprintf("States with polygons ..... %d / %d", length(poly_states), length(present_states)))
missing_poly <- setdiff(present_states, poly_states)
if (length(missing_poly))
  message("States still WITHOUT polygons: ", paste(missing_poly, collapse = ", "))
message("========================================")
if (DRY_RUN) message("(dry run — no files were changed)")
