# global.R
# Loaded once when the app starts. Shared by ui.R and server.R.

# ---- Packages ----------------------------------------------------------------
# One-time install (note tigris/sf are new since the previous version):
#   install.packages(c("shiny", "leaflet", "dplyr", "htmltools",
#                      "jsonlite", "readr", "tigris", "sf"))

library(shiny)
library(leaflet)
library(dplyr)
library(htmltools)
library(jsonlite)
library(readr)
library(tigris)
library(sf)

# UI / theming
library(bslib)
library(bsicons)
library(shinyjs)

# Compare tab
library(ggplot2)
library(plotly)
library(DT)

# tigris caches downloaded shapefiles so the Utah district polygons are only
# fetched from the Census on first run (~30 sec). Subsequent runs are instant.
options(tigris_use_cache = TRUE)

# Data vintage surfaced to users in the KPI bar and district hover cards. All
# six ranking inputs (state assessments, AP/IB exams, graduation) are from the
# 2022-2023 school year, so a single label applies to the whole scorecard.
DATA_YEAR <- "2022-2023"

# ---- Load school data --------------------------------------------------------
# The full dataset — every school's scraped fields joined to its geocoded
# coordinates — is pre-built into data/master_data.csv by update_data.R (run
# that whenever you add a state). Reading the one master CSV keeps this file
# simple; the stacking / geocoding / joining all lives in the pipeline.
# guess_max = Inf so sparse numeric columns (e.g. graduation_rate, which many
# rows leave blank) are still typed numeric, not logical.
master_path <- "data/master_data.csv"
if (!file.exists(master_path))
  stop("data/master_data.csv not found — run `Rscript update_data.R` to build it.")

schools <- read_csv(master_path, show_col_types = FALSE, guess_max = Inf)

# ---- Headline counts (surfaced in the navbar + scope block) ------------------
# The same district name can appear in more than one state (e.g. a "Washington
# County" district exists in several states), so districts are counted per
# (state, district) pair rather than by bare name.
n_schools_total <- nrow(schools)
n_states        <- length(unique(schools$state))
n_districts     <- nrow(dplyr::distinct(schools, state, district))

message(sprintf("Loaded %d schools across %d state(s), %d districts. %d without coordinates.",
                n_schools_total, n_states, n_districts,
                sum(is.na(schools$latitude))))

# Per-state summary for the DEFAULT overview map: the total number of high
# schools in each state and a single bubble position (the mean of that state's
# school coordinates). The overview shows one count bubble per state instead of
# every individual school marker; the per-school markers only appear once a
# state/district is selected.
state_summary <- schools %>%
  dplyr::group_by(state) %>%
  dplyr::summarise(
    n_schools = dplyr::n(),
    lng       = mean(longitude, na.rm = TRUE),
    lat       = mean(latitude,  na.rm = TRUE),
    .groups   = "drop"
  )

# ---- Proficiency ranking (Map tab right-side drill-down table) ---------------
# Ranks any grouping of schools by an equal-weighted average of reading, math,
# and science proficiency — the three core-subject KPIs. Graduation and AP are
# deliberately excluded (a diploma / an AP sitting doesn't certify proficiency).
# Because all three inputs are the same "% proficient" unit, the composite
# "Proficiency Index" is simply their mean, so it stays on the readable 0-100
# scale.
#
# `group_col` is the column to rank by: "state" for the top level, "district"
# within a chosen state, or "school_name" within a chosen district — the Map
# tab walks state -> district -> school using this one helper, so the index is
# computed identically at every level.
#
# Missing-subject handling (important): a subject with no numeric data for a
# group averages to NaN — either because no school reports it (e.g. a state that
# doesn't test science, like Colorado) or because it's only given as a range
# (">=80%", non-numeric). `rowMeans(..., na.rm = TRUE)` drops such a subject
# from BOTH the numerator and the denominator, so a no-science group divides by
# 2, not 3. A group with no proficiency data at all gets NA (sorts last,
# unranked) rather than a divide-by-zero.
compute_prof_ranking <- function(df, group_col) {
  df %>%
    dplyr::group_by(dplyr::across(dplyr::all_of(group_col))) %>%
    dplyr::summarise(
      n_schools = dplyr::n(),
      reading   = mean(reading_proficiency, na.rm = TRUE),
      math      = mean(math_proficiency,    na.rm = TRUE),
      science   = mean(science_proficiency, na.rm = TRUE),
      .groups   = "drop"
    ) %>%
    dplyr::mutate(
      n_subjects = (!is.nan(reading)) + (!is.nan(math)) + (!is.nan(science)),
      prof_index = ifelse(n_subjects == 0, NA_real_,
                          rowMeans(cbind(reading, math, science), na.rm = TRUE))
    ) %>%
    dplyr::arrange(dplyr::desc(prof_index)) %>%
    dplyr::mutate(rank = ifelse(is.na(prof_index), NA_integer_, dplyr::row_number()))
}

