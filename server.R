# server.R

function(input, output, session) {

  # ---- Debug logger ---------------------------------------------------------
  # Flip DEBUG to FALSE to silence all the diagnostic messages.
  DEBUG <- TRUE
  log_evt <- function(tag, ...) {
    if (!DEBUG) return()
    ts <- format(Sys.time(), "%H:%M:%OS3")
    msg <- paste0(..., collapse = "")
    message(sprintf("[%s] %-15s | %s", ts, tag, msg))
  }
  log_evt("startup", sprintf("schools=%d  districts=%d  polygons=%d",
                             nrow(schools),
                             length(unique(schools$district)),
                             nrow(district_polygons)))

  # ---- Reactive: filtered school list ---------------------------------------
  filtered <- reactive({
    df <- schools
    if (input$district != "All districts") df <- df %>% filter(district == input$district)
    if (input$school   != "All schools")   df <- df %>% filter(school_name == input$school)
    log_evt("filtered()",
            sprintf("district=%s  school=%s  -> %d rows",
                    input$district, input$school, nrow(df)))
    df
  })

  # Keep the "School" dropdown in sync with the chosen district
  observeEvent(input$district, {
    log_evt("input$district", sprintf("changed -> %s", input$district))
    df <- schools
    if (input$district != "All districts") df <- df %>% filter(district == input$district)
    updateSelectInput(
      session, "school",
      choices  = c("All schools", sort(unique(df$school_name))),
      selected = "All schools"
    )
  })

  observeEvent(input$school, {
    log_evt("input$school", sprintf("changed -> %s", input$school))
  }, ignoreInit = TRUE)

  # ---- Base map (renders once) ----------------------------------------------
  output$map <- renderLeaflet({
    log_evt("renderLeaflet", "building base map (polygons drawn here)")
    leaflet() %>%
      addProviderTiles(providers$CartoDB.Positron) %>%
      addPolygons(
        data        = district_polygons,
        fillColor   = ~district_pal(usnews_district),
        fillOpacity = 0.35,
        color       = "#333",
        weight      = 1,
        label       = polygon_hover_labels,
        labelOptions = labelOptions(
          direction = "auto",
          sticky    = FALSE,
          opacity   = 1,
          style     = list(
            "background-color" = "white",
            "border"           = "1px solid #888",
            "border-radius"    = "4px",
            "padding"          = "6px 8px",
            "box-shadow"       = "0 2px 6px rgba(0,0,0,0.18)"
          )
        ),
        layerId     = ~usnews_district,
        group       = "districts",
        highlightOptions = highlightOptions(
          weight = 3, color = "#000", fillOpacity = 0.55, bringToFront = FALSE
        )
      ) %>%
      fitBounds(UTAH_BBOX$lng1, UTAH_BBOX$lat1,
                UTAH_BBOX$lng2, UTAH_BBOX$lat2)
  })

  # ---- Update markers when the filter changes -------------------------------
  observe({
    df <- filtered() %>% filter(!is.na(latitude) & !is.na(longitude))
    log_evt("markers obs", sprintf("rendering %d circle markers", nrow(df)))

    proxy <- leafletProxy("map") %>%
      clearMarkers() %>%
      clearMarkerClusters()

    if (nrow(df) == 0) {
      log_evt("markers obs", "no rows -> bailing out without fitBounds")
      return()
    }

    # Build the rich scorecard HTML once per row, then wrap each in
    # htmltools::HTML so leaflet renders it as HTML inside the hover label
    # rather than treating it as plain text.
    popup_html  <- vapply(
      seq_len(nrow(df)),
      function(i) as.character(school_popup(df[i, ])),
      character(1)
    )
    hover_labels <- lapply(popup_html, htmltools::HTML)

    proxy <- proxy %>% addCircleMarkers(
      lng         = df$longitude,
      lat         = df$latitude,
      radius      = 7,
      fillColor   = district_pal(df$district),
      color       = "#222",
      weight      = 1,
      fillOpacity = 0.95,
      layerId     = df$school_name,
      label       = hover_labels,
      labelOptions = labelOptions(
        direction = "auto",
        offset    = c(0, -8),
        sticky    = FALSE,
        opacity   = 1,
        style     = list(
          "background-color" = "white",
          "border"           = "1px solid #888",
          "border-radius"    = "4px",
          "padding"          = "8px 10px",
          "box-shadow"       = "0 2px 6px rgba(0,0,0,0.18)"
        )
      ),
      group       = "schools",
      clusterOptions = markerClusterOptions(
        showCoverageOnHover = FALSE,
        spiderfyOnMaxZoom   = TRUE,
        maxClusterRadius    = 45
      )
    )

    # Auto-fit logic, in order of preference:
    #   1. Single specific school selected -> zoom in tight on it.
    #   2. District selected AND has a polygon (the 41 traditional districts)
    #      -> fit the map to the polygon's bounding box.
    #   3. Otherwise -> fit to the school coordinates with a small pad.
    if (input$school != "All schools" && nrow(df) == 1) {
      log_evt("auto-fit", sprintf("branch=school  zoom 14 on %s",
                                  df$school_name))
      proxy %>% setView(lng = df$longitude, lat = df$latitude, zoom = 14)
    } else if (input$district != "All districts" &&
               input$district %in% district_polygons$usnews_district) {
      bbox <- st_bbox(district_polygons[
        district_polygons$usnews_district == input$district, ])
      log_evt("auto-fit", sprintf("branch=polygon  bbox=[%.3f,%.3f,%.3f,%.3f]",
                                  bbox["xmin"], bbox["ymin"],
                                  bbox["xmax"], bbox["ymax"]))
      proxy %>% fitBounds(
        as.numeric(bbox["xmin"]), as.numeric(bbox["ymin"]),
        as.numeric(bbox["xmax"]), as.numeric(bbox["ymax"])
      )
    } else {
      log_evt("auto-fit", sprintf("branch=schools  bbox=[%.3f,%.3f,%.3f,%.3f]",
                                  min(df$longitude), min(df$latitude),
                                  max(df$longitude), max(df$latitude)))
      proxy %>% fitBounds(
        min(df$longitude) - 0.05, min(df$latitude) - 0.05,
        max(df$longitude) + 0.05, max(df$latitude) + 0.05
      )
    }
  })

  # ---- Clicking a marker selects that school in the sidebar -----------------
  observeEvent(input$map_marker_click, {
    click <- input$map_marker_click
    log_evt("marker_click",
            sprintf("id=%s  group=%s  lat=%.4f  lng=%.4f  len=%d",
                    deparse(click$id), deparse(click$group),
                    click$lat %||% NA, click$lng %||% NA,
                    length(click$id)))

    id <- click$id
    if (length(id) != 1) {
      log_evt("marker_click", "  -> skipping: id length != 1 (cluster?)")
      return()
    }
    if (id %in% schools$school_name) {
      log_evt("marker_click", sprintf("  -> updating input$school to %s", id))
      updateSelectInput(session, "school", selected = as.character(id))
    } else {
      log_evt("marker_click", "  -> id not in schools$school_name, ignoring")
    }
  })

  # ---- Clicking a polygon selects that district in the sidebar --------------
  observeEvent(input$map_shape_click, {
    click <- input$map_shape_click
    log_evt("shape_click",
            sprintf("id=%s  group=%s  lat=%.4f  lng=%.4f  len=%d",
                    deparse(click$id), deparse(click$group),
                    click$lat %||% NA, click$lng %||% NA,
                    length(click$id)))

    if (!isTRUE(click$group == "districts")) {
      log_evt("shape_click", "  -> not a district polygon, ignoring")
      return()
    }
    id <- click$id
    if (length(id) != 1) {
      log_evt("shape_click", "  -> id length != 1, ignoring")
      return()
    }
    if (id %in% schools$district) {
      log_evt("shape_click", sprintf("  -> updating input$district to %s", id))
      updateSelectInput(session, "district", selected = as.character(id))
    } else {
      log_evt("shape_click", sprintf("  -> %s not in schools$district, ignoring", id))
    }
  })

  # ---- Reset button ---------------------------------------------------------
  observeEvent(input$reset_view, {
    log_evt("reset_view", "clicked -> resetting filters and map view")
    updateSelectInput(session, "district", selected = "All districts")
    updateSelectInput(session, "school",   selected = "All schools")
    leafletProxy("map") %>%
      fitBounds(UTAH_BBOX$lng1, UTAH_BBOX$lat1,
                UTAH_BBOX$lng2, UTAH_BBOX$lat2)
  })

  # ---- Average scorecard (under the filters) --------------------------------
  output$avg_scorecard <- renderUI({
    df  <- filtered()
    avg <- compute_avg_scorecard(df)
    log_evt("avg_scorecard",
            sprintf("rerender  n=%d  scope district=%s  school=%s",
                    nrow(df), input$district, input$school))

    if (is.null(avg)) return(p(em("No schools match the current filters.")))

    scope <- if (input$district == "All districts" && input$school == "All schools") {
      "Statewide"
    } else if (input$school != "All schools") {
      input$school
    } else {
      input$district
    }

    tagList(
      p(sprintf("%s — %d school%s", scope, avg$n, if (avg$n == 1) "" else "s"),
        style = "color:#666; font-size:11px; margin: 1px 0 6px 0;"),
      tags$ul(
        tags$li(strong("Took at Least One AP Exam: "),    fmt_avg(avg$ap_taken)),
        tags$li(strong("Passed at Least One AP Exam: "),  fmt_avg(avg$ap_passed)),
        tags$li(strong("Mathematics Proficiency: "),      fmt_avg(avg$math)),
        tags$li(strong("Reading Proficiency: "),          fmt_avg(avg$reading)),
        tags$li(strong("Science Proficiency: "),          fmt_avg(avg$science)),
        tags$li(strong("Graduation Rate: "),              fmt_avg(avg$graduation))
      ),
      tags$small(
        "Bucketed values (>= 80%, 60-69%, n< 10%, N/A) are excluded from averages.",
        style = "color:#999;"
      )
    )
  })

  # ---- Sidebar scorecard ----------------------------------------------------
  output$school_stats <- renderUI({
    df <- filtered()
    log_evt("school_stats", sprintf("rerender  n=%d", nrow(df)))

    if (nrow(df) == 0) {
      return(p(em("No schools match the current filters.")))
    }

    if (nrow(df) > 1) {
      return(p(em(sprintf("%d schools match. Pick one (or click a marker) to see its scorecard.",
                          nrow(df)))))
    }

    s <- df[1, ]
    tagList(
      strong(s$school_name),
      p(s$district, style = "color:#888; font-size:11px; margin:1px 0;"),
      p(s$address,  style = "color:#666; margin-top:2px;"),
      tags$ul(
        tags$li(strong("Overall Score: "),           fmt_score(s$overall_score)),
        tags$li(strong("Utah HS Ranking: "),         fmt_rank(s$state_rank)),
        tags$li(strong("National Ranking: "),        fmt_rank(s$national_rank)),
        tags$li(strong("Took at Least One AP: "),    fmt_pct(s$ap_taken_pct)),
        tags$li(strong("Passed at Least One AP: "),  fmt_pct(s$ap_passed_pct)),
        tags$li(strong("Mathematics Proficiency: "), fmt_pct(s$math_proficiency)),
        tags$li(strong("Reading Proficiency: "),     fmt_pct(s$reading_proficiency)),
        tags$li(strong("Science Proficiency: "),     fmt_pct(s$science_proficiency)),
        tags$li(strong("Graduation Rate: "),         fmt_grad(s$graduation_rate, s$graduation_rate_raw))
      ),
      if (!is.na(s$source_url))
        tags$a(href = s$source_url, target = "_blank", "U.S. News page ↗")
    )
  })
}
