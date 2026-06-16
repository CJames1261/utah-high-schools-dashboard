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
schools_json <- fromJSON("data/utah_high_schools.json", simplifyDataFrame = TRUE)
geo_csv      <- read_csv("data/school_addresses_geocode.csv", show_col_types = FALSE)

geo <- geo_csv %>%
  transmute(
    address          = address,
    latitude         = `Geocodio Latitude`,
    longitude        = `Geocodio Longitude`,
    geocode_accuracy = `Geocodio Accuracy Score`
  ) %>%
  # Some addresses appear multiple times in the CSV (e.g., a building shared
  # by two schools was geocoded once per row). Keep only one row per address
  # so the left_join below is one-to-many, not many-to-many.
  distinct(address, .keep_all = TRUE)

schools <- schools_json %>% left_join(geo, by = "address")

# Breakdown of "districts" in the U.S. News data:
#   - 41 are real Utah school districts (label ends in "District").
#   - The rest are charter schools that U.S. News treats as their own LEA, so
#     each charter appears as a 1-school "district" with the charter's name.
#   We surface both counts so the header doesn't mislead.
all_districts_n <- length(unique(schools$district))
n_traditional   <- sum(grepl("District$", unique(schools$district)))
n_charters      <- all_districts_n - n_traditional

message(sprintf("Loaded %d schools (%d districts + %d charters = %d total LEAs). %d without coordinates.",
                nrow(schools), n_traditional, n_charters, all_districts_n,
                sum(is.na(schools$latitude))))

# ---- District boundary polygons (Census TIGER) -------------------------------
# Census uses slightly different names than U.S. News. This lookup translates
# from the U.S. News district name (in our JSON) to the Census NAME column.
# Only the 41 traditional geographic districts get polygons. Charters
# (~44 "districts" in U.S. News) are statewide schools-of-choice with no
# boundary and remain as markers only.
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

# Pull Utah unified school district polygons (cached after first run)
ut_districts_raw <- school_districts(state = "UT", type = "unified",
                                     cb = TRUE, year = 2023,
                                     progress_bar = FALSE)

# Normalize district names so the mapping survives TIGER vs U.S. News quirks
# (some districts include "County" or "City", some don't; capitalization
# differs across releases).
normalize_district <- function(x) {
  x <- tolower(x)
  x <- gsub(" school district\\b", "", x)
  x <- gsub(" district\\b",        "", x)
  x <- gsub(" county\\b",          "", x)
  x <- gsub(" city\\b",            "", x)
  x <- gsub("\\s+",                " ", x)
  trimws(x)
}

# Map normalized Census NAME -> original U.S. News name (the key we want).
usnews_normalized <- normalize_district(names(usnews_to_census_district))
norm_to_usnews    <- setNames(names(usnews_to_census_district), usnews_normalized)

# Count high schools per U.S. News district (for the polygon hover tooltip).
school_counts <- schools %>% count(district, name = "n_schools")

district_polygons <- ut_districts_raw %>%
  mutate(
    norm            = normalize_district(NAME),
    usnews_district = unname(norm_to_usnews[norm])
  ) %>%
  filter(!is.na(usnews_district)) %>%
  st_transform(crs = 4326) %>%
  left_join(school_counts, by = c("usnews_district" = "district"))

# Diagnostic: list districts on each side that didn't get matched.
matched_census  <- ut_districts_raw$NAME[normalize_district(ut_districts_raw$NAME) %in% usnews_normalized]
unmatched_census <- setdiff(ut_districts_raw$NAME, matched_census)
traditional_usnews_set <- names(usnews_to_census_district)
unmatched_usnews <- setdiff(traditional_usnews_set, district_polygons$usnews_district)
if (length(unmatched_census) > 0) {
  message("[district join] Census districts with NO polygon match:")
  message("  ", paste(unmatched_census, collapse = "; "))
}
if (length(unmatched_usnews) > 0) {
  message("[district join] U.S. News districts with NO polygon assigned:")
  message("  ", paste(unmatched_usnews, collapse = "; "))
}
message(sprintf("[district join] %d / %d traditional districts have polygons.",
                nrow(district_polygons), length(traditional_usnews_set)))

# NOTE: per-polygon hover labels are the district KPI scorecards, built in the
# Helpers section below once compute_avg_scorecard() / fmt_avg() are defined.

# ---- District color palette --------------------------------------------------
# 87 districts is too many for any pre-built qualitative palette to produce
# fully distinct colors, but a hue-stepped rainbow with controlled saturation
# guarantees every district reads as a real color (not interpolated near-white).
all_districts <- sort(unique(schools$district))

# Shuffle district -> color mapping so alphabetically-adjacent districts
# (which often share hue when sampled from a continuous palette) don't end up
# with near-identical colors. Seed makes the assignment reproducible.
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

# One KPI card per polygon, in the same row order as district_polygons.
polygon_hover_labels <- lapply(seq_len(nrow(district_polygons)), function(i) {
  nm <- district_polygons$usnews_district[i]
  df <- schools[schools$district == nm, ]
  district_kpi_card(nm, compute_avg_scorecard(df))
})

# Utah bounding box for initial map view
UTAH_BBOX <- list(lng1 = -114.05, lat1 = 37.00,
                  lng2 = -109.05, lat2 = 42.00)

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