# Top-level table: every state ranked. (District/school levels are computed
# on demand in server.R as the user drills in.)
state_rankings <- compute_prof_ranking(schools, "state")

# ---- Data coverage notes (the "why are some values blank?" info modal) -------
# For each state, which KPIs have NO numeric data at all — i.e. U.S. News simply
# doesn't publish them for that state (verified against the source pages: e.g.
# Connecticut shows only a proficiency rank, Colorado/Hawaii omit science).
# Computed from the data so the notes stay accurate as states are added.
kpi_labels <- c(
  overall_score       = "Overall Score",        state_rank      = "State Rank",
  national_rank       = "National Rank",         ap_taken_pct    = "AP Participation",
  ap_passed_pct       = "AP Pass Rate",          math_proficiency    = "Math Proficiency",
  reading_proficiency = "Reading Proficiency",   science_proficiency = "Science Proficiency",
  graduation_rate     = "Graduation Rate"
)
coverage_notes <- lapply(sort(unique(schools$state)), function(st) {
  d    <- schools[schools$state == st, ]
  miss <- names(kpi_labels)[vapply(names(kpi_labels),
                                   function(k) all(is.na(d[[k]])), logical(1))]
  # % of the state's schools that U.S. News actually ranks (have an overall score)
  pct_ranked <- round(100 * mean(!is.na(d$overall_score)))
  list(state = st, n = nrow(d), pct_ranked = pct_ranked,
       missing = unname(kpi_labels[miss]))
})

# ---- District boundary polygons (pre-built; see build_district_polygons.R) ---
# District areas for every state are matched to Census TIGER boundaries offline
# by build_district_polygons.R and saved to data/district_polygons.rds, so the
# app loads them instantly with no live Census downloads. Re-run that script
# whenever you add a new state JSON. If the file is absent the app still runs —
# it just shows school markers without the shaded district areas.
#
# Schema: state, usnews_district, n_schools, geometry (one row per matched
# (state, district) — keyed by state so same-named districts in different
# states stay distinct).
poly_path <- "data/district_polygons.rds"
if (file.exists(poly_path)) {
  district_polygons <- readRDS(poly_path)
  message(sprintf("Loaded %d district polygons across %d state(s) from %s.",
                  nrow(district_polygons),
                  length(unique(district_polygons$state)), poly_path))
} else {
  # Empty sf with the expected schema so downstream code (subsetting, st_bbox,
  # the polygon observer) never errors when the file hasn't been built yet.
  district_polygons <- sf::st_sf(
    state           = character(0),
    usnews_district = character(0),
    n_schools       = integer(0),
    geometry        = sf::st_sfc(crs = 4326)
  )
  message("NOTE: ", poly_path, " not found — run `Rscript build_district_polygons.R` ",
          "to generate district areas. Showing school markers only for now.")
}

