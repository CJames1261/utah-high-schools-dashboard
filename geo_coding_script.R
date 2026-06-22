
library(tidygeocoder)
library(dplyr)

schools <- read.csv("school_addresses_so_far.csv")

geocode_addresses <- function(df) {
  
  total_rows <- nrow(df)
  
  if (!"address" %in% names(df)) {
    stop("Your dataset must have a column named 'address'.")
  }
  
  df <- df %>%
    mutate(row_id = row_number())
  
  print_status <- function(method_name, remaining_count) {
    remaining_pct <- round(100 * remaining_count / total_rows, 2)
    
    cat(
      sprintf(
        "\nAfter %s: %s NULL lat/long rows remaining (%.2f%%)\n",
        method_name,
        remaining_count,
        remaining_pct
      )
    )
  }
  
  cat("\nTotal addresses:", total_rows, "\n")
  
  # Census
  message("Step 1: Geocoding all addresses with Census...")
  
  results <- df %>%
    geocode(
      address = address,
      method = "census",
      lat = latitude,
      long = longitude
    )
  
  remaining <- results %>%
    filter(is.na(latitude) | is.na(longitude))
  
  print_status("Census", nrow(remaining))
  
  # ArcGIS
  if (nrow(remaining) > 0) {
    
    message("Step 2: Geocoding remaining NULL addresses with ArcGIS...")
    
    arcgis <- remaining %>%
      select(-latitude, -longitude) %>%
      geocode(
        address = address,
        method = "arcgis",
        lat = latitude_arcgis,
        long = longitude_arcgis
      )
    
    results <- results %>%
      left_join(
        arcgis %>%
          select(row_id, latitude_arcgis, longitude_arcgis),
        by = "row_id"
      ) %>%
      mutate(
        latitude = coalesce(latitude, latitude_arcgis),
        longitude = coalesce(longitude, longitude_arcgis)
      ) %>%
      select(-latitude_arcgis, -longitude_arcgis)
    
    remaining <- results %>%
      filter(is.na(latitude) | is.na(longitude))
    
    print_status("ArcGIS", nrow(remaining))
  }
  
  # OSM
  if (nrow(remaining) > 0) {
    
    message("Step 3: Geocoding remaining NULL addresses with OSM...")
    
    osm <- remaining %>%
      select(-latitude, -longitude) %>%
      geocode(
        address = address,
        method = "osm",
        lat = latitude_osm,
        long = longitude_osm
      )
    
    results <- results %>%
      left_join(
        osm %>%
          select(row_id, latitude_osm, longitude_osm),
        by = "row_id"
      ) %>%
      mutate(
        latitude = coalesce(latitude, latitude_osm),
        longitude = coalesce(longitude, longitude_osm)
      ) %>%
      select(-latitude_osm, -longitude_osm)
    
    remaining <- results %>%
      filter(is.na(latitude) | is.na(longitude))
    
    print_status("OSM", nrow(remaining))
  }
  
  final_missing <- results %>%
    filter(is.na(latitude) | is.na(longitude))
  
  cat("\nFinal geocoding summary:\n")
  cat("Total rows:", total_rows, "\n")
  cat("Successfully geocoded:", total_rows - nrow(final_missing), "\n")
  cat("Still missing:", nrow(final_missing), "\n")
  cat(
    "Final missing percentage:",
    round(100 * nrow(final_missing) / total_rows, 2),
    "%\n"
  )
  
  results <- results %>%
    select(-row_id)
  
  return(results)
}

schools_geo <- geocode_addresses(schools)

write.csv(schools_geo, "data\school_addresses_geocode.csv", row.names = FALSE)
