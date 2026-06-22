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
    # State filter (multi-select; default = all). A brief NULL before the input
    # registers, or an empty selection, is treated as "all states".
    sel_states <- input$states
    if (!is.null(sel_states) && length(sel_states) > 0)
      df <- df %>% filter(state %in% sel_states)
    if (!is.null(input$district) && input$district != "All districts")
      df <- df %>% filter(district == input$district)
    if (!is.null(input$school) && input$school != "All schools")
      df <- df %>% filter(school_name == input$school)
    log_evt("filtered()",
            sprintf("states=%d  district=%s  school=%s  -> %d rows",
                    length(sel_states), input$district %||% "NA",
                    input$school %||% "NA", nrow(df)))
    df
  })

  # ---- Map zoom level: "overview" vs "detail" -------------------------------
  # OVERVIEW = the pure default (all states selected, no district/school): the
  # map shows one shape + one count bubble per state. Any narrowing — a subset
  # of states, or a chosen district/school — flips to DETAIL, which breaks out
  # the individual district polygons and per-school markers.
  all_states_selected <- function() {
    s <- input$states
    is.null(s) || length(s) == 0 || setequal(s, all_states)
  }
  map_mode <- reactive({
    if (all_states_selected() &&
        (input$district %||% "All districts") == "All districts" &&
        (input$school   %||% "All schools")   == "All schools") "overview" else "detail"
  })

  # In DETAIL mode, which states' district polygons to draw: the selected subset
  # if one is chosen, otherwise the state(s) of the chosen school/district (so
  # picking a single district while all states are selected only draws that
  # district's home state, not all 1,300+ polygons).
  focus_states <- reactive({
    s <- input$states
    if (!is.null(s) && length(s) > 0 && !setequal(s, all_states)) return(s)
    if ((input$school %||% "All schools") != "All schools")
      return(unique(schools$state[schools$school_name == input$school]))
    if ((input$district %||% "All districts") != "All districts")
      return(unique(schools$state[schools$district == input$district]))
    all_states
  })

  # When a school is picked from the legend search, the district filter is
  # switched to that school's district — which would normally reset the School
  # dropdown to "All schools". We stash the desired school here so the observer
  # below re-selects it after repopulating the choices.
  pending_school <- reactiveVal(NULL)

  # Keep the "School" dropdown in sync with the chosen district (and the
  # selected states, so the list never offers a school that's filtered out).
  observeEvent(input$district, {
    log_evt("input$district", sprintf("changed -> %s", input$district))
    df <- schools
    if (!is.null(input$states) && length(input$states) > 0)
      df <- df %>% filter(state %in% input$states)
    if (input$district != "All districts") df <- df %>% filter(district == input$district)
    sel <- pending_school()
    updateSelectInput(
      session, "school",
      choices  = c("All schools", sort(unique(df$school_name))),
      selected = if (!is.null(sel) && sel %in% df$school_name) sel else "All schools"
    )
    if (!is.null(sel)) pending_school(NULL)
  })

  # Keep the "District" dropdown scoped to the selected states. Changing states
  # repopulates the district choices; if the current district is no longer
  # available it falls back to "All districts" (which cascades to School above).
  observeEvent(input$states, {
    df <- schools
    if (!is.null(input$states) && length(input$states) > 0)
      df <- df %>% filter(state %in% input$states)
    dist_choices <- c("All districts", sort(unique(df$district)))
    cur <- if (!is.null(input$district) && input$district %in% dist_choices)
             input$district else "All districts"
    log_evt("input$states", sprintf("changed -> %d states; %d district choices",
                                     length(input$states), length(dist_choices) - 1))
    updateSelectInput(session, "district", choices = dist_choices, selected = cur)
  }, ignoreNULL = FALSE)

  observeEvent(input$school, {
    log_evt("input$school", sprintf("changed -> %s", input$school))
  }, ignoreInit = TRUE)

  # ---- Base map (renders once) ----------------------------------------------
  # Tiles only; district polygons are drawn (and redrawn on state-filter change)
  # by the observer below so the map shows only the selected states' areas.
  output$map <- renderLeaflet({
    log_evt("renderLeaflet", "building base map (tiles only; polygons via proxy)")
    leaflet() %>%
      addProviderTiles(providers$CartoDB.Positron) %>%
      fitBounds(DATA_BBOX$lng1, DATA_BBOX$lat1,
                DATA_BBOX$lng2, DATA_BBOX$lat2)
  })

  # ---- Draw the map's polygon layer (two zoom levels) -----------------------
  # Redraws (clear + re-add) whenever the state filter changes:
  #   * DEFAULT (all states selected) -> one single-color shape per STATE with a
  #     state-average hover card. Clicking a state drills in (see shape_click).
  #   * SUBSET (a state clicked or the filter narrowed) -> the individual
  #     district polygons for the selected states, with district-average hovers.
  hover_opts <- labelOptions(
    direction = "auto",
    sticky    = TRUE,             # follow the cursor across large polygons
    opacity   = 1,
    className = "district-hover-tooltip"
  )

  observe({
    proxy <- leafletProxy("map") %>% clearShapes()

    if (map_mode() == "overview") {
      # ----- State-level choropleth (default overview) -----
      log_evt("polygon obs", sprintf("state view: %d state shapes",
                                     nrow(state_polygons)))
      if (nrow(state_polygons) == 0) return()
      proxy %>% addPolygons(
        data        = state_polygons,
        fillColor   = ~state_pal(state),
        fillOpacity = 0.30,
        color       = "#333",
        weight      = 1.2,
        label       = state_hover_labels,
        labelOptions = hover_opts,
        layerId     = ~state,
        group       = "states",
        highlightOptions = highlightOptions(
          weight = 3, color = "#000", fillOpacity = 0.50, bringToFront = FALSE
        )
      )
    } else {
      # ----- District-level (drilled into the focus states) -----
      idx <- which(district_polygons$state %in% focus_states())
      log_evt("polygon obs", sprintf("district view: %d / %d district polygons",
                                     length(idx), nrow(district_polygons)))
      if (length(idx) == 0) return()
      polys <- district_polygons[idx, ]
      # "State || District" composite keeps same-named districts in different
      # states distinct on the map.
      polys$poly_id <- paste(polys$state, polys$usnews_district, sep = " || ")
      proxy %>% addPolygons(
        data        = polys,
        fillColor   = ~state_pal(state),
        fillOpacity = 0.35,
        color       = "#333",
        weight      = 1,
        label       = polygon_hover_labels[idx],
        labelOptions = hover_opts,
        layerId     = ~poly_id,
        group       = "districts",
        highlightOptions = highlightOptions(
          weight = 3, color = "#000", fillOpacity = 0.55, bringToFront = FALSE
        )
      )
    }
  })

  # ---- Update markers when the filter changes -------------------------------
  observe({
    proxy <- leafletProxy("map") %>%
      clearMarkers() %>%
      clearMarkerClusters()

    # OVERVIEW: one count bubble per state (total high schools), instead of every
    # individual school marker. The bubble is a label-only marker; its pill has
    # pointer-events:none so hover/click fall through to the state polygon
    # (state-average KPI on hover, drill-in on click).
    if (map_mode() == "overview") {
      ss <- state_summary[is.finite(state_summary$lng) &
                          is.finite(state_summary$lat), ]
      log_evt("markers obs", sprintf("overview: %d state count bubbles", nrow(ss)))
      if (nrow(ss) > 0) {
        # The badge is the obvious click target, so make it drill into its state
        # directly (onclick -> state_pick). The state polygon underneath is also
        # clickable (shape_click), so either lands the user in that state.
        badges <- lapply(seq_len(nrow(ss)), function(i)
          htmltools::HTML(sprintf(
            "<div class='state-count-badge' onclick=\"Shiny.setInputValue('state_pick','%s',{priority:'event'})\">%s <span class='scb-label'>school%s</span></div>",
            ss$state[i],
            formatC(ss$n_schools[i], big.mark = ","),
            if (ss$n_schools[i] == 1) "" else "s")))
        proxy %>% addLabelOnlyMarkers(
          lng   = ss$lng, lat = ss$lat,
          label = badges,
          labelOptions = labelOptions(
            noHide = TRUE, direction = "center", textOnly = TRUE,
            className = "state-count-tip"
          ),
          group = "schools"
        )
      }
      proxy %>% fitBounds(DATA_BBOX$lng1, DATA_BBOX$lat1,
                          DATA_BBOX$lng2, DATA_BBOX$lat2)
      return()
    }

    # DETAIL: individual school markers for the current filter.
    df <- filtered() %>% filter(!is.na(latitude) & !is.na(longitude))
    log_evt("markers obs", sprintf("detail: rendering %d circle markers", nrow(df)))

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
      fillColor   = unname(state_pal(df$state)),
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

    # Auto-fit (detail mode only — the overview frames DATA_BBOX above):
    #   1. A single specific school selected -> zoom in tight on it.
    #   2. Otherwise -> fit to the bounding box of the schools in view (one
    #      state, one district, etc.), which naturally zooms to AK or HI when
    #      they're the selection.
    if (input$school != "All schools" && nrow(df) == 1) {
      log_evt("auto-fit", sprintf("branch=school  zoom 14 on %s",
                                  df$school_name))
      proxy %>% setView(lng = df$longitude, lat = df$latitude, zoom = 14)
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

  # ---- Clicking a polygon ---------------------------------------------------
  # In the default state view, clicking a STATE drills into it (narrows the
  # state filter to that one state, which flips the map to its districts). In
  # the district view, clicking a DISTRICT selects it in the sidebar.
  observeEvent(input$map_shape_click, {
    click <- input$map_shape_click
    log_evt("shape_click",
            sprintf("id=%s  group=%s  lat=%.4f  lng=%.4f  len=%d",
                    deparse(click$id), deparse(click$group),
                    click$lat %||% NA, click$lng %||% NA,
                    length(click$id)))

    id <- click$id
    if (length(id) != 1) {
      log_evt("shape_click", "  -> id length != 1, ignoring")
      return()
    }

    if (isTRUE(click$group == "states")) {
      if (id %in% all_states) {
        log_evt("shape_click", sprintf("  -> state '%s' clicked, drilling to its districts", id))
        updateSelectInput(session, "states", selected = id)
      }
      return()
    }

    if (isTRUE(click$group == "districts")) {
      # layerId is a "State || District" composite; recover the district name.
      parts <- strsplit(as.character(id), " || ", fixed = TRUE)[[1]]
      dist  <- if (length(parts) == 2) parts[[2]] else as.character(id)
      if (dist %in% schools$district) {
        log_evt("shape_click", sprintf("  -> updating input$district to %s", dist))
        updateSelectInput(session, "district", selected = dist)
      } else {
        log_evt("shape_click", sprintf("  -> %s not in schools$district, ignoring", dist))
      }
      return()
    }
  })

  # ---- Clicking a state count bubble drills into that state -----------------
  observeEvent(input$state_pick, {
    pick <- input$state_pick
    log_evt("state_pick", sprintf("count bubble clicked -> %s", pick))
    if (is.character(pick) && length(pick) == 1 && pick %in% all_states) {
      updateSelectInput(session, "states", selected = pick)
    }
  })

  # =========================================================================
  # RANKING TABLE (right side) — drill-down: states -> districts -> schools
  # =========================================================================
  # The table's level is DERIVED from the active filters, so the table and the
  # map always stay in sync (a row click just advances the same filters the map
  # already reads):
  #   * all states selected             -> rank every STATE
  #   * exactly one state, no district   -> rank that state's DISTRICTS
  #   * a district selected              -> rank that district's SCHOOLS
  rank_level <- reactive({
    st <- input$states
    one_state <- !is.null(st) && length(st) == 1 && st %in% all_states
    if ((input$district %||% "All districts") != "All districts") return("school")
    if (one_state) return("district")
    "state"
  })

  # The state in context when drilling below the top level. In the normal drill
  # path input$states is the single chosen state; fall back to the focus state
  # (e.g. a district picked via search while all states were still selected).
  rank_state <- reactive({
    st <- input$states
    if (!is.null(st) && length(st) == 1 && st %in% all_states) return(st)
    focus_states()[1]
  })

  # The ranked data frame for the current level, plus the entity (row) names in
  # display order so a row click maps straight back to a state/district/school.
  rank_data <- reactive({
    lvl <- rank_level()
    if (lvl == "district") {
      st   <- rank_state()
      base <- dplyr::filter(schools, state == st)
      rk   <- compute_prof_ranking(base, "district")
      list(level = lvl, df = rk, entities = rk$district, name_header = "District",
           base = base, summary_label = st)
    } else if (lvl == "school") {
      st   <- rank_state(); dsel <- input$district
      base <- dplyr::filter(schools, state == st, district == dsel)
      rk   <- compute_prof_ranking(base, "school_name")
      list(level = lvl, df = rk, entities = rk$school_name, name_header = "School",
           base = base, summary_label = dsel)
    } else {
      list(level = "state", df = state_rankings,
           entities = state_rankings$state, name_header = "State",
           base = schools, summary_label = "All states")
    }
  })

  output$state_rank_table <- DT::renderDT({
    rd   <- rank_data()
    # At the school level the detail card shares the right column, so cap the
    # list to the top ~half; otherwise the list uses the full column height.
    scroll_y <- if (rd$level == "school") "calc(52vh - 140px)" else "calc(100vh - 360px)"
    fmt1 <- function(x) ifelse(is.na(x) | is.nan(x), NA_real_, round(x, 1))
    ranked <- data.frame(
      `#`   = ifelse(is.na(rd$df$rank), "", as.character(rd$df$rank)),
      Name  = rd$entities,
      Read  = fmt1(rd$df$reading),
      Math  = fmt1(rd$df$math),
      Sci   = fmt1(rd$df$science),
      Index = fmt1(rd$df$prof_index),
      check.names = FALSE, stringsAsFactors = FALSE
    )
    # Colour-bar range from the ranked rows only (the average row is excluded so
    # it doesn't skew the scale).
    vals    <- ranked$Index[is.finite(ranked$Index)]
    idx_rng <- if (length(vals)) range(vals) else c(0, 100)

    # ---- Pinned "average" row (the same figures as the top KPI bar, for the
    # current scope): all states at the state level, the chosen state's average
    # above its districts, the chosen district's average above its schools. So
    # the overall numbers sit right here and you needn't glance at the top bar.
    agg <- function(col) {
      m <- mean(rd$base[[col]], na.rm = TRUE); if (is.nan(m)) NA_real_ else round(m, 1)
    }
    sr_read <- agg("reading_proficiency"); sr_math <- agg("math_proficiency")
    sr_sci  <- agg("science_proficiency")
    sr_idx  <- mean(c(sr_read, sr_math, sr_sci), na.rm = TRUE)
    sr_idx  <- if (is.nan(sr_idx)) NA_real_ else round(sr_idx, 1)
    summary_row <- data.frame(
      `#` = "", Name = rd$summary_label,
      Read = sr_read, Math = sr_math, Sci = sr_sci, Index = sr_idx,
      check.names = FALSE, stringsAsFactors = FALSE
    )
    tab <- rbind(summary_row, ranked)

    DT::datatable(
      tab,
      rownames  = FALSE,
      colnames  = c("#", rd$name_header, "Read", "Math", "Sci", "Index"),
      selection = "single",
      class     = "compact stripe hover row-border state-rank-dt",
      options   = list(
        dom            = "t",
        paging         = FALSE,
        scrollY        = scroll_y,
        scrollCollapse = TRUE,
        # Sorting off so the average row stays pinned at the top and the rows
        # keep their best-first rank order.
        ordering       = FALSE,
        columnDefs     = list(
          list(className = "dt-center", targets = c(0, 2, 3, 4, 5)),
          list(width = "34px", targets = 0)
        )
      )
    ) %>%
      DT::formatRound(c("Read", "Math", "Sci", "Index"), digits = 1) %>%
      DT::formatStyle("#",    color = "#64748b", fontWeight = "700") %>%
      DT::formatStyle("Name", fontWeight = "600", color = "#0f172a") %>%
      DT::formatStyle(
        "Index",
        fontWeight = "700", color = "#0f172a",
        background = DT::styleColorBar(idx_rng, "#bfdbfe"),
        backgroundSize     = "98% 62%",
        backgroundRepeat   = "no-repeat",
        backgroundPosition = "center"
      )
  }, server = FALSE)

  # Breadcrumb header — All States > {State} > {District}; earlier crumbs are
  # clickable to climb back up the hierarchy.
  output$rank_breadcrumb <- renderUI({
    lvl <- rank_level()
    sep <- span(class = "rank-crumb-sep", bsicons::bs_icon("chevron-right"))
    root <- if (lvl == "state")
      span(class = "rank-crumb rank-crumb-cur", "All States")
    else
      actionLink("rank_crumb_root", "All States",
                 class = "rank-crumb rank-crumb-link")
    if (lvl == "state")
      return(div(class = "rank-crumbs", root))
    if (lvl == "district")
      return(div(class = "rank-crumbs", root, sep,
                 span(class = "rank-crumb rank-crumb-cur", rank_state())))
    div(class = "rank-crumbs", root, sep,
        actionLink("rank_crumb_state", rank_state(),
                   class = "rank-crumb rank-crumb-link"),
        sep, span(class = "rank-crumb rank-crumb-cur", input$district))
  })

  # Crumb clicks reset the relevant filters (req() ignores the unclicked/0 value
  # the link resets to each time the breadcrumb is re-rendered).
  observeEvent(input$rank_crumb_root, {
    req(input$rank_crumb_root)
    log_evt("rank_crumb", "root -> reset to all states")
    updateSelectInput(session, "states",   selected = all_states)
    updateSelectInput(session, "district", selected = "All districts")
    updateSelectInput(session, "school",   selected = "All schools")
  }, ignoreInit = TRUE)
  observeEvent(input$rank_crumb_state, {
    req(input$rank_crumb_state)
    log_evt("rank_crumb", sprintf("state -> back to %s districts", rank_state()))
    updateSelectInput(session, "district", selected = "All districts")
    updateSelectInput(session, "school",   selected = "All schools")
  }, ignoreInit = TRUE)

  # Keep the panel visible at every level; clear any stale row highlight when the
  # level changes. At the school level the detail card shares the right column,
  # so shrink it (CSS .detail-compact) to tile beneath the school list.
  observeEvent(rank_level(), {
    shinyjs::show("state_rank_panel")
    DT::dataTableProxy("state_rank_table") %>% DT::selectRows(NULL)
    if (rank_level() == "school") {
      shinyjs::addClass("detail_panel", "detail-compact")
    } else {
      shinyjs::removeClass("detail_panel", "detail-compact")
    }
  }, ignoreInit = TRUE)

  # Clicking a row advances the drill-down: state -> its districts, district ->
  # its schools, school -> opens its detail card. Rows are in display order, so
  # the selected index maps back to the entity via rank_data()$entities.
  observeEvent(input$state_rank_table_rows_selected, {
    i <- input$state_rank_table_rows_selected
    if (length(i) != 1) return()
    # Row 1 is the pinned "average" row — not drillable; clear its highlight.
    if (i == 1) {
      DT::dataTableProxy("state_rank_table") %>% DT::selectRows(NULL)
      return()
    }
    rd  <- rank_data()
    ent <- rd$entities[i - 1]          # offset past the pinned average row
    if (is.na(ent)) return()
    log_evt("rank_row_click", sprintf("%s level, row %d -> %s", rd$level, i, ent))
    if (rd$level == "state") {
      if (ent %in% all_states) updateSelectInput(session, "states", selected = ent)
    } else if (rd$level == "district") {
      updateSelectInput(session, "district", selected = ent)
    } else {
      updateSelectInput(session, "school", selected = ent)
    }
  })

  # ---- "Why are some values blank?" data-coverage info modal ----------------
  # Data-driven from coverage_notes (global.R): the per-state list of KPIs that
  # U.S. News doesn't publish at all, plus the general reasons values go blank.
  show_data_notes <- function() {
    reason <- function(icon, title, body)
      div(class = "dn-reason",
        div(class = "dn-reason-icon", bsicons::bs_icon(icon)),
        div(div(class = "dn-reason-title", title),
            div(class = "dn-reason-body", body)))

    prof       <- c("Math Proficiency", "Reading Proficiency", "Science Proficiency")
    gap_states <- Filter(function(x) length(x$missing) > 0, coverage_notes)

    state_blocks <- lapply(gap_states, function(x) {
      detail <- if (all(prof %in% x$missing))
        "U.S. News shows only a State Assessment Proficiency rank for this state — not the underlying math, reading, or science percentages."
      else
        "U.S. News doesn't publish this subject for this state's schools (verified against the source pages)."
      div(class = "dn-state",
        div(class = "dn-state-head",
          span(class = "dn-state-name", x$state),
          span(class = "dn-state-count",
               sprintf("%d schools · %d%% ranked", x$n, x$pct_ranked))
        ),
        div(class = "dn-pills", lapply(x$missing, function(m) span(class = "dn-pill", m))),
        div(class = "dn-state-detail", detail)
      )
    })

    showModal(modalDialog(
      easyClose = TRUE, size = "l", footer = modalButton("Got it"),
      div(class = "data-notes",
        div(class = "dn-head",
          div(class = "dn-head-icon", bsicons::bs_icon("clipboard2-data-fill")),
          div(
            h3(class = "dn-title", "Why are some values blank?"),
            p(class = "dn-lead",
              sprintf("Every metric comes straight from the U.S. News %s Best High Schools data. A cell is blank only when U.S. News itself doesn't publish that value — nothing is dropped here.",
                      "2025-2026"))
          )
        ),
        div(class = "dn-reasons",
          reason("trophy-fill", "Unranked schools",
                 "U.S. News scores and ranks only a share of each state's schools. Unranked schools are still listed, but with no overall score, rank, AP, or proficiency values."),
          reason("clipboard-x-fill", "Subjects a state doesn't report",
                 "For some states, U.S. News shows only a proficiency ranking — not the underlying math/reading/science percentages — so those columns are blank for the whole state."),
          reason("hash", "Ranges instead of numbers",
                 "A few values are published as ranges ('>= 80%') or 'N/A' rather than an exact number, so they can't be averaged and show as blank.")
        ),
        h4(class = "dn-subhead",
           sprintf("States missing an entire metric (%d)", length(gap_states))),
        div(class = "dn-states", state_blocks),
        p(class = "dn-foot",
          "Every other state reports the full set of metrics for the schools U.S. News ranks.")
      )
    ))
  }
  observeEvent(input$data_coverage_info,      show_data_notes())
  observeEvent(input$data_coverage_info_foot, show_data_notes())

  # ---- Reset button ---------------------------------------------------------
  observeEvent(input$reset_view, {
    log_evt("reset_view", "clicked -> resetting filters and map view")
    updateSelectInput(session, "states",   selected = all_states)
    updateSelectInput(session, "district", selected = "All districts")
    updateSelectInput(session, "school",   selected = "All schools")
    leafletProxy("map") %>%
      fitBounds(DATA_BBOX$lng1, DATA_BBOX$lat1,
                DATA_BBOX$lng2, DATA_BBOX$lat2)
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
    math       = "Percentage of students who scored proficient on the state-administered mathematics assessment.",
    reading    = "Percentage of students who scored proficient on the state-administered reading assessment.",
    science    = "Percentage of students who scored proficient on the state-administered science assessment.",
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
    # State-level scope: one state selected -> name it; a few -> count them.
    sel <- input$states
    if (!is.null(sel) && length(sel) > 0 && !setequal(sel, all_states)) {
      if (length(sel) == 1) return(list(name = sel, kind = "state"))
      return(list(name = sprintf("%d states", length(sel)), kind = "state"))
    }
    list(name = "All states", kind = "all")
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
      "all"      = "All school averages",
      "state"    = sprintf("%s averages", scope$name),
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
          span(class = "data-year-pill",
               bsicons::bs_icon("calendar3"), DATA_YEAR),
          span(sprintf("Based on %d school%s",
                       avg$n, if (avg$n == 1) "" else "s"))
        )
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
      "state"    = if (length(input$states %||% character(0)) == 1) "State" else "States",
      "district" = "District",
      "school"   = "School")

    # Surface the school / district (/ state) counts for the current selection.
    meta <- if (scope$kind == "all") {
      sprintf("%d schools  ·  %d districts  ·  %d states",
              nrow(df), dplyr::n_distinct(df$state, df$district),
              dplyr::n_distinct(df$state))
    } else if (scope$kind == "state") {
      sprintf("%d schools  ·  %d districts",
              nrow(df), dplyr::n_distinct(df$state, df$district))
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
  # DISTRICT LEGEND  (inside the floating control panel)
  # =========================================================================
  # Counted per (state, district) so same-named districts in different states
  # stay distinct.
  district_counts <- schools %>% count(state, district, name = "n_schools")

  build_legend_item <- function(name, state, count, is_active) {
    div(
      class       = paste("legend-item", if (is_active) "is-active" else ""),
      `data-district` = name,
      tabindex    = "0",
      role        = "button",
      `aria-label` = sprintf("Filter map to %s", name),
      onclick     = sprintf(
        "Shiny.setInputValue('legend_pick', %s, {priority:'event'});",
        jsonlite::toJSON(name, auto_unbox = TRUE)
      ),
      onkeydown   = sprintf(
        "if(event.key==='Enter'||event.key===' '){event.preventDefault();Shiny.setInputValue('legend_pick', %s, {priority:'event'});}",
        jsonlite::toJSON(name, auto_unbox = TRUE)
      ),
      title       = sprintf("%s — %d school%s",
                            name, count, if (count == 1) "" else "s"),
      div(class = "legend-item-swatch",
          style = sprintf("background:%s;", unname(state_pal(state)))),
      div(class = "legend-item-text",
        span(class = "legend-item-name", name),
        span(class = "legend-item-meta",
             sprintf("%d school%s", count, if (count == 1) "" else "s"))
      ),
      bsicons::bs_icon("chevron-right", class = "legend-item-arrow")
    )
  }

  # A search-result row for an individual school (vs a district row above).
  # Clicking it sets input$school_pick; the swatch uses the school's state color
  # and the meta line shows which district it belongs to.
  build_school_item <- function(name, district, state) {
    div(
      class           = "legend-item legend-item-school",
      `data-school`   = name,
      tabindex        = "0",
      role            = "button",
      `aria-label`    = sprintf("Show %s in %s", name, district),
      onclick         = sprintf(
        "Shiny.setInputValue('school_pick', %s, {priority:'event'});",
        jsonlite::toJSON(name, auto_unbox = TRUE)
      ),
      onkeydown       = sprintf(
        "if(event.key==='Enter'||event.key===' '){event.preventDefault();Shiny.setInputValue('school_pick', %s, {priority:'event'});}",
        jsonlite::toJSON(name, auto_unbox = TRUE)
      ),
      title           = sprintf("%s — %s", name, district),
      div(class = "legend-item-swatch",
          style = sprintf("background:%s;", unname(state_pal(state)))),
      div(class = "legend-item-text",
        span(class = "legend-item-name", name),
        span(class = "legend-item-meta", district)
      ),
      bsicons::bs_icon("geo-alt", class = "legend-item-arrow")
    )
  }

  output$district_legend <- renderUI({
    query    <- tolower(input$legend_search %||% "")
    selected <- input$district %||% "All districts"
    sel_states <- input$states
    if (is.null(sel_states) || length(sel_states) == 0) sel_states <- all_states

    # District rows for the selected states, sorted by state then district, and
    # filtered by the search box when one is active.
    dc <- district_counts[district_counts$state %in% sel_states, ]
    if (nzchar(query)) dc <- dc[grepl(query, tolower(dc$district), fixed = TRUE), ]
    dc <- dc[order(dc$state, dc$district), ]

    # Individual schools surface only while searching (scoped to the selected
    # states), so the default view stays a clean district list.
    school_hits <- schools[0, c("school_name", "district", "state")]
    if (nzchar(query)) {
      sh <- schools[schools$state %in% sel_states &
                    grepl(query, tolower(schools$school_name), fixed = TRUE), ]
      school_hits <- sh[order(sh$school_name), c("school_name", "district", "state")]
    }

    if (nrow(dc) == 0 && nrow(school_hits) == 0) {
      return(div(class = "legend-empty",
        bsicons::bs_icon("search"),
        "No districts or schools match your search."
      ))
    }

    # Cap district rows so selecting many states (1,000+ districts) renders fast.
    cap_d       <- 300L
    truncated_d <- nrow(dc) > cap_d
    dc_shown    <- utils::head(dc, cap_d)

    # One group per state, listing that state's districts (colored by state).
    state_group <- function(st) {
      rows <- dc_shown[dc_shown$state == st, ]
      if (nrow(rows) == 0) return(NULL)
      div(class = "legend-group",
        div(class = "legend-group-head",
          span(st),
          span(class = "legend-group-count", nrow(rows))
        ),
        div(class = "legend-group-body",
          lapply(seq_len(nrow(rows)), function(i)
            build_legend_item(rows$district[i], rows$state[i], rows$n_schools[i],
                              is_active = (rows$district[i] == selected)))
        )
      )
    }
    district_groups <- lapply(sort(unique(dc_shown$state)), state_group)

    # Schools group (search results only), capped so the list stays usable.
    school_group <- NULL
    if (nrow(school_hits) > 0) {
      cap_s <- 50L
      shown <- utils::head(school_hits, cap_s)
      school_group <- div(class = "legend-group",
        div(class = "legend-group-head",
          span("Schools"),
          span(class = "legend-group-count", nrow(school_hits))
        ),
        div(class = "legend-group-body",
          lapply(seq_len(nrow(shown)), function(i)
            build_school_item(shown$school_name[i], shown$district[i], shown$state[i]))
        ),
        if (nrow(school_hits) > cap_s)
          div(class = "legend-more-note",
              sprintf("Showing first %d of %d — keep typing to narrow.",
                      cap_s, nrow(school_hits)))
      )
    }

    tagList(
      district_groups,
      if (truncated_d)
        div(class = "legend-more-note",
            sprintf("Showing first %d of %d districts — search or select fewer states to narrow.",
                    cap_d, nrow(dc))),
      school_group
    )
  })

  # Click a legend row -> set the district filter (toggles off if already on).
  observeEvent(input$legend_pick, {
    pick <- input$legend_pick
    log_evt("legend_pick", sprintf("user picked '%s'", pick))
    if (!is.character(pick) || length(pick) != 1) return()
    if (!(pick %in% schools$district)) return()

    if (identical(input$district, pick)) {
      updateSelectInput(session, "district", selected = "All districts")
    } else {
      updateSelectInput(session, "district", selected = pick)
    }
  })

  # Click a school search result -> select that school. We switch the district
  # filter to the school's district so the dropdowns and map agree; the
  # pending_school() relay keeps the school selected through that change.
  observeEvent(input$school_pick, {
    pick <- input$school_pick
    log_evt("school_pick", sprintf("user picked '%s'", pick))
    if (!is.character(pick) || length(pick) != 1) return()
    if (!(pick %in% schools$school_name)) return()

    dist <- schools$district[schools$school_name == pick][1]
    if (!identical(input$district, dist)) {
      pending_school(pick)
      updateSelectInput(session, "district", selected = dist)
    } else {
      updateSelectInput(session, "school", selected = pick)
    }
  })

  # When the district changes (via dropdown, polygon click, or legend),
  # scroll the matching legend row into view inside the list container.
  observeEvent(input$district, {
    if (!is.null(input$district) && input$district != "All districts") {
      shinyjs::runjs(sprintf(
        "(function(){
           var d = %s;
           var el = document.querySelector('[data-district=\"' + d + '\"]');
           if (el) el.scrollIntoView({block:'nearest', behavior:'smooth'});
         })();",
        jsonlite::toJSON(input$district, auto_unbox = TRUE)
      ))
    }
  }, ignoreInit = TRUE)

  # ---- Suppress the redundant district hover card --------------------------
  # When a mapped district is the active filter, the top KPI panel already
  # shows that district's averages, so its polygon hover card would just
  # duplicate them. Hide only that one card (other districts keep their cards
  # so the map stays explorable). Implemented as an injected CSS rule keyed to
  # the card's data-dh-district attribute — no polygon redraw, so no flicker.
  observeEvent(input$district, {
    sel       <- input$district
    is_mapped <- !is.null(sel) && sel != "All districts" &&
                 sel %in% district_polygons$usnews_district
    log_evt("hover_suppress", sprintf("district=%s  suppress=%s", sel, is_mapped))

    if (is_mapped) {
      rule <- sprintf(
        ".district-hover-card[data-dh-district=\"%s\"]{display:none !important;}",
        sel
      )
      shinyjs::runjs(sprintf(
        "(function(){var s=document.getElementById('dh-suppress')||(function(){var e=document.createElement('style');e.id='dh-suppress';document.head.appendChild(e);return e;})();s.textContent=%s;})();",
        jsonlite::toJSON(rule, auto_unbox = TRUE)
      ))
    } else {
      shinyjs::runjs("var s=document.getElementById('dh-suppress'); if(s){s.textContent='';}")
    }
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

  # ---- Per-metric plain-language descriptions ------------------------------
  # Each entry pairs a Compare-tab metric with a one-sentence definition and
  # (where applicable) a pointer to the U.S. News indicator + weight it feeds.
  # Rendered in the floating callout below the Compare controls grid.
  metric_descriptions <- list(
    overall_score        = "National percentile (0-100) summarizing all six U.S. News indicators. Higher is better. Top-ranked schools score in the 90s; bottom-quartile scores are concealed in the source data.",
    state_rank           = "Each school's rank among Utah schools, sorted by Overall Score. #1 is the top-ranked school in the state.",
    national_rank        = "Each school's rank among the roughly 18,000 ranked U.S. public high schools. #1 is the top-ranked school in the nation.",
    ap_taken_pct         = "Share of 12th-graders who took at least one Advanced Placement exam by the end of senior year. Feeds the College Readiness Index (30% of the Overall Score).",
    ap_passed_pct        = "Share of 12th-graders who scored 3 or higher on at least one AP exam — the threshold for college-level mastery. Feeds the College Readiness Index (30%).",
    math_proficiency     = "Share of students scoring proficient on Utah's state mathematics assessment. Feeds State Assessment Proficiency (20%) and Performance (20%).",
    reading_proficiency  = "Share of students scoring proficient on Utah's state reading assessment. Feeds State Assessment Proficiency (20%) and Performance (20%).",
    science_proficiency  = "Share of students scoring proficient on Utah's state science assessment. Feeds State Assessment Proficiency (20%) and Performance (20%).",
    graduation_rate      = "Share of 2019-2020 ninth-grade entrants who graduated within four years (by 2023). Feeds the Graduation Rate indicator (10%)."
  )

  output$cmp_metric_desc <- renderUI({
    m <- input$cmp_metric
    desc <- metric_descriptions[[m]]
    if (is.null(desc)) return(NULL)
    label <- compare_metrics[[m]]$label
    div(class = "compare-metric-desc",
      bsicons::bs_icon("info-circle-fill"),
      span(tags$strong(label), " — ", desc)
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

  # Size the chart container to the row count: ~24px per bar (floored at 420px)
  # so 219 schools no longer crush into a 560px box with overlapping labels.
  output$compare_chart_wrap <- renderUI({
    n <- nrow(compare_data())
    h <- max(420, 24 * n)
    plotlyOutput("compare_chart", height = paste0(h, "px"))
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

    fill_cols <- unname(district_pal(df$district))

    # school_name is NOT a unique key — two different schools are both named
    # "Valley High School" (Jordan District and Kane District). Keying the
    # categorical y-axis on the bare name collapsed them onto a single category,
    # which stacked both schools into one hover tooltip (the repeated title) and
    # crashed factor() on the duplicate level. Build a unique per-row axis label:
    # append the district to any name shared by more than one school, with
    # make.unique() as a final safety net. The tooltip title keeps the plain
    # name, since the district already appears on its own line below it.
    dup_name   <- df$school_name %in% df$school_name[duplicated(df$school_name)]
    axis_label <- df$school_name
    axis_label[dup_name] <- sprintf("%s (%s)", df$school_name[dup_name], df$district[dup_name])
    axis_label <- make.unique(axis_label, sep = " #")

    # Y axis order: factor so the first row of df sits at the top.
    df$axis_label <- factor(axis_label, levels = rev(axis_label))

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
          tickfont = list(family = "Inter", size = 11, color = "#475569")
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
        y = ~axis_label,
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

      # Lollipop "stems" as line segments via shapes. y0/y1 must match the
      # categorical axis value, which is now the unique axis_label (not the
      # possibly-duplicated school_name).
      stems <- lapply(seq_len(nrow(df)), function(i) {
        list(type = "line", layer = "below",
             x0 = xmin, x1 = ranks[i],
             y0 = as.character(df$axis_label[i]),
             y1 = as.character(df$axis_label[i]),
             line = list(color = "rgba(148, 163, 184, 0.45)", width = 1.4))
      })

      plot_ly(
        data = df,
        type = "scatter",
        mode = "markers",
        y = ~axis_label,
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
      # Blank the column header (colnames = "") so the empty state reads as a
      # message, not a table with a literal "Message" column header.
      return(DT::datatable(
        data.frame(x = "No schools match the current filter for this metric."),
        rownames = FALSE, colnames = "", options = list(dom = "t", paging = FALSE)
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