# State outline polygons drive the DEFAULT view: one single-color shape per
# state with a state-average hover card. The map only drills into the individual
# district polygons above once a state is clicked or the state filter narrows to
# a subset. Built by the same script; falls back to dissolving the district
# polygons per state, then to an empty sf, if the file isn't present.
state_poly_path <- "data/state_polygons.rds"
if (file.exists(state_poly_path)) {
  state_polygons <- readRDS(state_poly_path)
} else if (nrow(district_polygons) > 0) {
  state_polygons <- suppressWarnings(
    district_polygons %>% dplyr::group_by(state) %>%
      dplyr::summarise(.groups = "drop")
  )[, "state"]
} else {
  state_polygons <- sf::st_sf(state = character(0),
                              geometry = sf::st_sfc(crs = 4326))
}
message(sprintf("Loaded %d state outline polygon(s).", nrow(state_polygons)))

# ---- Color palettes ----------------------------------------------------------
# Primary map palette: one distinct color per STATE. At national scale (dozens
# of states, 1,000+ districts) coloring polygons and markers by state is what
# reads clearly when the map is zoomed out — the polygon hover card and detail
# panel carry the district-level detail. A hue-stepped rainbow guarantees every
# state gets a real, distinct color (not interpolated near-white) as more
# states are added; the shuffle keeps alphabetically-adjacent states from
# sharing a hue. Seed makes the assignment reproducible.
all_states <- sort(unique(schools$state))
set.seed(42)
state_colors <- rainbow(length(all_states), s = 0.65, v = 0.90)
state_colors <- state_colors[sample(length(state_colors))]
state_pal <- colorFactor(palette = state_colors, domain = all_states)

# Secondary palette kept only for the (unchanged) Compare Schools tab, which
# still tints its bars per district. Keyed on every district name nationwide.
all_districts <- sort(unique(schools$district))
set.seed(42)
district_colors <- rainbow(length(all_districts), s = 0.7, v = 0.85)
district_colors <- district_colors[sample(length(district_colors))]
district_pal <- colorFactor(
  palette = district_colors,
  domain  = all_districts
)

# ---- Helpers -----------------------------------------------------------------
fmt_pct  <- function(x) ifelse(is.na(x), "n/a", paste0(x, "%"))
fmt_avg  <- function(x) if (is.na(x) || is.nan(x)) "n/a" else sprintf("%.1f%%", x)
fmt_rank <- function(x) ifelse(is.na(x), "n/a", paste0("#", format(x, big.mark = ",")))
fmt_score<- function(x) ifelse(is.na(x), "n/a", paste0(x, "/100"))

# Prefer numeric percent; fall back to U.S. News raw string when bucketed.
fmt_grad <- function(num, raw) {
  if (!is.na(num)) return(paste0(num, "%"))
  if (!is.na(raw) && nzchar(raw)) return(raw)
  "n/a"
}

# Average scorecard for a data frame (NAs ignored, so bucketed values are
# silently excluded — which is correct: ">= 80%" isn't a number).
compute_avg_scorecard <- function(df) {
  if (nrow(df) == 0) return(NULL)
  list(
    n          = nrow(df),
    ap_taken   = mean(df$ap_taken_pct,        na.rm = TRUE),
    ap_passed  = mean(df$ap_passed_pct,       na.rm = TRUE),
    math       = mean(df$math_proficiency,    na.rm = TRUE),
    reading    = mean(df$reading_proficiency, na.rm = TRUE),
    science    = mean(df$science_proficiency, na.rm = TRUE),
    graduation = mean(df$graduation_rate,     na.rm = TRUE)
  )
}

# HTML popup for a single school row (used by the map markers)
school_popup <- function(row) {
  HTML(paste0(
    "<div style='font-family:sans-serif; min-width:240px;'>",
      "<h4 style='margin:0 0 4px 0;'>", htmlEscape(row$school_name), "</h4>",
      "<div style='color:#475569; font-size: 12px;'>", htmlEscape(row$district), "</div>",
      "<div style='color:#334155; margin:4px 0 8px 0;'>", htmlEscape(row$address), "</div>",
      "<table style='font-size: 13px; border-collapse:collapse;'>",
        "<tr><td><b>Overall Score</b></td><td>", fmt_score(row$overall_score), "</td></tr>",
        "<tr><td><b>Utah Rank</b></td><td>",     fmt_rank(row$state_rank),    "</td></tr>",
        "<tr><td><b>National Rank</b></td><td>", fmt_rank(row$national_rank), "</td></tr>",
        "<tr><td><b>Took AP</b></td><td>",       fmt_pct(row$ap_taken_pct),   "</td></tr>",
        "<tr><td><b>Passed AP</b></td><td>",     fmt_pct(row$ap_passed_pct),  "</td></tr>",
        "<tr><td><b>Math</b></td><td>",          fmt_pct(row$math_proficiency),    "</td></tr>",
        "<tr><td><b>Reading</b></td><td>",       fmt_pct(row$reading_proficiency), "</td></tr>",
        "<tr><td><b>Science</b></td><td>",       fmt_pct(row$science_proficiency), "</td></tr>",
        "<tr><td><b>Graduation</b></td><td>",    fmt_grad(row$graduation_rate, row$graduation_rate_raw), "</td></tr>",
      "</table>",
    "</div>"
  ))
}

