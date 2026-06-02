# ui.R — multi-tab dashboard: Map view + Compare schools

# ============================================================================
# CSS — single inline stylesheet
# ============================================================================
app_css <- "
:root {
  --bg-app: #f1f5f9;
  --bg-glass: rgba(255, 255, 255, 0.94);
  --bg-card-solid: #ffffff;
  --border-color: #e2e8f0;
  --text-primary: #0f172a;
  --text-secondary: #475569;
  --text-tertiary: #94a3b8;
  --color-primary: #2563eb;
  --color-primary-700: #1d4ed8;
  --color-primary-soft: #dbeafe;
  --color-primary-tint: #eff6ff;
  --shadow-xs: 0 1px 2px rgba(15, 23, 42, 0.04);
  --shadow-sm: 0 2px 6px rgba(15, 23, 42, 0.06);
  --shadow-md: 0 6px 18px rgba(15, 23, 42, 0.10);
  --shadow-lg: 0 12px 32px rgba(15, 23, 42, 0.14);
  --shadow-xl: 0 24px 48px rgba(15, 23, 42, 0.18);
  --radius-sm: 8px;
  --radius-md: 12px;
  --radius-lg: 16px;
}
* { box-sizing: border-box; }
html, body {
  margin: 0; padding: 0;
  font-family: 'Inter', -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
  font-size: 14px;
  color: var(--text-primary);
  background: var(--bg-app);
  -webkit-font-smoothing: antialiased;
}

/* ===================== NAVBAR ===================== */
.navbar {
  background: var(--bg-card-solid) !important;
  border-bottom: 1px solid var(--border-color) !important;
  box-shadow: 0 1px 0 rgba(15, 23, 42, 0.02), 0 2px 6px rgba(15, 23, 42, 0.04);
  padding: 0 24px !important;
  min-height: 64px;
  z-index: 1100;
}
.navbar .container-fluid,
.navbar > .container,
.navbar > .container-xl,
.navbar > .container-lg {
  padding: 0 !important; gap: 16px;
}

