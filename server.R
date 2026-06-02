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
      fillColor   = unname(district_pal(df$district)),
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

  # ---- Collapse / expand the floating control panel -------------------------
  observeEvent(input$collapse_filters, {
    log_evt("collapse_filters", "toggle")
    shinyjs::toggleClass(id = "control_panel", class = "is-collapsed")
  })

  # ---- Detail panel visibility ---------------------------------------------
  # Auto-shows when a filter narrows the scope; user can dismiss with the X.
  # Re-opens on the next filter change so it doesn't stay hidden forever.
  detail_dismissed <- reactiveVal(FALSE)

  observeEvent(c(input$district, input$school), {
    detail_dismissed(FALSE)
    has_filter <- (input$district != "All districts") ||
                  (input$school   != "All schools")
    if (has_filter) {
      log_evt("detail_panel", "showing (filter active)")
      shinyjs::show("detail_panel", anim = TRUE, animType = "fade")
    } else {
      log_evt("detail_panel", "hiding (no filter)")
      shinyjs::hide("detail_panel", anim = TRUE, animType = "fade")
    }
  }, ignoreInit = TRUE)

  observeEvent(input$close_detail, {
    log_evt("close_detail", "user dismissed details panel")
    detail_dismissed(TRUE)
    shinyjs::hide("detail_panel", anim = TRUE, animType = "fade")
  })

  # ---- Helpers for KPI / scope / detail UI ---------------------------------
  # Brief, professional explanations shown on hover of each stat's info icon.
  kpi_tooltips <- list(
    ap_taken   = "Percentage of 12th-grade students who took at least one Advanced Placement (AP) exam during high school.",
    ap_passed  = "Percentage of 12th-grade students who scored 3 or higher on at least one AP exam — the threshold for college-level mastery.",
    math       = "Percentage of students who scored proficient on Utah's state-administered mathematics assessment.",
    reading    = "Percentage of students who scored proficient on Utah's state-administered reading assessment.",
    science    = "Percentage of students who scored proficient on Utah's state-administered science assessment.",
    graduation = "Percentage of students who graduate within four years of starting 9th grade (four-year adjusted cohort rate)."
  )

  kpi_stat <- function(icon, label, value, tooltip_text = NULL) {
    is_na <- identical(value, "n/a")
    info <- if (!is.null(tooltip_text)) {
      bslib::tooltip(
        span(class = "kpi-info", bsicons::bs_icon("info-circle")),
        tooltip_text,
        placement = "top"
      )
    }
    div(class = "kpi-stat",
      div(class = "kpi-stat-head",
        bsicons::bs_icon(icon),
        span(label),
        info
      ),
      div(class = paste("kpi-stat-value", if (is_na) "na" else ""), value)
    )
  }

  stat_row <- function(label, value) {
    is_na <- identical(value, "n/a")
    div(class = "stat-row",
      span(class = "stat-row-label", label),
      span(class = paste("stat-row-value", if (is_na) "na" else ""), value)
    )
  }

  current_scope <- function() {
    if (input$school != "All schools") return(list(name = input$school, kind = "school"))
    if (input$district != "All districts") return(list(name = input$district, kind = "district"))
    list(name = "Statewide", kind = "all")
  }

  # ---- KPI panel (top center) — single card with dynamic title -------------
  output$kpi_cards <- renderUI({
    df    <- filtered()
    avg   <- compute_avg_scorecard(df)
    scope <- current_scope()
    log_evt("kpi_cards",
            sprintf("rerender  n=%d  district=%s  school=%s",
                    nrow(df), input$district, input$school))
    if (is.null(avg)) return(NULL)

    title <- switch(scope$kind,
      "all"      = "All Utah district averages",
      "district" = sprintf("%s averages", scope$name),
      "school"   = sprintf("%s scorecard",  scope$name)
    )

    tagList(
      div(class = "kpi-panel-head",
        div(class = "kpi-panel-title",
          bsicons::bs_icon("bar-chart-line-fill"),
          span(title)
        ),
        div(class = "kpi-panel-meta",
          sprintf("Based on %d school%s",
                  avg$n, if (avg$n == 1) "" else "s"))
      ),
      div(class = "kpi-panel-body",
        kpi_stat("pencil-square",    "AP Taken",   fmt_avg(avg$ap_taken),   kpi_tooltips$ap_taken),
        kpi_stat("patch-check-fill", "AP Passed",  fmt_avg(avg$ap_passed),  kpi_tooltips$ap_passed),
        kpi_stat("calculator",       "Math",       fmt_avg(avg$math),       kpi_tooltips$math),
        kpi_stat("book",             "Reading",    fmt_avg(avg$reading),    kpi_tooltips$reading),
        kpi_stat("lightbulb",        "Science",    fmt_avg(avg$science),    kpi_tooltips$science),
        kpi_stat("mortarboard-fill", "Graduation", fmt_avg(avg$graduation), kpi_tooltips$graduation)
      )
    )
  })

  # ---- Scope block (inside the control panel) ------------------------------
  output$scope_block <- renderUI({
    df    <- filtered()
    scope <- current_scope()
    log_evt("scope_block",
            sprintf("scope=%s  n=%d", scope$name, nrow(df)))

    eyebrow <- switch(scope$kind,
      "all"      = "Currently viewing",
      "district" = "District",
      "school"   = "School")

    # Statewide view: surface the district / charter split too.
    meta <- if (scope$kind == "all") {
      sprintf("%d schools  ·  %d districts + %d charters",
              nrow(df), n_traditional, n_charters)
    } else {
      sprintf("%d school%s in view", nrow(df), if (nrow(df) == 1) "" else "s")
    }

    div(class = "scope-block",
      div(class = "scope-eyebrow", eyebrow),
      div(class = "scope-value",   scope$name),
      div(class = "scope-meta",    meta),
      div(class = "scope-note",
        bsicons::bs_icon("info-circle", style = "margin-right:4px"),
        "Bucketed values ('>= 80%', '60-69%', 'n< 10%', 'N/A') are excluded from averages."
      )
    )
  })

  # =========================================================================
  # COMPARE SCHOOLS TAB
  # =========================================================================

  compare_data <- reactive({
    metric <- input$cmp_metric
    req(metric %in% names(schools))

    df <- schools
    if (!is.null(input$cmp_district) && input$cmp_district != "All districts") {
      df <- df %>% filter(district == input$cmp_district)
    }
    df <- df[!is.na(df[[metric]]), ]
    if (nrow(df) == 0) return(df)

    # "Best first" means highest value for score metrics, but lowest value
    # for rank metrics (Utah Rank, National Rank), since #1 is the best.
    higher_better   <- compare_metrics[[metric]]$higher_better
    want_best_first <- input$cmp_sort == "best"
    sort_descending <- isTRUE(higher_better) == isTRUE(want_best_first)
    df <- df[order(df[[metric]], decreasing = sort_descending), ]

    n <- suppressWarnings(as.integer(input$cmp_n))
    if (is.na(n) || n <= 0) n <- nrow(df)
    head(df, n)
  })

  metric_meta <- reactive({
    m <- input$cmp_metric
    list(
      key   = m,
      label = compare_metrics[[m]]$label,
      unit  = compare_metrics[[m]]$unit,
      higher_better = compare_metrics[[m]]$higher_better
    )
  })

  output$cmp_meta_inline <- renderUI({
    df <- compare_data()
    m  <- metric_meta()
    scope <- if (input$cmp_district == "All districts") "Statewide"
             else input$cmp_district
    span(sprintf("%s · %s · %d school%s",
                 scope, m$label, nrow(df),
                 if (nrow(df) == 1) "" else "s"))
  })

  output$cmp_chart_meta <- renderUI({
    df <- compare_data()
    m  <- metric_meta()
    span(sprintf("Showing %d ranked by %s · %s first",
                 nrow(df), m$label,
                 if (input$cmp_sort == "best") "best" else "worst"))
  })

  output$cmp_stat_strip <- renderUI({
    df <- compare_data()
    m  <- metric_meta()
    if (nrow(df) == 0) return(NULL)

    vals <- df[[m$key]]
    fmt  <- function(x) {
      if (is.na(x) || is.nan(x)) return("n/a")
      if (m$unit == "%")     sprintf("%.1f%%", x)
      else if (m$unit == "/100") sprintf("%.2f", x)
      else                    paste0("#", formatC(x, big.mark = ",", format = "d"))
    }

    stat_card <- function(label, value, meta = NULL) {
      div(class = "compare-stat-card",
        div(class = "compare-stat-eyebrow", label),
        div(class = "compare-stat-value", value),
        if (!is.null(meta)) div(class = "compare-stat-meta", meta)
      )
    }

    # Identify best and worst by actual value semantics, regardless of
    # which way the user has the sort dropdown set.
    best_i  <- if (m$higher_better) which.max(vals) else which.min(vals)
    worst_i <- if (m$higher_better) which.min(vals) else which.max(vals)

    div(class = "compare-stat-strip",
      stat_card("Schools in view",
                formatC(nrow(df), big.mark = ","),
                if (input$cmp_district == "All districts") "Statewide"
                else input$cmp_district),
      stat_card("Best",
                fmt(vals[best_i]),
                df$school_name[best_i]),
      stat_card("Median",
                fmt(median(vals, na.rm = TRUE)),
                m$label),
      stat_card("Worst",
                fmt(vals[worst_i]),
                df$school_name[worst_i])
    )
  })

  output$compare_chart <- renderPlotly({
    df <- compare_data()
    m  <- metric_meta()

    log_evt("compare_chart",
            sprintf("rerender  metric=%s  district=%s  n=%d  order=%s  hb=%s",
                    m$key, input$cmp_district, nrow(df), input$cmp_sort, m$higher_better))

    if (nrow(df) == 0) {
      return(plotly_empty(type = "scatter", mode = "markers") %>%
               layout(annotations = list(
                 text = "No schools have data for this metric in the current filter.",
                 x = 0.5, y = 0.5, xref = "paper", yref = "paper",
                 showarrow = FALSE,
                 font = list(family = "Inter", size = 14, color = "#94a3b8")
               )))
    }

    # Y axis order: factor so first row of df sits at the top.
    df$school_name <- factor(df$school_name, levels = rev(df$school_name))
    fill_cols <- unname(district_pal(df$district))

    val_lab <- if (m$unit == "%")        sprintf("%.1f%%", df[[m$key]])
               else if (m$unit == "/100") sprintf("%.2f",   df[[m$key]])
               else                        paste0("#", formatC(df[[m$key]], big.mark = ",", format = "d"))
    tooltip_txt <- sprintf("<b>%s</b><br>%s<br>%s: <b>%s</b>",
      df$school_name, df$district, m$label, val_lab)

    common_layout <- function(p, xtitle, extra = list()) {
      layout(p,
        margin = list(l = 240, r = 30, t = 12, b = 60),
        xaxis  = c(list(
          title    = list(text = xtitle,
                          font = list(family = "Inter", size = 11, color = "#475569")),
          gridcolor = "#eef2f6",
          zerolinecolor = "#e2e8f0",
          tickfont = list(family = "Inter", size = 11, color = "#64748b")
        ), extra),
        yaxis = list(
          title = "",
          tickfont = list(family = "Inter", size = 11.5, color = "#1f2937"),
          automargin = TRUE
        ),
        plot_bgcolor  = "rgba(0,0,0,0)",
        paper_bgcolor = "rgba(0,0,0,0)",
        hoverlabel    = list(bgcolor = "white",
                             bordercolor = "#e2e8f0",
                             font = list(family = "Inter", size = 12, color = "#0f172a")),
        showlegend = FALSE
      ) %>% config(displayModeBar = FALSE)
    }

    if (isTRUE(m$higher_better)) {
      # ---- Score metrics: horizontal bar chart -------------------------
      xtitle <- paste0(m$label,
                       if (nzchar(m$unit)) paste0(" (", m$unit, ")") else "")
      plot_ly(
        data = df,
        type = "bar",
        orientation = "h",
        y = ~school_name,
        x = stats::setNames(df[[m$key]], NULL),
        marker = list(
          color = fill_cols,
          line  = list(color = "rgba(15,23,42,0.18)", width = 0.5)
        ),
        hovertemplate = paste0(tooltip_txt, "<extra></extra>")
      ) %>% common_layout(xtitle)

    } else {
      # ---- Rank metrics: lollipop / dot plot --------------------------
      # Bar length isn't meaningful for ranks (#1 is best, not "smallest").
      # Use a dot whose x position = the rank, plus a thin line connecting it
      # to the best rank in the chart so the eye can scan.
      xtitle <- paste0(m$label, " — lower number is better")
      ranks  <- df[[m$key]]
      xmin   <- min(ranks, na.rm = TRUE)

      # Lollipop "stems" as line segments via shapes.
      stems <- lapply(seq_len(nrow(df)), function(i) {
        list(type = "line", layer = "below",
             x0 = xmin, x1 = ranks[i],
             y0 = as.character(df$school_name[i]),
             y1 = as.character(df$school_name[i]),
             line = list(color = "rgba(148, 163, 184, 0.45)", width = 1.4))
      })

      plot_ly(
        data = df,
        type = "scatter",
        mode = "markers",
        y = ~school_name,
        x = stats::setNames(ranks, NULL),
        marker = list(
          color = fill_cols,
          size  = 14,
          line  = list(color = "rgba(15, 23, 42, 0.55)", width = 1)
        ),
        hovertemplate = paste0(tooltip_txt, "<extra></extra>")
      ) %>%
      common_layout(xtitle, extra = list(
        # autorange = TRUE; rangemode = "tozero" keeps the scale honest.
        rangemode = "tozero"
      )) %>%
      layout(shapes = stems)
    }
  })

  output$compare_table <- DT::renderDT({
    df <- compare_data()
    m  <- metric_meta()
    log_evt("compare_table", sprintf("rerender  n=%d", nrow(df)))

    if (nrow(df) == 0) {
      return(DT::datatable(
        data.frame(Message = "No schools match the current filter for this metric."),
        rownames = FALSE, options = list(dom = "t", paging = FALSE)
      ))
    }

    # Render percent / score / rank values as readable strings; NA -> "—".
    fmt_pct_cell   <- function(x) ifelse(is.na(x), "—", sprintf("%d%%",      as.integer(round(x))))
    fmt_score_cell <- function(x) ifelse(is.na(x), "—", sprintf("%.2f",      x))
    fmt_rank_cell  <- function(x) ifelse(is.na(x), "—", paste0("#", formatC(x, big.mark = ",", format = "d")))
    fmt_grad_cell  <- function(num, raw) {
      out <- ifelse(is.na(num), as.character(raw), sprintf("%d%%", as.integer(round(num))))
      ifelse(is.na(out) | out == "NA", "—", out)
    }

    pretty <- df %>%
      mutate(rank = row_number()) %>%
      transmute(
        Rank         = rank,
        School       = school_name,
        District     = district,
        `Overall Score`        = fmt_score_cell(overall_score),
        `Utah Ranking`         = fmt_rank_cell(state_rank),
        `National Ranking`     = fmt_rank_cell(national_rank),
        `AP Taken`             = fmt_pct_cell(ap_taken_pct),
        `AP Passed`            = fmt_pct_cell(ap_passed_pct),
        `Math Proficiency`     = fmt_pct_cell(math_proficiency),
        `Reading Proficiency`  = fmt_pct_cell(reading_proficiency),
        `Science Proficiency`  = fmt_pct_cell(science_proficiency),
        `Graduation Rate`      = fmt_grad_cell(graduation_rate, graduation_rate_raw)
      )

    # Map metric key -> matching column name in `pretty`, for highlighting.
    metric_to_col <- c(
      overall_score        = "Overall Score",
      state_rank           = "Utah Ranking",
      national_rank        = "National Ranking",
      ap_taken_pct         = "AP Taken",
      ap_passed_pct        = "AP Passed",
      math_proficiency     = "Math Proficiency",
      reading_proficiency  = "Reading Proficiency",
      science_proficiency  = "Science Proficiency",
      graduation_rate      = "Graduation Rate"
    )
    selected_col <- metric_to_col[[m$key]]

    dt <- DT::datatable(
      pretty,
      rownames = FALSE,
      class    = "stripe hover compact",
      escape   = FALSE,
      options  = list(
        pageLength = 25,
        lengthMenu = c(10, 25, 50, 100),
        dom        = 'lftrip',
        order      = list(),
        scrollX    = TRUE,        # horizontal scroll if window is narrow
        autoWidth  = FALSE,
        columnDefs = list(
          # Rank, Overall, ranks, percentages — numeric columns right-aligned.
          list(className = "dt-center", targets = 0),                 # Rank
          list(className = "dt-right",  targets = c(3, 4, 5, 6, 7, 8, 9, 10, 11))
        ),
        language   = list(search     = "Filter:",
                          lengthMenu = "Rows per page: _MENU_")
      )
    ) %>%
      DT::formatStyle("School",  fontWeight = "600", color = "#0f172a") %>%
      DT::formatStyle("Rank",    fontWeight = "700", color = "#475569")

    # Highlight the column that matches the user's chosen sort metric.
    if (!is.null(selected_col) && selected_col %in% names(pretty)) {
      dt <- dt %>% DT::formatStyle(
        selected_col,
        fontWeight = "700",
        color      = "#0f172a",
        background = "linear-gradient(180deg, #eff6ff 0%, #ffffff 100%)"
      )
    }
    dt
  })

  # ---- Detail panel (bottom right) — school card or multi-summary ---------
  output$school_stats <- renderUI({
    df <- filtered()
    log_evt("school_stats", sprintf("rerender  n=%d", nrow(df)))

    if (nrow(df) == 0) {
      return(div(class = "empty-card",
        bsicons::bs_icon("exclamation-circle", class = "empty-card-icon"),
        "No schools match the current filters."
      ))
    }

    if (nrow(df) > 1) {
      return(div(class = "empty-card",
        bsicons::bs_icon("hand-index-thumb", class = "empty-card-icon"),
        sprintf("%d schools in this district.", nrow(df)),
        tags$br(),
        tags$small("Click any marker to see its scorecard.",
                   style = "color:var(--text-tertiary); font-size:11.5px;")
      ))
    }

    s <- df[1, ]
    div(class = "school-card",
      div(class = "detail-eyebrow", s$district),
      div(class = "detail-title",   s$school_name),
      div(class = "detail-address",
        bsicons::bs_icon("geo-alt"),
        span(s$address)
      ),

      div(class = "stat-section",
        div(class = "stat-section-title", "Rankings"),
        stat_row("Overall Score",  fmt_score(s$overall_score)),
        stat_row("Utah Rank",      fmt_rank(s$state_rank)),
        stat_row("National Rank",  fmt_rank(s$national_rank))
      ),

      div(class = "stat-section",
        div(class = "stat-section-title", "Advanced Placement"),
        stat_row("Took an AP Exam",   fmt_pct(s$ap_taken_pct)),
        stat_row("Passed an AP Exam", fmt_pct(s$ap_passed_pct))
      ),

      div(class = "stat-section",
        div(class = "stat-section-title", "Subject Proficiency"),
        stat_row("Mathematics", fmt_pct(s$math_proficiency)),
        stat_row("Reading",     fmt_pct(s$reading_proficiency)),
        stat_row("Science",     fmt_pct(s$science_proficiency))
      ),

      div(class = "stat-section",
        div(class = "stat-section-title", "Outcomes"),
        stat_row("Graduation Rate",
                 fmt_grad(s$graduation_rate, s$graduation_rate_raw))
      ),

      if (!is.na(s$source_url))
        tags$a(class = "source-link",
               href = s$source_url, target = "_blank",
               bsicons::bs_icon("box-arrow-up-right"),
               "View on U.S. News")
    )
  })
}