# ---- District hover scorecard (polygon tooltips) -----------------------------
# Each traditional district polygon gets a hover tooltip styled like the KPI
# panel at the top of the map: a titled card with a 3x2 grid of the district's
# average scores. Built once at startup (data is static) for performance, and
# uses the same compute_avg_scorecard() helper as the top KPI panel so the
# numbers always agree.

# Pre-render the Bootstrap icon SVGs once, rather than regenerating them for
# every district x metric combination inside the loop below.
hover_icons <- vapply(
  c("geo-alt-fill", "pencil-square", "patch-check-fill",
    "calculator", "book", "lightbulb", "mortarboard-fill", "calendar3"),
  function(n) as.character(bsicons::bs_icon(n)),
  character(1)
)

# One stat cell: icon + uppercase label, then the big value beneath.
district_hover_stat <- function(icon, label, value) {
  is_na <- identical(value, "n/a")
  sprintf(
    "<div class='district-hover-stat'>
       <div class='district-hover-stat-head'>%s<span>%s</span></div>
       <div class='district-hover-stat-value%s'>%s</div>
     </div>",
    hover_icons[[icon]], label,
    if (is_na) " na" else "", value
  )
}

# Full KPI scorecard card for one district (name + averaged scores).
district_kpi_card <- function(name, avg) {
  if (is.null(avg)) {
    meta <- ""
    body <- "<div style='grid-column:1/-1; padding:14px; color:#64748b; font-size: 13px;'>No scorecard data for this district.</div>"
    foot <- ""
  } else {
    meta <- sprintf(
      "<span class='data-year-pill'>%s%s</span><span class='district-hover-count'>Average of %d school%s</span>",
      hover_icons[["calendar3"]], DATA_YEAR,
      avg$n, if (avg$n == 1) "" else "s"
    )
    vals <- c(
      fmt_avg(avg$ap_taken), fmt_avg(avg$ap_passed), fmt_avg(avg$math),
      fmt_avg(avg$reading),  fmt_avg(avg$science),   fmt_avg(avg$graduation)
    )
    body <- paste0(
      district_hover_stat("pencil-square",    "AP Taken",   vals[1]),
      district_hover_stat("patch-check-fill", "AP Passed",  vals[2]),
      district_hover_stat("calculator",       "Math",       vals[3]),
      district_hover_stat("book",             "Reading",    vals[4]),
      district_hover_stat("lightbulb",        "Science",    vals[5]),
      district_hover_stat("mortarboard-fill", "Graduation", vals[6])
    )
    # Footnote explaining any 'n/a' cells: U.S. News reports some values as
    # ranges/buckets (e.g. '>= 80%'), which aren't numeric and are excluded
    # from the average — the same rule noted in the control-panel scope block.
    n_na <- sum(vals == "n/a")
    foot <- if (n_na == 0) "" else sprintf(
      "<div class='district-hover-foot'>%s</div>",
      if (n_na == 6)
        "No numeric scores — U.S. News reports this district's values as ranges."
      else
        "n/a = reported by U.S. News as a range, excluded from the average."
    )
  }
  # data-dh-district lets the server hide this specific card via injected CSS
  # when its district is the active filter (the top KPI panel already shows
  # the same averages). Distinct from the legend's data-district attribute.
  htmltools::HTML(sprintf(
    "<div class='district-hover-card' data-dh-district='%s'>
       <div class='district-hover-head'>
         <div class='district-hover-title'>%s<span class='district-hover-titletext'><span class='district-hover-name'>%s</span><span class='district-hover-sub'>Average scores</span></span></div>
         <div class='district-hover-meta'>%s</div>
       </div>
       <div class='district-hover-body'>%s</div>
       %s
     </div>",
    htmltools::htmlEscape(name), hover_icons[["geo-alt-fill"]],
    htmltools::htmlEscape(name), meta, body, foot
  ))
}