/* Brand block */
.navbar .navbar-brand {
  padding: 10px 18px 10px 0;
  margin-right: 12px;
  border-right: 1px solid var(--border-color);
  margin-left: 0;
}
.navbar-brand-content {
  display: flex; align-items: center; gap: 12px;
}
.brand-mark {
  width: 40px; height: 40px;
  display: flex; align-items: center; justify-content: center;
  background: linear-gradient(135deg, #2563eb 0%, #6366f1 100%);
  color: white;
  border-radius: 11px;
  box-shadow: 0 6px 16px rgba(37, 99, 235, 0.32),
              inset 0 0 0 1px rgba(255, 255, 255, 0.18);
  font-size: 18px;
}
.brand-title {
  font-size: 15px; font-weight: 700; letter-spacing: -0.01em; line-height: 1.2;
  color: var(--text-primary);
}
.brand-subtitle {
  font-size: 11px; color: var(--text-tertiary);
  margin-top: 2px;
  letter-spacing: 0.02em;
}

/* Tabs — bottom-border indicator style */
.navbar-nav { gap: 0; align-items: stretch; }
.navbar .nav-item { display: flex; }
.navbar .nav-link {
  font-size: 13px !important;
  font-weight: 600 !important;
  color: var(--text-secondary) !important;
  padding: 22px 18px 20px !important;
  border-radius: 0 !important;
  background: transparent !important;
  border: 0 !important;
  border-bottom: 2px solid transparent !important;
  transition: color 0.15s ease, border-color 0.15s ease, background 0.15s ease;
  display: inline-flex !important;
  align-items: center;
  gap: 8px;
  position: relative;
}
.navbar .nav-link svg { font-size: 15px; }
.navbar .nav-link:hover {
  color: var(--color-primary) !important;
  background: rgba(37, 99, 235, 0.04) !important;
}
.navbar .nav-link.active {
  color: var(--color-primary) !important;
  background: transparent !important;
  border-bottom-color: var(--color-primary) !important;
}

/* Right-side stat pill */
.navbar-stat-pill {
  display: inline-flex; align-items: center; gap: 9px;
  padding: 7px 14px;
  background: linear-gradient(135deg, #eff6ff 0%, #f0f7ff 100%);
  color: var(--color-primary);
  border-radius: 999px;
  font-size: 12px; font-weight: 600;
  border: 1px solid rgba(37, 99, 235, 0.18);
  box-shadow: var(--shadow-xs);
  font-variant-numeric: tabular-nums;
}
.navbar-stat-pill svg { font-size: 13px; }

/* ===================== MAP TAB ===================== */
.map-shell {
  position: relative;
  height: 100%;
  width: 100%;
  background: var(--bg-app);
}
#map { position: absolute !important; inset: 0 !important; }
.leaflet-container { background: #eef3f9 !important; }

/* KPI panel (top center) */
.kpi-panel {
  position: absolute;
  top: 20px; left: 50%;
  transform: translateX(-50%);
  z-index: 500;
  background: var(--bg-glass);
  -webkit-backdrop-filter: blur(14px) saturate(180%);
  backdrop-filter: blur(14px) saturate(180%);
  border: 1px solid rgba(255, 255, 255, 0.7);
  border-radius: var(--radius-lg);
  box-shadow: var(--shadow-lg);
  overflow: hidden;
  min-width: 720px;
  max-width: calc(100% - 700px);
  transition: box-shadow 0.2s ease;
}
.kpi-panel:hover { box-shadow: var(--shadow-xl); }
.kpi-panel-head {
  display: flex; align-items: center; justify-content: space-between;
  padding: 10px 16px 10px 18px;
  background: linear-gradient(180deg, rgba(255,255,255,0.45) 0%, rgba(255,255,255,0) 100%);
  border-bottom: 1px solid var(--border-color);
}
.kpi-panel-title {
  display: flex; align-items: center; gap: 8px;
  font-size: 12.5px; font-weight: 700;
  color: var(--text-primary);
}
.kpi-panel-title svg { color: var(--color-primary); font-size: 14px; }
.kpi-panel-meta {
  font-size: 11px; color: var(--text-tertiary);
  font-variant-numeric: tabular-nums;
}
.kpi-panel-body {
  display: flex; align-items: stretch;
  padding: 12px 4px;
}
.kpi-stat {
  flex: 1 1 0;
  min-width: 96px;
  padding: 4px 14px;
  border-right: 1px solid var(--border-color);
}
.kpi-stat:last-child { border-right: 0; }
.kpi-stat-head {
  display: flex; align-items: center; gap: 5px;
  color: var(--text-tertiary);
  font-size: 10px; font-weight: 700;
  text-transform: uppercase; letter-spacing: 0.06em;
  margin-bottom: 6px;
}
.kpi-stat-head > svg { color: var(--color-primary); font-size: 11px; }

/* Info icon — small, faded, lights up on hover.  Sits at the right edge of
   the stat header via margin-left:auto and triggers a Bootstrap tooltip. */
.kpi-info {
  margin-left: auto;
  display: inline-flex;
  align-items: center;
  cursor: help;
  color: var(--text-tertiary);
  font-size: 11px;
  opacity: 0.7;
  transition: color 0.15s ease, opacity 0.15s ease;
}
.kpi-info:hover {
  color: var(--color-primary);
  opacity: 1;
}
.kpi-info svg { font-size: 11.5px; }

/* Tone down the default Bootstrap tooltip to match the app's look. */
.tooltip-inner {
  background: #0f172a !important;
  color: #f8fafc !important;
  font-family: 'Inter', sans-serif !important;
  font-size: 12px !important;
  font-weight: 500 !important;
  padding: 8px 11px !important;
  border-radius: 8px !important;
  max-width: 260px !important;
  text-align: left !important;
  line-height: 1.4 !important;
  letter-spacing: 0;
  box-shadow: 0 8px 24px rgba(15, 23, 42, 0.25) !important;
}
.tooltip-arrow::before, .tooltip .tooltip-arrow::before,
.bs-tooltip-top .tooltip-arrow::before,
.bs-tooltip-auto[data-popper-placement^='top'] .tooltip-arrow::before {
  border-top-color: #0f172a !important;
}
.kpi-stat-value {
  font-size: 22px; font-weight: 700; line-height: 1;
  letter-spacing: -0.02em;
  color: var(--text-primary);
  font-variant-numeric: tabular-nums;
}
.kpi-stat-value.na {
  color: var(--text-tertiary); font-weight: 500;
  font-size: 14px; letter-spacing: 0;
}

/* Floating glass cards */
.glass {
  background: var(--bg-glass);
  -webkit-backdrop-filter: blur(14px) saturate(180%);
  backdrop-filter: blur(14px) saturate(180%);
  border: 1px solid rgba(255, 255, 255, 0.7);
  box-shadow: var(--shadow-lg);
  border-radius: var(--radius-lg);
}

/* Control panel */
.control-panel {
  position: absolute;
  top: 20px; left: 20px;
  width: 320px;
  z-index: 600;
  display: flex; flex-direction: column;
  max-height: calc(100% - 130px);
}
.panel-head {
  display: flex; align-items: center; justify-content: space-between;
  padding: 14px 16px;
  border-bottom: 1px solid var(--border-color);
}
.panel-title {
  display: flex; align-items: center; gap: 8px;
  font-size: 12px; font-weight: 700;
  text-transform: uppercase; letter-spacing: 0.06em;
  color: var(--text-secondary);
}
.panel-title svg { color: var(--color-primary); font-size: 14px; }
.panel-body { padding: 16px; overflow-y: auto; }
.btn-icon {
  background: transparent; border: none;
  width: 28px; height: 28px;
  display: flex; align-items: center; justify-content: center;
  border-radius: 6px;
  color: var(--text-tertiary);
  cursor: pointer;
  transition: all 0.15s ease;
}
.btn-icon:hover {
  background: var(--color-primary-tint);
  color: var(--color-primary);
}
.control-panel.is-collapsed { width: auto; }
.control-panel.is-collapsed .panel-body,
.control-panel.is-collapsed .panel-title span { display: none; }
.control-panel.is-collapsed .panel-head { padding: 10px; border: 0; }
.control-panel.is-collapsed .btn-icon svg { transform: rotate(180deg); }

.field-group { margin-bottom: 14px; }
.field-label {
  display: block;
  font-size: 11px; font-weight: 700;
  color: var(--text-tertiary);
  text-transform: uppercase; letter-spacing: 0.06em;
  margin-bottom: 6px;
}
.field-group .form-group { margin-bottom: 0; }

/* selectize overrides */
.selectize-control.single .selectize-input {
  background: #fff !important;
  border: 1px solid var(--border-color) !important;
  border-radius: var(--radius-sm) !important;
  padding: 9px 12px !important;
  min-height: 38px !important;
  font-size: 13px;
  box-shadow: var(--shadow-xs);
  transition: border-color 0.15s, box-shadow 0.15s;
}
.selectize-control.single .selectize-input.focus {
  border-color: var(--color-primary) !important;
  box-shadow: 0 0 0 3px rgba(37, 99, 235, 0.10) !important;
}
.selectize-dropdown {
  border-radius: var(--radius-sm) !important;
  border: 1px solid var(--border-color) !important;
  box-shadow: var(--shadow-md) !important;
  margin-top: 4px !important; overflow: hidden;
}
.selectize-dropdown .option { padding: 9px 12px !important; font-size: 13px; }
.selectize-dropdown .active {
  background: var(--color-primary-tint) !important;
  color: var(--color-primary) !important;
}

.btn-modern {
  display: inline-flex; align-items: center; justify-content: center; gap: 8px;
  padding: 9px 14px;
  border: 1px solid var(--border-color);
  background: var(--bg-card-solid);
  color: var(--text-primary);
  border-radius: var(--radius-sm);
  font-size: 13px; font-weight: 600;
  cursor: pointer; transition: all 0.15s;
  box-shadow: var(--shadow-xs);
}
.btn-modern:hover {
  background: #f8fafc;
  border-color: var(--color-primary);
  color: var(--color-primary);
  transform: translateY(-1px);
}

.scope-block {
  margin-top: 18px;
  padding: 14px;
  background: linear-gradient(135deg, var(--color-primary-tint) 0%, #f0f7ff 100%);
  border: 1px solid rgba(37, 99, 235, 0.14);
  border-radius: var(--radius-md);
}
.scope-eyebrow {
  font-size: 10px; font-weight: 700;
  color: var(--color-primary);
  text-transform: uppercase; letter-spacing: 0.07em;
}
.scope-value {
  font-size: 15px; font-weight: 700;
  color: var(--text-primary);
  margin-top: 4px; line-height: 1.25;
}
.scope-meta { font-size: 12px; color: var(--text-secondary); margin-top: 4px; }
.scope-note {
  margin-top: 10px; padding-top: 10px;
  border-top: 1px solid rgba(37, 99, 235, 0.14);
  font-size: 10.5px; color: var(--text-tertiary); line-height: 1.45;
}

/* Detail panel */
.detail-panel {
  position: absolute;
  bottom: 20px; right: 20px;
  width: 360px; max-height: calc(100% - 200px);
  z-index: 600;
  display: flex; flex-direction: column;
}
.detail-body { padding: 18px; overflow-y: auto; }
.detail-eyebrow {
  font-size: 10px; font-weight: 700;
  color: var(--color-primary);
  text-transform: uppercase; letter-spacing: 0.07em;
  margin-bottom: 4px;
}
.detail-title {
  font-size: 17px; font-weight: 700; letter-spacing: -0.01em;
  color: var(--text-primary); line-height: 1.3;
}
.detail-address {
  display: flex; align-items: flex-start; gap: 6px;
  margin-top: 8px; padding-bottom: 14px;
  border-bottom: 1px solid var(--border-color);
  color: var(--text-secondary); font-size: 12.5px;
}
.detail-address svg { flex-shrink: 0; color: var(--text-tertiary); margin-top: 2px; }
.stat-section { margin-top: 14px; }
.stat-section-title {
  font-size: 10px; font-weight: 700;
  color: var(--text-tertiary);
  text-transform: uppercase; letter-spacing: 0.07em;
  margin-bottom: 6px;
}
.stat-row {
  display: flex; justify-content: space-between; align-items: center;
  padding: 7px 0;
  border-bottom: 1px dashed #eef2f6;
  font-size: 13px;
}
.stat-row:last-child { border-bottom: 0; }
.stat-row-label { color: var(--text-secondary); }
.stat-row-value {
  font-weight: 700; color: var(--text-primary);
  font-variant-numeric: tabular-nums;
}
.stat-row-value.na {
  color: var(--text-tertiary);
  font-weight: 500; font-style: italic;
}
.source-link {
  display: inline-flex; align-items: center; gap: 6px;
  margin-top: 16px; padding: 8px 14px;
  background: var(--color-primary-tint);
  color: var(--color-primary);
  border-radius: var(--radius-sm);
  text-decoration: none;
  font-size: 12px; font-weight: 600;
  border: 1px solid rgba(37, 99, 235, 0.18);
  transition: all 0.15s;
}
.source-link:hover {
  background: var(--color-primary-soft); transform: translateY(-1px);
  text-decoration: none;
}
.empty-card {
  text-align: center; padding: 28px 16px;
  color: var(--text-tertiary); font-size: 13px;
}
.empty-card-icon {
  font-size: 26px; display: block; margin-bottom: 8px;
  color: var(--text-tertiary);
}

/* Map footer */
.map-footer {
  position: absolute; bottom: 0; left: 0; right: 0;
  display: flex; align-items: center; justify-content: space-between;
  padding: 6px 16px;
  background: rgba(255,255,255,0.95);
  -webkit-backdrop-filter: blur(8px); backdrop-filter: blur(8px);
  border-top: 1px solid var(--border-color);
  font-size: 11px; color: var(--text-tertiary);
  z-index: 400;
}
.map-footer a { color: var(--color-primary); text-decoration: none; }
.map-footer a:hover { text-decoration: underline; }
.map-footer .footer-left, .map-footer .footer-right {
  display: flex; align-items: center; gap: 8px;
}

/* Leaflet polish */
.leaflet-top.leaflet-left {
  top: auto !important;
  bottom: 36px !important; /* clear of the map-footer */
}
.leaflet-control-zoom {
  border: 0 !important;
  border-radius: var(--radius-sm) !important;
  overflow: hidden;
  box-shadow: var(--shadow-md);
  margin: 0 0 8px 20px !important;
}
.leaflet-control-zoom a {
  background: white !important;
  color: var(--text-primary) !important;
  border-bottom: 1px solid var(--border-color) !important;
  width: 32px !important; height: 32px !important;
  line-height: 32px !important; font-size: 16px !important;
}
.leaflet-control-zoom a:last-child { border-bottom: 0 !important; }
.leaflet-control-zoom a:hover {
  background: var(--color-primary-tint) !important;
  color: var(--color-primary) !important;
}
.leaflet-control-attribution {
  background: rgba(255,255,255,0.85) !important;
  border-radius: var(--radius-sm) 0 0 0 !important;
  padding: 2px 8px !important;
  font-size: 10px !important;
  margin-bottom: 28px !important;
}

/* ===================== COMPARE TAB ===================== */
.compare-shell {
  padding: 24px 28px 32px;
  max-width: 1400px;
  margin: 0 auto;
  min-height: calc(100vh - 60px);
}
.compare-header {
  display: flex; align-items: flex-start; justify-content: space-between;
  margin-bottom: 18px;
}
.compare-title {
  font-size: 22px; font-weight: 700;
  letter-spacing: -0.01em;
  margin: 0;
}
.compare-subtitle {
  font-size: 13px; color: var(--text-secondary);
  margin: 4px 0 0 0;
}

.compare-card {
  background: white;
  border: 1px solid var(--border-color);
  border-radius: var(--radius-lg);
  box-shadow: var(--shadow-sm);
  margin-bottom: 18px;
  /* No overflow:hidden — selectize dropdowns need to escape the card. */
}
.compare-card-head {
  border-top-left-radius: var(--radius-lg);
  border-top-right-radius: var(--radius-lg);
}
.compare-card .compare-card-body:last-child {
  border-bottom-left-radius: var(--radius-lg);
  border-bottom-right-radius: var(--radius-lg);
}
.selectize-dropdown { z-index: 1080 !important; }
.compare-card-head {
  display: flex; align-items: center; justify-content: space-between;
  padding: 14px 18px;
  border-bottom: 1px solid var(--border-color);
}
.compare-card-title {
  display: flex; align-items: center; gap: 8px;
  font-size: 12px; font-weight: 700;
  text-transform: uppercase; letter-spacing: 0.06em;
  color: var(--text-secondary);
}
.compare-card-title svg { color: var(--color-primary); font-size: 14px; }
.compare-card-meta {
  font-size: 11px; color: var(--text-tertiary);
  font-variant-numeric: tabular-nums;
}
.compare-card-body { padding: 18px; }

.compare-controls {
  display: grid;
  grid-template-columns: repeat(4, minmax(0, 1fr));
  gap: 16px;
}
@media (max-width: 900px) {
  .compare-controls { grid-template-columns: repeat(2, minmax(0, 1fr)); }
}
@media (max-width: 540px) {
  .compare-controls { grid-template-columns: 1fr; }
}

/* Quick stat strip on Compare tab */
.compare-stat-strip {
  display: grid;
  grid-template-columns: repeat(4, minmax(0, 1fr));
  gap: 14px;
  margin-bottom: 18px;
}
.compare-stat-card {
  background: white;
  border: 1px solid var(--border-color);
  border-radius: var(--radius-md);
  padding: 14px 18px;
  box-shadow: var(--shadow-xs);
}
.compare-stat-eyebrow {
  font-size: 10px; font-weight: 700;
  color: var(--text-tertiary);
  text-transform: uppercase; letter-spacing: 0.06em;
}
.compare-stat-value {
  font-size: 22px; font-weight: 700; line-height: 1.1;
  margin-top: 4px;
  font-variant-numeric: tabular-nums;
  color: var(--text-primary);
}
.compare-stat-meta {
  font-size: 11.5px; color: var(--text-secondary);
  margin-top: 4px;
}
@media (max-width: 760px) {
  .compare-stat-strip { grid-template-columns: repeat(2, minmax(0, 1fr)); }
}

/* DT polish */
table.dataTable thead th {
  font-size: 11px !important;
  font-weight: 700 !important;
  text-transform: uppercase;
  letter-spacing: 0.05em;
  color: var(--text-secondary) !important;
  border-bottom: 2px solid var(--border-color) !important;
}
table.dataTable tbody td {
  font-size: 13px !important;
  padding: 9px 10px !important;
  color: var(--text-primary);
  border-bottom: 1px solid #f1f5f9 !important;
}
table.dataTable tbody tr:hover { background: var(--color-primary-tint) !important; }
.dataTables_wrapper .dataTables_filter input,
.dataTables_wrapper .dataTables_length select {
  border: 1px solid var(--border-color) !important;
  border-radius: var(--radius-sm) !important;
  padding: 6px 10px !important;
  font-size: 12px !important;
}
.dataTables_wrapper .dataTables_info,
.dataTables_wrapper .dataTables_paginate { font-size: 12px !important; }

/* Responsive (map) */
@media (max-width: 1180px) {
  .kpi-panel { min-width: 0; max-width: calc(100% - 380px); }
  .kpi-stat-value { font-size: 18px; }
  .kpi-stat { padding: 4px 10px; min-width: 80px; }
}
@media (max-width: 880px) {
  .kpi-panel-body { flex-wrap: wrap; }
  .kpi-stat { border-right: 0; border-bottom: 1px solid var(--border-color); }
}
@media (max-width: 760px) {
  .control-panel { width: calc(100vw - 32px); top: 16px; left: 16px; }
  .kpi-panel {
    top: auto; bottom: 56px; left: 16px; right: 16px;
    transform: none; max-width: none; min-width: 0;
  }
  .detail-panel { display: none; }
}
"

# ============================================================================
# UI
# ============================================================================
bslib::page_navbar(
  title = div(class = "navbar-brand-content",
    div(class = "brand-mark", bsicons::bs_icon("geo-alt-fill")),
    div(
      div(class = "brand-title", "Utah Public High Schools"),
      div(class = "brand-subtitle", "U.S. News Best High Schools 2025-2026")
    )
  ),
  id = "main_tab",
  bg = "#ffffff",
  fillable = "tab_map",
  theme = bslib::bs_theme(
    version       = 5,
    bg            = "#f1f5f9",
    fg            = "#0f172a",
    primary       = "#2563eb",
    base_font     = bslib::font_google("Inter"),
    heading_font  = bslib::font_google("Inter"),
    font_scale    = 0.95
  ),

  header = tagList(
    tags$meta(name = "viewport", content = "width=device-width, initial-scale=1"),
    tags$style(HTML(app_css)),
    shinyjs::useShinyjs()
  ),

  # =========== TAB 1: Map dashboard ========================================
  bslib::nav_panel(
    title = tagList(bsicons::bs_icon("geo-alt"), "Map Dashboard"),
    value = "tab_map",

    div(class = "map-shell",
      leafletOutput("map", width = "100%", height = "100%"),

      # KPI panel
      div(class = "kpi-panel", id = "kpi_panel",
        uiOutput("kpi_cards")
      ),

      # Control panel
      div(class = "glass control-panel", id = "control_panel",
        div(class = "panel-head",
          div(class = "panel-title", bsicons::bs_icon("sliders"), span("Filters")),
          actionButton("collapse_filters",
            label = NULL, icon = icon("chevron-left"),
            class = "btn-icon", title = "Collapse filters")
        ),
        div(class = "panel-body",
          div(class = "field-group",
            tags$label("School District", class = "field-label"),
            selectInput("district", NULL,
              choices  = c("All districts", sort(unique(schools$district))),
              selected = "All districts", width = "100%")
          ),
          div(class = "field-group",
            tags$label("School", class = "field-label"),
            selectInput("school", NULL,
              choices  = c("All schools", sort(unique(schools$school_name))),
              selected = "All schools", width = "100%")
          ),
          actionButton("reset_view",
            label = tagList(bsicons::bs_icon("arrow-counterclockwise"), "Reset view"),
            class = "btn-modern", style = "width:100%"),
          uiOutput("scope_block")
        )
      ),

      # Detail panel
      shinyjs::hidden(
        div(class = "glass detail-panel", id = "detail_panel",
          div(class = "panel-head",
            div(class = "panel-title", bsicons::bs_icon("info-circle"), span("Details")),
            actionButton("close_detail",
              label = NULL, icon = icon("xmark"),
              class = "btn-icon", title = "Close details")
          ),
          div(class = "detail-body",
            uiOutput("school_stats")
          )
        )
      ),

      # Map footer
      div(class = "map-footer",
        div(class = "footer-left",
          bsicons::bs_icon("database"),
          span("Sources:"),
          tags$a(href = "https://www.usnews.com/education/best-high-schools/utah/rankings",
                 target = "_blank", "U.S. News"),
          span("·"), span("Geocodio"), span("·"), span("Census TIGER 2023")
        ),
        div(class = "footer-right",
          bsicons::bs_icon("info-circle"),
          span("Hover markers for scorecards · Click polygons to filter by district")
        )
      )
    )
  ),

  # =========== TAB 2: Compare schools ======================================
  bslib::nav_panel(
    title = tagList(bsicons::bs_icon("bar-chart-line-fill"), "Compare Schools"),
    value = "tab_compare",

    div(class = "compare-shell",
      div(class = "compare-header",
        div(
          h1("Compare schools across Utah", class = "compare-title"),
          p("Rank any metric across the 219 schools, filter by district, and explore the distribution.",
            class = "compare-subtitle")
        )
      ),

      # Controls card
      div(class = "compare-card",
        div(class = "compare-card-head",
          div(class = "compare-card-title",
            bsicons::bs_icon("sliders"), span("Comparison settings")),
          div(class = "compare-card-meta", uiOutput("cmp_meta_inline"))
        ),
        div(class = "compare-card-body",
          div(class = "compare-controls",
            div(
              tags$label("Metric", class = "field-label"),
              selectInput("cmp_metric", NULL,
                choices = compare_metric_choices,
                selected = "math_proficiency", width = "100%")
            ),
            div(
              tags$label("District filter", class = "field-label"),
              selectInput("cmp_district", NULL,
                choices = c("All districts", sort(unique(schools$district))),
                selected = "All districts", width = "100%")
            ),
            div(
              tags$label("Sort order", class = "field-label"),
              selectInput("cmp_sort", NULL,
                # "Best" is direction-aware in the server: for score metrics
                # best = highest value; for rank metrics best = lowest number.
                choices = c("Best first"  = "best",
                            "Worst first" = "worst"),
                selected = "best", width = "100%")
            ),
            div(
              tags$label("Show", class = "field-label"),
              selectInput("cmp_n", NULL,
                choices = c("Top 15" = "15", "Top 25" = "25",
                            "Top 50" = "50", "Top 100" = "100",
                            "All schools" = "999"),
                selected = "25", width = "100%")
            )
          )
        )
      ),

      # Summary stat strip
      uiOutput("cmp_stat_strip"),

      # Chart card — only meaningful for score-style metrics. Hidden when the
      # user picks a rank metric, where bar/dot length doesn't carry meaning.
      conditionalPanel(
        condition = "input.cmp_metric !== 'state_rank' &&
                     input.cmp_metric !== 'national_rank'",
        div(class = "compare-card",
          div(class = "compare-card-head",
            div(class = "compare-card-title",
              bsicons::bs_icon("bar-chart-fill"), span("Ranked visualization")),
            div(class = "compare-card-meta", uiOutput("cmp_chart_meta"))
          ),
          div(class = "compare-card-body",
            plotlyOutput("compare_chart", height = "560px")
          )
        )
      ),

      # Table card
      div(class = "compare-card",
        div(class = "compare-card-head",
          div(class = "compare-card-title",
            bsicons::bs_icon("table"), span("Data table")),
          div(class = "compare-card-meta", "Sortable · searchable · exportable order")
        ),
        div(class = "compare-card-body",
          DT::DTOutput("compare_table")
        )
      )
    )
  ),

  # =========== Right-side navbar items ====================================
  bslib::nav_spacer(),
  bslib::nav_item(
    div(class = "navbar-stat-pill",
      bsicons::bs_icon("buildings"),
      span(sprintf("%d schools", nrow(schools))),
      tags$span("·", style = "opacity:.6"),
      span(sprintf("%d districts", n_traditional)),
      tags$span("·", style = "opacity:.6"),
      span(sprintf("%d charters", n_charters))
    )
  )
)
