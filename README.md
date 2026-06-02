# Utah Public High Schools Dashboard

An interactive R Shiny app that maps and ranks the **219 public high schools across all 87 Utah districts** using data from *U.S. News Best High Schools 2025-2026*. Click a district polygon or a school marker to drill into rankings, AP participation, proficiency scores, and graduation rates — averages recalculate live as you filter.

![App](https://img.shields.io/badge/R-Shiny-1f78b4) ![Map](https://img.shields.io/badge/Map-Leaflet-3cb371) ![Data](https://img.shields.io/badge/Schools-219-orange)

## What the app shows

- **Leaflet map of Utah** with the 41 traditional school district boundaries colored by district, plus clustered markers for all 219 high schools.
- **Hover a polygon** → tooltip with district name and high school count (e.g., *Davis School District — 15 high schools*).
- **Hover a marker** → rich tooltip with the school's full scorecard: name, district, address, Overall Score, Utah and National Rank, AP taken/passed, Mathematics/Reading/Science proficiency, and Graduation Rate.
- **Click a polygon** → district dropdown updates, map zooms to the district's bounding box, markers filter to that district's schools, average scorecard recalculates.
- **Click a marker** → school dropdown updates, map zooms to that school, sidebar shows its full scorecard with a link to the U.S. News source page.
- **Average scorecard panel** in the sidebar dynamically reflects the current filter (Statewide → District → Single school) for AP exam participation/pass, subject proficiencies, and graduation rate. Bucketed values (`>= 80%`, `60-69%`, `n< 10%`, `N/A`) are excluded from averages — they aren't real numbers and would distort the mean.

## Data sources

| Field | Source |
|---|---|
| School scorecards (Overall Score, ranks, AP, proficiency, grad rate) | *U.S. News Best High Schools 2025-2026* — scraped from per-school detail pages via the schema.org `HighSchool` JSON-LD blob plus `data-test-id` attributes |
| Addresses | Same — pulled from each school's JSON-LD `PostalAddress` |
| Latitude / longitude | Geocodio batch geocoding of the address column |
| District polygons | U.S. Census Bureau TIGER/Line 2023 — Unified School Districts |

The scrape verified every numeric field against the live U.S. News page on a sample of 10 schools (3 edge cases with bucketed grad rates / unranked / range-ranked, plus 7 random schools across the rank distribution).

## File layout

```
.
├── global.R                          # Packages, data load, JOIN, polygons, palette, helpers
├── ui.R                              # Sidebar (filters + averages + scorecard) and map layout
├── server.R                          # Reactivity: filters, click handlers, marker rendering, auto-fit
├── data/
│   ├── utah_high_schools.json        # 219 schools × 15 fields (scorecard + raw graduation string)
│   └── school_addresses_geocode.csv  # Geocodio output keyed by address
├── renv.lock                         # Reproducible package versions
└── renv/                             # renv bootstrap (library/ folder is gitignored)
```

## Schema

`data/utah_high_schools.json` — one object per school:

```json
{
  "school_name": "Ogden High School",
  "district":   "Ogden City District",
  "address":    "2828 Harrison Blvd, Ogden, Utah 84403",
  "overall_score":         62.55,
  "state_rank":            68,
  "national_rank":         6704,
  "ap_taken_pct":          41,
  "ap_passed_pct":         31,
  "math_proficiency":      14,
  "reading_proficiency":   29,
  "science_proficiency":   20,
  "graduation_rate":       93,
  "graduation_rate_raw":   "93%",
  "year":                  "2025-2026",
  "source_url":            "https://www.usnews.com/..."
}
```

Numeric fields are `null` when U.S. News suppressed the value (e.g., very small schools have `graduation_rate_raw: "n< 10%"` and `graduation_rate: null`). The `_raw` field always preserves the source string verbatim for transparency.

## Running it locally

### Prerequisites
- R ≥ 4.1
- RStudio (recommended for the **Run App** button)

### One-time setup
Open the project in RStudio (double-click `School district graduation.Rproj`) and restore the package set:

```r
install.packages("renv")
renv::restore()
```

If you'd rather skip renv, install the packages directly:

```r
install.packages(c(
  "shiny", "leaflet", "dplyr", "htmltools",
  "jsonlite", "readr", "tigris", "sf"
))
```

### Run
Open any of `global.R`, `ui.R`, or `server.R` in RStudio and click **Run App**. Equivalent from the console:

```r
shiny::runApp()
```

First launch may take ~30 seconds while `tigris` downloads the Utah school district shapefile from the Census; subsequent launches load from the local cache instantly.

## Reactivity overview

```
input$district (dropdown or polygon click)
    ↓ observeEvent
    ↓ updateSelectInput("school", "All schools")
    ↓
filtered()  ←──── input$school
    ↓
    ├──────► observe(): redraw markers + auto-fit (polygon bbox or school bbox)
    ├──────► output$avg_scorecard: recompute averages
    └──────► output$school_stats: show single-school detail or N-match summary
```

Map clicks bypass the dropdowns by calling `updateSelectInput` from `observeEvent(input$map_shape_click)` / `observeEvent(input$map_marker_click)` — same reactive cascade either way.

## Debug logging

`server.R` has a `DEBUG <- TRUE` flag at the top of the server function. While true, every click, dropdown change, reactive invalidation, and render prints a timestamped line to the R console:

```
[19:47:39.657] filtered()      | district=All districts  school=All schools  -> 219 rows
[19:47:39.659] markers obs     | rendering 219 circle markers
[19:47:39.850] auto-fit        | branch=schools  bbox=[-114.037,37.005,-109.304,41.826]
```

Set `DEBUG <- FALSE` for silence.

## Known quirks worth keeping in mind

- **Bucketed graduation rates**: U.S. News suppresses exact values for small schools and shows ranges instead (`>= 80%`, `70-79%`, `n< 10%`). The numeric `graduation_rate` is `null` for these; the average scorecard excludes them.
- **Range rankings**: a few schools are reported as a range, e.g., *#131-162 in Utah High Schools*. Those become `null` in `state_rank` / `national_rank` for the same reason.
- **Charters as "districts"**: U.S. News treats each charter school as its own district. The app preserves that — there are 87 entries in the district filter (41 traditional + 46 charters). Charters don't have geographic boundaries, so they appear as markers only, not polygons.
- **District name mapping**: TIGER's Census names differ from U.S. News's. The app normalizes both sides (strips "County", "City", "School District", "District") to make the join robust to either convention.

## Acknowledgments

- U.S. News & World Report — *Best High Schools* methodology and scorecard data
- U.S. Census Bureau — TIGER/Line shapefiles for school district boundaries
- Geocodio — address geocoding
- The R ecosystem — `shiny`, `leaflet`, `sf`, `tigris`, `dplyr`, `jsonlite`