# One KPI card per polygon, in the same row order as district_polygons. Filter
# by BOTH state and district so a district name that also exists in another
# state only averages the schools that belong to this polygon's state.
polygon_hover_labels <- lapply(seq_len(nrow(district_polygons)), function(i) {
  st <- district_polygons$state[i]
  nm <- district_polygons$usnews_district[i]
  df <- schools[schools$state == st & schools$district == nm, ]
  district_kpi_card(nm, compute_avg_scorecard(df))
})

# One KPI card per STATE (shown on the default state choropleth), averaging
# every school in the state. Reuses the same card component as the district
# hover so the two zoom levels look consistent.
state_hover_labels <- lapply(seq_len(nrow(state_polygons)), function(i) {
  st <- state_polygons$state[i]
  df <- schools[schools$state == st, ]
  district_kpi_card(st, compute_avg_scorecard(df))
})

# Default / reset map view. We frame the BULK of the schools (2nd-98th
# percentile of coordinates) rather than the raw min/max, so a handful of
# far-flung points — e.g. Alaska's Aleutian Islands near the antimeridian —
# don't blow the initial view out across the Pacific. Every school is still
# plotted; outliers are reachable by panning or by selecting that state (which
# auto-fits to it). Data-driven, so it re-frames as states are added; falls
# back to the continental U.S. if no coordinates are present yet.
.bbox_lat <- schools$latitude[is.finite(schools$latitude)]
.bbox_lng <- schools$longitude[is.finite(schools$longitude)]
DATA_BBOX <- if (length(.bbox_lat) > 0 && length(.bbox_lng) > 0) {
  qlat <- stats::quantile(.bbox_lat, c(0.02, 0.98), names = FALSE)
  qlng <- stats::quantile(.bbox_lng, c(0.02, 0.98), names = FALSE)
  list(lng1 = qlng[1], lat1 = qlat[1], lng2 = qlng[2], lat2 = qlat[2])
} else {
  list(lng1 = -125, lat1 = 24, lng2 = -66.5, lat2 = 49.5)
}
rm(.bbox_lat, .bbox_lng)

# Null-coalescing helper used by the debug loggers in server.R.
`%||%` <- function(a, b) if (is.null(a)) b else a

# ---- Comparable metrics (Compare Schools tab) --------------------------------
# Each entry: column name -> display label (and whether higher is better).
compare_metrics <- list(
  overall_score        = list(label = "Overall Score",         unit = "/100", higher_better = TRUE),
  state_rank           = list(label = "Utah Ranking",           unit = "",     higher_better = FALSE),
  national_rank        = list(label = "National Ranking",       unit = "",     higher_better = FALSE),
  ap_taken_pct         = list(label = "AP Exam Participation",  unit = "%",    higher_better = TRUE),
  ap_passed_pct        = list(label = "AP Exam Pass Rate",      unit = "%",    higher_better = TRUE),
  math_proficiency     = list(label = "Mathematics Proficiency",unit = "%",    higher_better = TRUE),
  reading_proficiency  = list(label = "Reading Proficiency",    unit = "%",    higher_better = TRUE),
  science_proficiency  = list(label = "Science Proficiency",    unit = "%",    higher_better = TRUE),
  graduation_rate      = list(label = "Graduation Rate",        unit = "%",    higher_better = TRUE)
)
compare_metric_choices <- setNames(names(compare_metrics),
                                   vapply(compare_metrics, `[[`, "", "label"))
