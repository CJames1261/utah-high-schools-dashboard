# ui.R — multi-tab dashboard: Map view + Compare schools

# ============================================================================
# CSS — single inline stylesheet
# ============================================================================
app_css <- "
:root {
  --bg-app: #f1f5f9;
  --bg-glass: rgba(255, 255, 255, 0.94);
  --bg-card-solid: #ffffff;
  --bg-subtle: #f8fafc;
  --border-color: #e2e8f0;
  --border-color-strong: #cbd5e1;
  --text-primary: #0f172a;
  --text-secondary: #475569;
  /* Darkened from #64748b (~2.5:1, failed WCAG AA) to #64748b (~4.8:1 on
     white) so all muted labels/meta clear AA. */
  --text-tertiary: #64748b;
  --color-primary: #2563eb;
  --color-primary-700: #1d4ed8;
  --color-primary-soft: #dbeafe;
  --color-primary-tint: #eff6ff;
  --focus-ring: #2563eb;
  --shadow-xs: 0 1px 2px rgba(15, 23, 42, 0.04);
  --shadow-sm: 0 2px 6px rgba(15, 23, 42, 0.06);
  --shadow-md: 0 6px 18px rgba(15, 23, 42, 0.10);
  --shadow-lg: 0 12px 32px rgba(15, 23, 42, 0.14);
  --shadow-xl: 0 24px 48px rgba(15, 23, 42, 0.18);
  --radius-sm: 8px;
  --radius-md: 12px;
  --radius-lg: 16px;
  --radius-xl: 20px;
  --radius-pill: 999px;
  /* Spacing scale (4px base) — no spacing tokens existed before. */
  --space-1: 4px;
  --space-2: 8px;
  --space-3: 12px;
  --space-4: 16px;
  --space-5: 22px;
  --space-6: 32px;
  /* Type scale — collapses ~19 ad-hoc sizes; every label floors at 11px. */
  --fs-overline: 11px;
  --fs-caption: 12px;
  --fs-sm: 13px;
  --fs-base: 14px;
  --fs-md: 16px;
  --fs-lg: 18px;
  --fs-xl: 22px;
  --fs-2xl: 26px;
}
* { box-sizing: border-box; }
html, body {
  margin: 0; padding: 0;
  font-family: 'Inter', -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
  font-size: 15px;
  color: var(--text-primary);
  background: var(--bg-app);
  -webkit-font-smoothing: antialiased;
}

/* ============================================================
   KEYBOARD FOCUS (WCAG 2.4.7) — one shared focus-visible ring
   for every interactive control. Previously only the legend
   search input had any :focus styling, so keyboard/switch users
   could not see what was focused anywhere else in the app.
   ============================================================ */
a:focus-visible,
button:focus-visible,
[tabindex]:focus-visible,
.nav-link:focus-visible,
.btn-navbar-icon:focus-visible,
.btn-icon:focus-visible,
.btn-modern:focus-visible,
.btn-close-modal:focus-visible,
.btn-primary-modal:focus-visible,
.onb-arrow:focus-visible,
.onb-dot:focus-visible,
.legend-item:focus-visible,
.source-link:focus-visible,
.compare-info-link:focus-visible {
  outline: 2px solid var(--focus-ring);
  outline-offset: 2px;
}

/* ============================================================
   REDUCED MOTION — honor prefers-reduced-motion. Only the timing
   is neutralized (not transform), so the carousel's translateX
   positioning still works; slide changes just become instant.
   ============================================================ */
@media (prefers-reduced-motion: reduce) {
  *, *::before, *::after {
    transition-duration: 0.01ms !important;
    animation-duration: 0.01ms !important;
    animation-iteration-count: 1 !important;
    scroll-behavior: auto !important;
  }
}

/* ============================================================
   NAVBAR — modern SaaS-style header
   Visual model: fixed 64px height, white surface, single hairline
   bottom border, near-imperceptible drop shadow for layering.
   Brand block / Tabs / Right utilities all baseline-aligned and
   vertically centered. Active tab uses an animated 2px indicator
   driven by a pseudo-element (scaleX) for a premium feel.
   ============================================================ */

.navbar {
  background: #ffffff !important;
  border: 0 !important;
  border-bottom: 1px solid var(--border-color) !important;
  box-shadow: 0 1px 0 rgba(15, 23, 42, 0.02);
  padding: 0 !important;
  min-height: 64px;
  height: 64px;
  z-index: 1100;
  position: sticky;
  top: 0;
}

/* Inner container — single source of horizontal padding. */
.navbar > .container-fluid,
.navbar > .container,
.navbar > .container-xl,
.navbar > .container-lg {
  padding: 0 28px !important;
  height: 100%;
  display: flex;
  align-items: stretch;
  flex-wrap: nowrap;
  gap: 0;
  max-width: none;
}

/* -------- Brand block (logo + title + subtitle) -------- */
.navbar .navbar-brand {
  padding: 0;
  margin: 0 28px 0 0;
  display: flex;
  align-items: center;
  position: relative;
  flex-shrink: 0;
}
/* Vertical hairline separator between brand and nav */
.navbar .navbar-brand::after {
  content: '';
  position: absolute;
  top: 50%; right: -14px;
  height: 32px; width: 1px;
  background: var(--border-color);
  transform: translateY(-50%);
}

.navbar-brand-content {
  display: flex;
  align-items: center;
  gap: 12px;
}
/* Text block (title + subtitle) is the unnamed sibling of .brand-mark */
.navbar-brand-content > div:not(.brand-mark) {
  display: flex;
  flex-direction: column;
  justify-content: center;
  line-height: 1.2;
}

.brand-mark {
  width: 36px; height: 36px;
  display: flex;
  align-items: center;
  justify-content: center;
  background: linear-gradient(135deg, #2563eb 0%, #6366f1 100%);
  color: white;
  border-radius: 10px;
  box-shadow:
    0 4px 12px rgba(37, 99, 235, 0.25),
    inset 0 1px 0 rgba(255, 255, 255, 0.20);
  font-size: 18px;
  line-height: 1;
  flex-shrink: 0;
  align-self: center;
  /* Small downward nudge to optically center the mark — its drop shadow
     extends below, which pulls the perceived visual weight downward. */
  margin-top: 2px;
}
/* Ensure the inner SVG is block-level so there's no inline-baseline space
   pushing the icon up from the geometric centre. */
.brand-mark svg {
  display: block;
}

/* Make the whole brand area span the full navbar height so vertical
   centering inside it is reliable across themes. */
.navbar .navbar-brand,
.navbar-brand-content {
  height: 100%;
}
.navbar-brand-content { align-items: center; }

.brand-title {
  font-size: 15px;
  font-weight: 700;
  letter-spacing: -0.015em;
  color: #0f172a;
  line-height: 1.15;
}
.brand-subtitle {
  font-size: 12px;
  font-weight: 500;
  color: #64748b;
  letter-spacing: 0.01em;
  margin-top: 2px;
  line-height: 1.2;
}

/* -------- Tab navigation — segmented control --------
   Every tab is its own white pill on a light track; the selected tab is a
   solid blue pill so the active view is obvious at a glance. */
.navbar-nav {
  display: flex;
  align-items: center;
  gap: 5px;
  align-self: center;
  margin-left: 18px;
  padding: 5px;
  background: var(--bg-app);
  border: 1px solid var(--border-color);
  border-radius: 12px;
}
.navbar .nav-item { display: flex; align-items: center; }

.navbar .nav-link {
  display: inline-flex !important;
  align-items: center;
  gap: 8px;
  padding: 7px 15px !important;
  font-size: 14px !important;
  font-weight: 600 !important;
  letter-spacing: -0.005em;
  color: var(--text-secondary) !important;
  /* Inherent white pill on every tab. */
  background: #ffffff !important;
  border: 0 !important;
  border-radius: 8px !important;
  box-shadow: var(--shadow-xs);
  position: relative;
  transition: background 0.15s ease, color 0.15s ease, box-shadow 0.15s ease;
}

/* Icons sit one shade muted, brighten on hover/active for hierarchy. */
.navbar .nav-link svg {
  font-size: 15px;
  flex-shrink: 0;
  color: var(--text-tertiary);
  transition: color 0.15s ease;
}

/* The pill background replaces the old underline indicator. */
.navbar .nav-link::after { display: none !important; }

/* Hover (inactive) — soft blue tint hint */
.navbar .nav-link:hover {
  color: var(--color-primary) !important;
  background: var(--color-primary-tint) !important;
  box-shadow: var(--shadow-sm);
}
.navbar .nav-link:hover svg { color: var(--color-primary); }

/* Selected — solid blue pill, white text + icon */
.navbar .nav-link.active {
  color: #ffffff !important;
  background: var(--color-primary) !important;
  box-shadow: 0 2px 8px rgba(37, 99, 235, 0.35);
}
.navbar .nav-link.active svg { color: #ffffff; }
.navbar .nav-link.active:hover {
  color: #ffffff !important;
  background: var(--color-primary-700) !important;
}
.navbar .nav-link.active:hover svg { color: #ffffff; }

/* -------- Right-side stat cluster --------
   A white card with a brand-accent icon and number/label stats separated by
   hairline dividers — a compact, professional at-a-glance summary. */
.navbar-stats {
  display: inline-flex;
  align-items: center;
  gap: 14px;
  padding: 6px 16px;
  background: #ffffff;
  border: 1px solid var(--border-color);
  border-radius: 12px;
  box-shadow: var(--shadow-xs);
  align-self: center;
}
.navbar-stats > svg {
  font-size: 18px;
  color: var(--color-primary);
  flex-shrink: 0;
  margin-right: 2px;
}
.navbar-stat {
  display: flex;
  flex-direction: column;
  line-height: 1.05;
}
.navbar-stat-num {
  font-size: 17px;
  font-weight: 700;
  color: var(--text-primary);
  letter-spacing: -0.01em;
  font-variant-numeric: tabular-nums;
}
.navbar-stat-label {
  font-size: 11px;
  font-weight: 700;
  text-transform: uppercase;
  letter-spacing: 0.06em;
  color: var(--text-tertiary);
  margin-top: 1px;
}
.navbar-stat-sep {
  width: 1px;
  height: 26px;
  background: var(--border-color);
  flex-shrink: 0;
}

/* ===================== HELP BUTTON IN NAVBAR ===================== */
.btn-navbar-icon {
  background: transparent;
  border: 0;
  width: 36px;
  height: 36px;
  border-radius: 9px;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  color: #475569;
  cursor: pointer;
  align-self: center;
  transition: background 0.15s ease, color 0.15s ease;
  margin-right: 6px;
}
.btn-navbar-icon svg { font-size: 19px; }
.btn-navbar-icon:hover {
  background: rgba(37, 99, 235, 0.08);
  color: #2563eb;
}

/* ===================== ONBOARDING MODAL ===================== */
.onboarding-overlay {
  position: fixed;
  inset: 0;
  z-index: 2000;
  background: rgba(15, 23, 42, 0.55);
  -webkit-backdrop-filter: blur(6px);
  backdrop-filter: blur(6px);
  display: flex;
  align-items: center;
  justify-content: center;
  padding: 24px;
  opacity: 0;
  visibility: hidden;
  transition: opacity 0.25s ease, visibility 0.25s ease;
}
.onboarding-overlay.is-visible {
  opacity: 1;
  visibility: visible;
}

.onboarding-modal {
  background: white;
  width: 100%;
  max-width: 960px;
  max-height: 92vh;
  border-radius: 20px;
  display: flex;
  flex-direction: column;
  overflow: hidden;
  box-shadow:
    0 24px 60px rgba(15, 23, 42, 0.30),
    0 0 0 1px rgba(15, 23, 42, 0.04);
  transform: translateY(16px) scale(0.97);
  opacity: 0;
  transition: transform 0.30s cubic-bezier(0.4, 0, 0.2, 1), opacity 0.25s ease;
}
.onboarding-overlay.is-visible .onboarding-modal {
  transform: translateY(0) scale(1);
  opacity: 1;
}

/* ----- Modal header ----- */
.onboarding-header {
  padding: 26px 30px 22px;
  border-bottom: 1px solid #f1f5f9;
  display: flex;
  align-items: flex-start;
  gap: 16px;
  background:
    radial-gradient(ellipse at top right, rgba(37, 99, 235, 0.06), transparent 50%),
    #ffffff;
}
.onb-header-mark {
  width: 48px; height: 48px;
  border-radius: 12px;
  background: linear-gradient(135deg, #2563eb 0%, #6366f1 100%);
  display: flex; align-items: center; justify-content: center;
  color: white;
  font-size: 23px;
  box-shadow: 0 6px 16px rgba(37, 99, 235, 0.32);
  flex-shrink: 0;
}
.onb-header-mark svg { display: block; }
.onb-header-text { flex: 1; min-width: 0; }
.onb-header-eyebrow {
  display: inline-block;
  font-size: 12px;
  font-weight: 700;
  text-transform: uppercase;
  letter-spacing: 0.08em;
  color: #2563eb;
  background: rgba(37, 99, 235, 0.08);
  padding: 3px 9px;
  border-radius: 999px;
  margin-bottom: 8px;
}
.onb-header-title {
  font-size: 24px;
  font-weight: 700;
  letter-spacing: -0.018em;
  margin: 0 0 6px;
  color: #0f172a;
  line-height: 1.2;
}
.onb-header-sub {
  font-size: 15.5px;
  color: #64748b;
  margin: 0;
  line-height: 1.5;
}
.btn-close-modal {
  background: transparent !important;
  border: 0 !important;
  width: 32px !important;
  height: 32px !important;
  padding: 0 !important;
  display: inline-flex !important;
  align-items: center;
  justify-content: center;
  color: #64748b !important;
  border-radius: 8px !important;
  cursor: pointer;
  transition: all 0.15s ease;
  flex-shrink: 0;
}
.btn-close-modal:hover {
  background: #f1f5f9 !important;
  color: #0f172a !important;
}

/* ----- Modal body ----- */
.onboarding-body {
  padding: 22px 30px 22px;
  overflow-y: auto;
  flex: 1;
}
.onb-grid {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 14px;
  margin-bottom: 18px;
}
@media (max-width: 640px) {
  .onb-grid { grid-template-columns: 1fr; }
}
.onb-section {
  padding: 16px;
  background: #f8fafc;
  border: 1px solid #eef2f6;
  border-radius: 12px;
  transition: border-color 0.15s ease, background 0.15s ease;
}
.onb-section:hover {
  border-color: rgba(37, 99, 235, 0.20);
  background: #f0f7ff;
}
.onb-section-icon {
  width: 32px; height: 32px;
  display: flex; align-items: center; justify-content: center;
  background: #eff6ff;
  color: #2563eb;
  border-radius: 9px;
  font-size: 17px;
  margin-bottom: 10px;
}
.onb-section-title {
  font-size: 16px;
  font-weight: 700;
  margin: 0 0 5px;
  color: #0f172a;
  letter-spacing: -0.01em;
}
.onb-section-body {
  font-size: 14.5px;
  color: #475569;
  margin: 0;
  line-height: 1.55;
}

/* Methodology disclosure (collapsible details block) */
.onb-method {
  border: 1px solid #eef2f6;
  border-radius: 12px;
  background: #ffffff;
  overflow: hidden;
}
.onb-method-summary {
  list-style: none;
  padding: 13px 16px;
  cursor: pointer;
  display: flex;
  align-items: center;
  gap: 10px;
  font-size: 14px;
  font-weight: 700;
  text-transform: uppercase;
  letter-spacing: 0.06em;
  color: #475569;
  transition: background 0.15s ease;
}
.onb-method-summary::-webkit-details-marker { display: none; }
.onb-method-summary:hover { background: #f8fafc; }
.onb-method-summary svg.method-lead-icon { color: #2563eb; font-size: 15px; }
.onb-method-summary svg.method-chev {
  margin-left: auto;
  color: #64748b;
  font-size: 13px;
  transition: transform 0.18s ease;
}
.onb-method[open] .onb-method-summary svg.method-chev { transform: rotate(90deg); }
.onb-method-content {
  padding: 4px 18px 16px;
  font-size: 14.5px;
  color: #475569;
  line-height: 1.6;
  border-top: 1px solid #f1f5f9;
}
.onb-method-content p { margin: 10px 0 8px; }
.onb-method-content ul {
  padding-left: 18px;
  margin: 0 0 8px;
}
.onb-method-content li { margin-bottom: 4px; }
.onb-method-content strong { color: #0f172a; }

/* ----- Modal footer ----- */
.onboarding-footer {
  padding: 16px 30px 22px;
  background: #f8fafc;
  border-top: 1px solid #f1f5f9;
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 16px;
  flex-wrap: wrap;
}
.onb-checkbox {
  display: inline-flex;
  align-items: center;
  gap: 8px;
  font-size: 13.5px;
  color: #475569;
  cursor: pointer;
  user-select: none;
}
.onb-checkbox input {
  width: 16px; height: 16px;
  accent-color: #2563eb;
  cursor: pointer;
  margin: 0;
}
.btn-primary-modal {
  display: inline-flex !important;
  align-items: center;
  gap: 8px;
  padding: 11px 20px !important;
  background: linear-gradient(135deg, #2563eb 0%, #1d4ed8 100%) !important;
  color: white !important;
  border: 0 !important;
  border-radius: 10px !important;
  font-size: 14px !important;
  font-weight: 600 !important;
  cursor: pointer;
  transition: transform 0.15s ease, box-shadow 0.15s ease;
  box-shadow: 0 4px 12px rgba(37, 99, 235, 0.32);
}
.btn-primary-modal:hover {
  transform: translateY(-1px);
  box-shadow: 0 8px 18px rgba(37, 99, 235, 0.42);
  color: white !important;
}
.btn-primary-modal svg { font-size: 15px; }

/* ===================== ONBOARDING CAROUSEL ===================== */
/* The modal is a 3-slide carousel: quote image, mission, then the guide.
   A fixed modal height keeps the frame steady as slides change; each slide
   scrolls internally and the track slides horizontally via translateX. */
.onboarding-modal.onb-carousel {
  position: relative;
  height: min(92vh, 840px);
  padding: 0;
}
.onb-close-float {
  position: absolute;
  top: 14px; right: 14px;
  z-index: 10;
}
.onb-carousel-viewport {
  position: relative;
  flex: 1 1 auto;
  min-height: 0;
  overflow: hidden;
}
.onb-carousel-track {
  display: flex;
  height: 100%;
  width: 100%;
  transition: transform 0.38s cubic-bezier(0.4, 0, 0.2, 1);
}
.onb-slide {
  flex: 0 0 100%;
  width: 100%;
  height: 100%;
  overflow-y: auto;
}
.onb-slide-body { padding: 22px 30px; }

/* Slide 1 — quote image */
.onb-slide-quote {
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  text-align: center;
  padding: 32px;
  background:
    radial-gradient(ellipse at center, rgba(37, 99, 235, 0.05), transparent 70%),
    #ffffff;
}
.onb-quote-img {
  width: 100%;
  max-width: 740px;
  height: auto;
  max-height: 70vh;
  object-fit: contain;
  border-radius: 14px;
  box-shadow: var(--shadow-lg);
}
.onb-quote-caption {
  margin: 22px 0 0;
  font-size: 14px;
  color: var(--text-tertiary);
  letter-spacing: 0.01em;
}

/* Slide 2 — mission */
.onb-mission-lead {
  font-size: 16px;
  color: var(--text-secondary);
  line-height: 1.6;
  margin: 6px 0 18px;
}
.onb-mission-close {
  display: flex;
  gap: 11px;
  align-items: flex-start;
  margin-top: 18px;
  padding: 14px 16px;
  background: linear-gradient(135deg, #eff6ff 0%, #f5f3ff 100%);
  border: 1px solid rgba(37, 99, 235, 0.14);
  border-radius: 12px;
  font-size: 15px;
  color: var(--text-secondary);
  line-height: 1.6;
}
.onb-mission-close > svg:first-child {
  color: var(--color-primary);
  font-size: 17px;
  flex-shrink: 0;
  margin-top: 2px;
}
.onb-mission-close strong { color: var(--text-primary); font-weight: 700; }

/* Nav bar (arrows + dots + start) */
.onb-carousel-nav {
  flex-shrink: 0;
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 14px;
  padding: 14px 22px;
  background: #f8fafc;
  border-top: 1px solid #f1f5f9;
}
.onb-arrow {
  width: 40px; height: 40px;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  border-radius: 10px;
  border: 1px solid var(--border-color);
  background: #ffffff;
  color: var(--text-secondary);
  cursor: pointer;
  box-shadow: var(--shadow-xs);
  transition: background 0.15s ease, color 0.15s ease, border-color 0.15s ease, transform 0.15s ease;
}
.onb-arrow svg { font-size: 17px; }
.onb-arrow:hover:not(:disabled) {
  background: var(--color-primary-tint);
  border-color: var(--color-primary);
  color: var(--color-primary);
  transform: translateY(-1px);
}
.onb-arrow:disabled { opacity: 0.4; cursor: not-allowed; }
.onb-nav-right { display: inline-flex; align-items: center; gap: 10px; }

/* Start button + next arrow visibility are driven by is-last on the modal,
   because .btn-primary-modal sets display:inline-flex !important. */
.onb-start { display: none !important; }
.onb-carousel.is-last .onb-start { display: inline-flex !important; }
.onb-carousel.is-last .onb-next { display: none; }

/* Dots */
.onb-dots { display: inline-flex; align-items: center; gap: 8px; }
.onb-dot {
  width: 8px; height: 8px;
  padding: 0;
  border: 0;
  border-radius: 999px;
  background: #cbd5e1;
  cursor: pointer;
  transition: background 0.15s ease, width 0.2s ease;
}
.onb-dot:hover { background: #64748b; }
.onb-dot.is-active { background: var(--color-primary); width: 22px; }

/* -------- Responsive collapse -------- */
@media (max-width: 1024px) {
  .navbar > .container-fluid { padding: 0 20px !important; }
}
@media (max-width: 900px) {
  .brand-subtitle { display: none; }
  .brand-title { font-size: 14.5px; }
  .navbar .navbar-brand { margin-right: 16px; }
  .navbar .navbar-brand::after { right: -8px; height: 28px; }
  .navbar-nav { margin-left: 8px; }
  .navbar .nav-link { padding: 7px 11px !important; }
}
@media (max-width: 640px) {
  .navbar > .container-fluid { padding: 0 14px !important; }
  .navbar-stats { gap: 10px; padding: 6px 12px; }
  /* Collapse to just the schools count on the smallest screens. */
  .navbar-stat-extra { display: none; }
}

/* ===================== MAP TAB ===================== */
.map-shell {
  position: relative;
  height: 100%;
  width: 100%;
  background: var(--bg-app);
}
#map { position: absolute !important; inset: 0 !important; }
.leaflet-container { background: #eef3f9 !important; }

/* State count bubble (default overview): one pill per state showing its total
   number of high schools. Rendered as a label-only marker; the dark pill stays
   legible over any state fill color, and pointer-events:none lets hover/click
   pass through to the state polygon underneath (KPI hover + drill-in). */
.leaflet-tooltip.state-count-tip {
  background: transparent !important;
  border: 0 !important;
  box-shadow: none !important;
  padding: 0 !important;
}
.leaflet-tooltip.state-count-tip::before { display: none !important; }
.state-count-badge {
  display: inline-flex; align-items: baseline; gap: 4px;
  background: rgba(15, 23, 42, 0.88);
  color: #ffffff;
  font-family: 'Inter', sans-serif;
  font-weight: 700; font-size: 13px;
  padding: 5px 11px; border-radius: 999px;
  border: 1.5px solid #ffffff;
  box-shadow: 0 2px 8px rgba(15, 23, 42, 0.35);
  white-space: nowrap;
  font-variant-numeric: tabular-nums;
  /* Re-enable pointer events (the parent tooltip sets none) so the bubble is a
     real click target that drills into its state. */
  pointer-events: auto;
  cursor: pointer;
  transition: background 0.15s ease, transform 0.15s ease, box-shadow 0.15s ease;
}
.state-count-badge:hover {
  background: var(--color-primary, #2563eb);
  transform: translateY(-1px);
  box-shadow: 0 4px 12px rgba(37, 99, 235, 0.45);
}
.state-count-badge .scb-label {
  font-weight: 600; font-size: 11px; opacity: 0.82;
  text-transform: uppercase; letter-spacing: 0.04em;
}

/* Marker-cluster bubbles: neutral slate (NOT count-coloured) so colour on the
   map only ever encodes proficiency. They just say 'N schools here, zoom in'. */
.prof-cluster-wrap { background: transparent; }
.prof-cluster {
  display: flex; align-items: center; justify-content: center;
  width: 40px; height: 40px; border-radius: 50%;
  background: rgba(71, 85, 105, 0.88);
  color: #ffffff; font-family: 'Inter', sans-serif;
  font-weight: 700; font-size: 13px;
  border: 2px solid #ffffff;
  box-shadow: 0 2px 6px rgba(15, 23, 42, 0.35);
  font-variant-numeric: tabular-nums;
}

/* KPI row (top center): the single metrics panel, whose right-most cell is the
   proficiency colour-scale legend. Centered between the filters and rankings
   panels; max-width keeps it from overlapping either. The metric cards shrink
   (see .kpi-stat) so the legend always fits inside the centered panel. */
.kpi-row {
  position: absolute;
  top: 20px;
  left: 50%;
  transform: translateX(-50%);
  max-width: calc(100% - 900px);
  z-index: 500;
  display: flex;
  align-items: stretch;
  pointer-events: none;
}
.kpi-row > * { pointer-events: auto; }
.kpi-panel {
  position: relative;
  flex: 1 1 auto;
  min-width: 0;
  max-width: 100%;
  background: var(--bg-glass);
  -webkit-backdrop-filter: blur(14px) saturate(180%);
  backdrop-filter: blur(14px) saturate(180%);
  border: 1px solid rgba(255, 255, 255, 0.7);
  border-radius: var(--radius-lg);
  box-shadow: var(--shadow-lg);
  overflow: hidden;
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
  font-size: 13.5px; font-weight: 700;
  color: var(--text-primary);
}
.kpi-panel-title svg { color: var(--color-primary); font-size: 15px; }
.kpi-panel-meta {
  display: inline-flex;
  align-items: center;
  gap: 8px;
  font-size: 12px; color: var(--text-tertiary);
  font-variant-numeric: tabular-nums;
}

/* Data-vintage pill — shows the school year of the data in the KPI panel head
   and the district hover card so users always know what year they're seeing. */
.data-year-pill {
  display: inline-flex;
  align-items: center;
  gap: 4px;
  font-size: 12px;
  font-weight: 700;
  letter-spacing: 0.02em;
  line-height: 1.4;
  color: var(--color-primary);
  background: var(--color-primary-soft);
  padding: 2px 8px;
  border-radius: 999px;
  font-variant-numeric: tabular-nums;
  white-space: nowrap;
}
.data-year-pill svg { font-size: 11px; flex-shrink: 0; }
.kpi-panel-body {
  display: flex; align-items: stretch;
  padding: 12px 4px;
}
.kpi-stat {
  /* Cards share the panel width equally (flex: 1 1 0) and may shrink below
     their content (min-width: 0) so the legend cell always fits inside the
     centered bar; overflow:hidden keeps a long label from spilling. */
  flex: 1 1 0;
  min-width: 0;
  padding: 4px 9px;
  border-right: 1px solid var(--border-color);
  overflow: hidden;
}
.kpi-stat:last-child { border-right: 0; }
.kpi-stat-head {
  display: flex; align-items: center; gap: 4px;
  flex-wrap: nowrap;            /* never break to a second row */
  color: var(--text-tertiary);
  font-size: 11px; font-weight: 700;
  text-transform: uppercase; letter-spacing: 0.02em;
  margin-bottom: 6px;
}
/* Keep the label on one line; the card's overflow:hidden clips it at the edge. */
.kpi-stat-head > span { white-space: nowrap; }
.kpi-stat-head > svg { color: var(--color-primary); font-size: 11px; flex-shrink: 0; }

/* Info icon — same brand blue as the metric icons, sits at the right edge of
   the stat header (margin-left:auto), and triggers a Bootstrap tooltip.
   Slight opacity keeps it secondary to the metric icon and value, so the
   visual hierarchy (icon -> label -> value) still reads clearly. */
.kpi-info {
  margin-left: auto;
  display: inline-flex;
  align-items: center;
  cursor: help;
  color: var(--color-primary);
  font-size: 12px;
  opacity: 0.55;
  transition: opacity 0.15s ease, transform 0.15s ease;
}
.kpi-info:hover {
  opacity: 1;
  transform: scale(1.08);
}
.kpi-info svg { font-size: 12.5px; }

/* Proficiency colour-scale legend — the right-most cell INSIDE the KPI bar (not
   a separate card). The preceding Graduation cell's border-right separates it.
   flex:0 0 auto so it keeps its width while the metrics flex. */
.kpi-legend {
  flex: 0 0 auto;
  display: flex; flex-direction: column; justify-content: center;
  gap: 4px;
  padding: 4px 13px;
  min-width: 104px;
}
.kpi-legend-head {
  display: flex; align-items: center; gap: 4px;
  color: var(--text-tertiary);
  font-size: 11px; font-weight: 700;
  text-transform: uppercase; letter-spacing: 0.04em;
  white-space: nowrap;
}
.kpi-legend-head svg { color: var(--color-primary); font-size: 11px; }
.kpi-legend-bar {
  height: 10px; border-radius: 3px;
  border: 1px solid rgba(15, 23, 42, 0.12);
}
.kpi-legend-scale {
  display: flex; justify-content: space-between;
  font-size: 10px; font-weight: 600; color: var(--text-tertiary);
  text-transform: uppercase; letter-spacing: 0.03em;
}
.kpi-legend-foot {
  display: flex; align-items: center; gap: 5px;
  font-size: 10px; font-weight: 600; color: var(--text-tertiary);
}
.kpi-legend-na {
  width: 11px; height: 11px; border-radius: 2px; display: inline-block;
  background: #cbd5e1; border: 1px solid rgba(15, 23, 42, 0.12);
}

/* Index column in the rankings table: a proportional bar coloured per-row by
   the same proficiency ramp as the map (the gradient is set inline per row).
   background-image is set inline so these size/repeat/position rules still take
   effect. */
.state-rank-dt td .idx-bar {
  background-repeat: no-repeat;
  background-size: 100% 64%;
  background-position: center;
  border-radius: 3px;
  padding: 2px 0;
  font-weight: 700; color: #0f172a;
  /* White halo keeps the value readable even over the darkest red/green bars. */
  text-shadow: 0 0 4px rgba(255, 255, 255, 0.95), 0 0 2px rgba(255, 255, 255, 0.95);
  text-align: center;
  font-variant-numeric: tabular-nums;
}
/* Muted 'NA' shown in the rankings table where a state/district has no score. */
.state-rank-dt .cell-na {
  color: #94a3b8;
  font-style: italic;
  font-weight: 600;
}

/* Tone down the default Bootstrap tooltip to match the app's look. */
.tooltip-inner {
  background: #0f172a !important;
  color: #f8fafc !important;
  font-family: 'Inter', sans-serif !important;
  font-size: 13px !important;
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

/* ===================== DISTRICT HOVER KPI CARD ===================== */
/* Scorecard tooltip shown when hovering a district polygon. Mirrors the look
   of the top KPI panel: a titled card over a 3x2 grid of average scores. The
   .district-hover-tooltip class strips Leaflet's default tooltip chrome so the
   card's own styling (border, radius, shadow) shows cleanly. */
.leaflet-tooltip.district-hover-tooltip {
  background: transparent !important;
  border: 0 !important;
  box-shadow: none !important;
  padding: 0 !important;
  border-radius: 0 !important;
  white-space: normal !important;
}
.leaflet-tooltip.district-hover-tooltip::before { display: none !important; }

.district-hover-card {
  font-family: 'Inter', -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
  width: 348px;
  /* Never exceed the viewport on small screens (tooltip can render anywhere). */
  max-width: min(348px, 92vw);
  background: #ffffff;
  border: 1px solid #e2e8f0;
  border-radius: 14px;
  box-shadow: 0 12px 32px rgba(15, 23, 42, 0.18);
  overflow: hidden;
}
.district-hover-head {
  display: flex; align-items: center; justify-content: space-between;
  gap: 10px;
  padding: 11px 14px;
  background: linear-gradient(180deg, #f8fafc 0%, #ffffff 100%);
  border-bottom: 1px solid #e2e8f0;
}
.district-hover-title {
  display: flex; align-items: center; gap: 7px;
  font-size: 14px; font-weight: 700;
  color: #0f172a; letter-spacing: -0.01em; line-height: 1.2;
}
.district-hover-title svg { color: #2563eb; font-size: 15px; flex-shrink: 0; }
.district-hover-titletext { display: flex; flex-direction: column; min-width: 0; }
.district-hover-name { font-weight: 700; line-height: 1.2; }
/* Makes it explicit the figures below are district AVERAGES, not one school. */
.district-hover-sub {
  font-size: 12px; font-weight: 600;
  text-transform: uppercase; letter-spacing: 0.04em;
  color: var(--color-primary);
  line-height: 1.3; margin-top: 1px;
}
.district-hover-meta {
  display: flex;
  flex-direction: column;
  align-items: flex-end;
  gap: 3px;
}
.district-hover-count {
  font-size: 12px; color: #64748b; font-weight: 600;
  white-space: nowrap; font-variant-numeric: tabular-nums;
}
/* Rank badge in the hover-card header (state rank, or a district's rank within
   its state). Amber to read as a standing/achievement, matching the trophy in
   the rankings panel; muted gray when the entity has no score to rank. */
.district-hover-rank {
  display: inline-flex; align-items: center; gap: 4px;
  background: #fef3c7; color: #92400e;
  font-size: 12px; font-weight: 700;
  padding: 2px 9px; border-radius: 999px;
  border: 1px solid #fde68a;
  white-space: nowrap; font-variant-numeric: tabular-nums;
}
.district-hover-rank svg { font-size: 11px; flex-shrink: 0; }
.district-hover-rank .dh-rank-of { font-weight: 600; opacity: 0.72; }
.district-hover-rank-na {
  background: #f1f5f9; color: #64748b; border-color: #e2e8f0;
}
.district-hover-body {
  display: grid;
  grid-template-columns: repeat(3, 1fr);
}
.district-hover-stat {
  padding: 9px 11px;
  border-right: 1px solid #eef2f6;
  border-bottom: 1px solid #eef2f6;
  /* Allow the 1fr grid tracks to shrink to equal widths instead of being
     forced wider by a long nowrap label (which would clip past the card). */
  min-width: 0;
}
/* No right border on the last column, no bottom border on the last row. */
.district-hover-stat:nth-child(3n) { border-right: 0; }
.district-hover-stat:nth-child(n+4) { border-bottom: 0; }
.district-hover-stat-head {
  display: flex; align-items: center; gap: 5px;
  color: #64748b;
  font-size: 12px; font-weight: 700;
  text-transform: uppercase; letter-spacing: 0.04em;
  margin-bottom: 5px; white-space: nowrap;
}
.district-hover-stat-head svg { color: #2563eb; font-size: 11px; flex-shrink: 0; }
/* Safety net: if a label can't fit (e.g. a wide fallback font before Inter
   loads), ellipsize it rather than letting it bleed into the next cell. */
.district-hover-stat-head span {
  min-width: 0;
  overflow: hidden;
  text-overflow: ellipsis;
}
.district-hover-stat-value {
  font-size: 18px; font-weight: 700; line-height: 1;
  color: #0f172a; letter-spacing: -0.02em;
  font-variant-numeric: tabular-nums;
}
.district-hover-stat-value.na {
  color: #64748b; font-weight: 500; font-size: 13px; letter-spacing: 0;
}
.district-hover-foot {
  padding: 8px 14px;
  border-top: 1px solid #eef2f6;
  background: #f8fafc;
  font-size: 12px;
  color: #64748b;
  line-height: 1.4;
}
.kpi-stat-value {
  font-size: 23px; font-weight: 700; line-height: 1;
  letter-spacing: -0.02em;
  color: var(--text-primary);
  font-variant-numeric: tabular-nums;
}
.kpi-stat-value.na {
  color: var(--text-tertiary); font-weight: 500;
  font-size: 15px; letter-spacing: 0;
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
  font-size: 13px; font-weight: 700;
  text-transform: uppercase; letter-spacing: 0.06em;
  color: var(--text-secondary);
}
.panel-title svg { color: var(--color-primary); font-size: 15px; }
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
  font-size: 12px; font-weight: 700;
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
  font-size: 14px;
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
.selectize-dropdown .option { padding: 9px 12px !important; font-size: 14px; }
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
  font-size: 14px; font-weight: 600;
  cursor: pointer; transition: all 0.15s;
  box-shadow: var(--shadow-xs);
}
.btn-modern:hover {
  background: #f8fafc;
  border-color: var(--color-primary);
  color: var(--color-primary);
  transform: translateY(-1px);
}
/* 'Back to {state}' button — only shown when drilled into a district/school, so
   you can step up one level (to the state) instead of resetting all the way out.
   Soft blue to read as the suggested action, sits just above 'Reset view'. */
.btn-back-state {
  margin-bottom: 8px;
  background: #eff6ff;
  border-color: #bfdbfe;
  color: var(--color-primary);
}
.btn-back-state:hover {
  background: var(--color-primary);
  border-color: var(--color-primary);
  color: #ffffff;
  transform: translateY(-1px);
}

/* ===================== DISTRICT LEGEND ===================== */
.legend-section {
  margin-top: 20px;
  padding-top: 18px;
  border-top: 1px solid var(--border-color);
}
.legend-section-head {
  display: flex; align-items: center; justify-content: space-between;
  margin-bottom: 10px;
}
.legend-section-title {
  display: flex; align-items: center; gap: 8px;
  font-size: 13px; font-weight: 700;
  text-transform: uppercase; letter-spacing: 0.06em;
  color: var(--text-secondary);
}
.legend-section-title svg { color: var(--color-primary); font-size: 15px; }
.legend-section-count {
  font-size: 12px; font-weight: 600;
  color: var(--text-tertiary);
  font-variant-numeric: tabular-nums;
}

/* Search input */
.legend-search-wrap {
  position: relative;
  margin-bottom: 10px;
}
.legend-search-wrap > svg {
  position: absolute;
  left: 11px; top: 50%;
  transform: translateY(-50%);
  color: var(--text-tertiary);
  font-size: 13px;
  pointer-events: none;
  z-index: 2;
}
.legend-search-wrap .form-group { margin-bottom: 0 !important; }
.legend-search-wrap input {
  width: 100%;
  height: 34px !important;
  min-height: 34px !important;
  padding: 6px 12px 6px 32px !important;
  background: #f8fafc !important;
  border: 1px solid var(--border-color) !important;
  border-radius: 8px !important;
  font-size: 13.5px !important;
  color: var(--text-primary) !important;
  box-shadow: none !important;
  transition: background 0.15s ease, border-color 0.15s ease, box-shadow 0.15s ease;
}
.legend-search-wrap input::placeholder { color: var(--text-tertiary); }
.legend-search-wrap input:focus {
  background: #ffffff !important;
  border-color: var(--color-primary) !important;
  box-shadow: 0 0 0 3px rgba(37, 99, 235, 0.10) !important;
  outline: none;
}

/* List container */
.legend-list {
  max-height: 320px;
  overflow-y: auto;
  margin: 0 -8px;
  padding: 2px 8px 4px;
  position: relative;
}
.legend-list::-webkit-scrollbar { width: 6px; }
.legend-list::-webkit-scrollbar-track { background: transparent; }
.legend-list::-webkit-scrollbar-thumb {
  background: #e2e8f0; border-radius: 3px;
}
.legend-list::-webkit-scrollbar-thumb:hover { background: #cbd5e1; }
.legend-list { scrollbar-width: thin; scrollbar-color: #e2e8f0 transparent; }

/* Group header */
.legend-group { margin-bottom: 8px; }
.legend-group:last-child { margin-bottom: 0; }
.legend-group-head {
  display: flex; align-items: center; gap: 6px;
  padding: 7px 4px 5px;
  font-size: 12px; font-weight: 700;
  color: var(--text-tertiary);
  text-transform: uppercase; letter-spacing: 0.06em;
  position: sticky;
  top: 0;
  background: rgba(255, 255, 255, 0.96);
  -webkit-backdrop-filter: blur(8px); backdrop-filter: blur(8px);
  z-index: 1;
  border-bottom: 1px solid #f1f5f9;
}
.legend-group-head svg { font-size: 10px; opacity: 0.8; }
.legend-group-count {
  margin-left: auto;
  font-weight: 600;
  color: var(--text-tertiary);
  font-variant-numeric: tabular-nums;
}

/* Individual row */
.legend-item {
  display: flex; align-items: center; gap: 10px;
  padding: 7px 8px 7px 5px;
  border-radius: 7px;
  cursor: pointer;
  border-left: 3px solid transparent;
  transition: background 0.12s ease, border-color 0.12s ease, padding 0.15s ease;
  user-select: none;
}
.legend-item:hover {
  background: #f1f5f9;
}
.legend-item:hover .legend-item-arrow {
  opacity: 1;
  transform: translateX(2px);
}
.legend-item.is-active {
  background: var(--color-primary-tint);
  border-left-color: var(--color-primary);
  padding-left: 8px;
}
.legend-item.is-active .legend-item-name { color: var(--color-primary); }
.legend-item.is-active .legend-item-arrow { opacity: 1; color: var(--color-primary); }

.legend-item-swatch {
  width: 12px; height: 12px;
  border-radius: 4px;
  flex-shrink: 0;
  box-shadow:
    inset 0 0 0 1px rgba(15, 23, 42, 0.20),
    0 1px 2px rgba(15, 23, 42, 0.08);
}
.legend-item-text {
  display: flex; flex-direction: column;
  min-width: 0; flex: 1;
  gap: 1px;
}
.legend-item-name {
  font-size: 13.5px; font-weight: 600;
  color: var(--text-primary);
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
  line-height: 1.2;
}
.legend-item-meta {
  font-size: 12px;
  color: var(--text-tertiary);
  font-variant-numeric: tabular-nums;
  line-height: 1.2;
}
.legend-item-arrow {
  color: var(--text-tertiary);
  font-size: 12px;
  opacity: 0;
  flex-shrink: 0;
  transition: opacity 0.15s ease, transform 0.15s ease;
}

/* Schools sub-list — expands beneath the ACTIVE district so the user can pick a
   school and zoom the map to it. Indented and tied to the district by a left
   rail; rows are a touch smaller than district rows. */
.legend-school-sub {
  display: flex; flex-direction: column; gap: 1px;
  margin: 1px 0 8px 17px;
  padding-left: 8px;
  border-left: 2px solid var(--color-primary-tint);
}
.legend-subitem { padding: 5px 8px 5px 6px; }
.legend-subitem .legend-item-name { font-size: 12.5px; }
.legend-subitem .legend-item-swatch { width: 10px; height: 10px; }
.legend-subitem .legend-item-arrow { opacity: 0.45; }
.legend-subitem:hover .legend-item-arrow { opacity: 1; color: var(--color-primary); }
.legend-subitem.is-active { background: var(--color-primary-tint); }
.legend-subitem.is-active .legend-item-name { color: var(--color-primary); }

/* Empty state */
.legend-empty {
  padding: 22px 14px;
  text-align: center;
  color: var(--text-tertiary);
  font-size: 13px;
}
.legend-empty svg {
  display: block; margin: 0 auto 6px;
  font-size: 21px; color: var(--text-tertiary);
}
.legend-more-note {
  padding: 7px 8px 2px;
  font-size: 12px;
  font-style: italic;
  color: var(--text-tertiary);
}

/* ===================== SCOPE BLOCK ===================== */
.scope-block {
  margin-top: 18px;
  padding: 14px;
  background: linear-gradient(135deg, var(--color-primary-tint) 0%, #f0f7ff 100%);
  border: 1px solid rgba(37, 99, 235, 0.14);
  border-radius: var(--radius-md);
}
.scope-eyebrow {
  font-size: 12px; font-weight: 700;
  color: var(--color-primary);
  text-transform: uppercase; letter-spacing: 0.07em;
}
.scope-value {
  font-size: 16px; font-weight: 700;
  color: var(--text-primary);
  margin-top: 4px; line-height: 1.25;
}
.scope-meta { font-size: 13px; color: var(--text-secondary); margin-top: 4px; }
.scope-note {
  margin-top: 10px; padding-top: 10px;
  border-top: 1px solid rgba(37, 99, 235, 0.14);
  font-size: 12px; color: var(--text-tertiary); line-height: 1.45;
}

/* Detail panel */
.detail-panel {
  position: absolute;
  bottom: 20px; right: 20px;
  width: 360px; max-height: calc(100% - 200px);
  z-index: 600;
  display: flex; flex-direction: column;
}
/* At the school drill level the rankings list sits above the detail card in the
   right column, so cap the card to the bottom ~44% to tile without overlap. */
.detail-panel.detail-compact { max-height: calc(44vh); }
.detail-body { padding: 18px; overflow-y: auto; }
.detail-eyebrow {
  font-size: 12px; font-weight: 700;
  color: var(--color-primary);
  text-transform: uppercase; letter-spacing: 0.07em;
  margin-bottom: 4px;
}
.detail-title {
  font-size: 18px; font-weight: 700; letter-spacing: -0.01em;
  color: var(--text-primary); line-height: 1.3;
}
.detail-address {
  display: flex; align-items: flex-start; gap: 6px;
  margin-top: 8px; padding-bottom: 14px;
  border-bottom: 1px solid var(--border-color);
  color: var(--text-secondary); font-size: 13.5px;
}
.detail-address svg { flex-shrink: 0; color: var(--text-tertiary); margin-top: 2px; }
.stat-section { margin-top: 14px; }
.stat-section-title {
  font-size: 12px; font-weight: 700;
  color: var(--text-tertiary);
  text-transform: uppercase; letter-spacing: 0.07em;
  margin-bottom: 6px;
}
.stat-row {
  display: flex; justify-content: space-between; align-items: center;
  padding: 7px 0;
  border-bottom: 1px dashed #eef2f6;
  font-size: 14px;
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
  font-size: 13px; font-weight: 600;
  border: 1px solid rgba(37, 99, 235, 0.18);
  transition: all 0.15s;
}
.source-link:hover {
  background: var(--color-primary-soft); transform: translateY(-1px);
  text-decoration: none;
}
.empty-card {
  text-align: center; padding: 28px 16px;
  color: var(--text-tertiary); font-size: 14px;
}
.empty-card-icon {
  font-size: 27px; display: block; margin-bottom: 8px;
  color: var(--text-tertiary);
}

/* ===================== STATE RANKING PANEL ===================== */
.state-rank-panel {
  position: absolute;
  top: 20px; right: 20px;
  width: 430px;
  z-index: 600;
  display: flex; flex-direction: column;
  overflow: hidden;
}
.state-rank-panel .panel-head { border-bottom: 1px solid var(--border-color); }
.srank-info {
  display: inline-flex; align-items: center;
  color: var(--color-primary); opacity: 0.6; cursor: help;
  transition: opacity 0.15s ease;
}
.srank-info:hover { opacity: 1; }
.srank-subhead {
  display: flex; align-items: center; gap: 6px;
  padding: 8px 16px;
  font-size: 11.5px; font-weight: 600;
  text-transform: uppercase; letter-spacing: 0.04em;
  color: var(--text-tertiary);
  background: var(--bg-subtle);
  border-bottom: 1px solid var(--border-color);
}
.srank-subhead svg { color: var(--color-primary); font-size: 13px; flex-shrink: 0; }
/* Drill-down breadcrumb bar (All States > State > District) */
.srank-crumbs-bar {
  padding: 7px 14px;
  background: var(--bg-subtle);
  border-bottom: 1px solid var(--border-color);
}
.rank-crumbs {
  display: flex; align-items: center; flex-wrap: wrap; gap: 4px;
  font-size: 12px; line-height: 1.35;
}
.rank-crumb { display: inline-flex; align-items: center; max-width: 100%; }
.rank-crumb-link {
  color: var(--color-primary); font-weight: 600; cursor: pointer;
  text-decoration: none;
}
.rank-crumb-link:hover { text-decoration: underline; }
.rank-crumb-cur {
  color: var(--text-primary); font-weight: 700;
  overflow: hidden; text-overflow: ellipsis; white-space: nowrap;
}
.rank-crumb-sep {
  display: inline-flex; align-items: center;
  color: var(--text-tertiary); opacity: 0.7; font-size: 11px;
}
.srank-body { padding: 4px 8px 6px; overflow: hidden; }
.srank-foot {
  display: flex; align-items: flex-start; gap: 6px;
  padding: 8px 14px 10px;
  border-top: 1px solid var(--border-color);
  background: var(--bg-subtle);
  font-size: 11px; line-height: 1.4; color: var(--text-tertiary);
}
.srank-foot svg { color: var(--color-primary); font-size: 12px; flex-shrink: 0; margin-top: 1px; }

/* DT overrides — compact, clean ranking table */
.state-rank-panel table.dataTable {
  font-size: 12.5px; border-collapse: collapse !important; margin: 0 !important;
  width: 100% !important;
}
.state-rank-panel table.dataTable thead th {
  font-size: 10.5px; font-weight: 700; text-transform: uppercase;
  letter-spacing: 0.03em; color: var(--text-tertiary);
  border-bottom: 1px solid var(--border-color-strong) !important;
  border-top: 0 !important;
  padding: 7px 8px !important; background: var(--bg-card-solid);
}
.state-rank-panel table.dataTable tbody td {
  padding: 6px 8px !important;
  border-top: 1px solid #f1f5f9 !important;
  font-variant-numeric: tabular-nums;
  color: var(--text-primary);
}
/* The Name column wraps so long district/school names show in full; the numeric
   columns stay on one line and only take the room they need. */
.state-rank-panel table.dataTable td:nth-child(2),
.state-rank-panel table.dataTable th:nth-child(2) {
  white-space: normal; word-break: break-word; line-height: 1.25;
}
.state-rank-panel table.dataTable td:not(:nth-child(2)),
.state-rank-panel table.dataTable th:not(:nth-child(2)) { white-space: nowrap; }
.state-rank-panel table.dataTable tbody tr { cursor: pointer; transition: background 0.1s ease; }
.state-rank-panel table.dataTable tbody tr:hover td { background: var(--color-primary-tint) !important; }
.state-rank-panel table.dataTable tbody tr.selected td {
  background: var(--color-primary-soft) !important;
}
.state-rank-panel table.dataTable tbody tr.selected td:first-child {
  box-shadow: inset 3px 0 0 var(--color-primary);
}
/* Pinned average row (always the first body row) reads as a summary/total bar
   above the ranked rows; overrides the hover + Index colour-bar so it stays a
   clean, uniform highlight. */
.state-rank-panel table.dataTable tbody tr:first-child td,
.state-rank-panel table.dataTable tbody tr:first-child:hover td {
  background: var(--color-primary-tint) !important;
  font-weight: 700;
  color: var(--text-primary);
  border-top: 0 !important;
  border-bottom: 2px solid var(--border-color-strong) !important;
  cursor: default;
}
.state-rank-panel table.dataTable tbody tr:first-child td:first-child::before {
  content: '\\2605';                 /* star marks the average row */
  color: var(--color-primary);
  font-size: 11px;
}
.state-rank-panel .dataTables_scrollBody::-webkit-scrollbar { width: 6px; }
.state-rank-panel .dataTables_scrollBody::-webkit-scrollbar-thumb {
  background: #e2e8f0; border-radius: 3px;
}
.state-rank-panel .dataTables_scrollHead { border-radius: 0; }
/* Collapse on screens too narrow to hold both side panels + the KPI bar. */
@media (max-width: 1480px) { .state-rank-panel { width: 360px; } }
@media (max-width: 1180px) { .state-rank-panel { width: 320px; } }
@media (max-width: 1060px) { .state-rank-panel { display: none !important; } }

/* ===================== DATA COVERAGE NOTES MODAL ===================== */
.dn-link, .footer-link {
  color: var(--color-primary); font-weight: 600; cursor: pointer;
  text-decoration: underline; text-underline-offset: 2px;
}
.dn-link:hover, .footer-link:hover { color: var(--color-primary-700); }
.footer-link {
  display: inline-flex; align-items: center; gap: 5px;
  text-decoration: none; font-weight: 600;
}
.footer-link:hover { text-decoration: underline; }
.data-notes { font-family: 'Inter', sans-serif; color: var(--text-primary); }
.dn-head { display: flex; gap: 14px; align-items: flex-start; margin-bottom: 18px; }
.dn-head-icon {
  width: 44px; height: 44px; flex-shrink: 0; border-radius: 12px;
  display: flex; align-items: center; justify-content: center;
  background: var(--color-primary-soft); color: var(--color-primary); font-size: 22px;
}
.dn-title { margin: 0 0 4px; font-size: 20px; font-weight: 700; letter-spacing: -0.01em; }
.dn-lead { margin: 0; font-size: 14px; color: var(--text-secondary); line-height: 1.5; }
.dn-reasons { display: grid; gap: 10px; margin-bottom: 20px; }
.dn-reason {
  display: flex; gap: 12px; padding: 12px 14px;
  background: var(--bg-subtle); border: 1px solid var(--border-color); border-radius: 12px;
}
.dn-reason-icon { color: var(--color-primary); font-size: 17px; flex-shrink: 0; margin-top: 1px; }
.dn-reason-title { font-size: 14px; font-weight: 700; margin-bottom: 2px; }
.dn-reason-body { font-size: 13px; color: var(--text-secondary); line-height: 1.5; }
.dn-subhead {
  font-size: 12px; font-weight: 700; text-transform: uppercase; letter-spacing: 0.06em;
  color: var(--text-tertiary); margin: 0 0 10px;
}
.dn-states { display: grid; gap: 10px; }
.dn-state {
  padding: 12px 14px; background: #ffffff;
  border: 1px solid var(--border-color); border-left: 3px solid var(--color-primary);
  border-radius: 10px;
}
.dn-state-head {
  display: flex; align-items: baseline; justify-content: space-between;
  gap: 10px; margin-bottom: 8px;
}
.dn-state-name { font-size: 15px; font-weight: 700; }
.dn-state-count { font-size: 12px; color: var(--text-tertiary); font-variant-numeric: tabular-nums; }
.dn-pills { display: flex; flex-wrap: wrap; gap: 6px; margin-bottom: 8px; }
.dn-pill {
  font-size: 11.5px; font-weight: 600; padding: 3px 9px; border-radius: 999px;
  background: #fef2f2; color: #b91c1c; border: 1px solid #fecaca;
}
.dn-state-detail { font-size: 13px; color: var(--text-secondary); line-height: 1.5; }
.dn-foot { margin: 16px 0 0; font-size: 13px; color: var(--text-tertiary); font-style: italic; }

/* Map footer */
.map-footer {
  position: absolute; bottom: 0; left: 0; right: 0;
  display: flex; align-items: center; justify-content: space-between;
  padding: 6px 16px;
  background: rgba(255,255,255,0.95);
  -webkit-backdrop-filter: blur(8px); backdrop-filter: blur(8px);
  border-top: 1px solid var(--border-color);
  font-size: 12px; color: var(--text-tertiary);
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
  line-height: 32px !important; font-size: 17px !important;
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
  font-size: 11px !important;
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
  font-size: 23px; font-weight: 700;
  letter-spacing: -0.01em;
  margin: 0;
}
.compare-subtitle {
  font-size: 14px; color: var(--text-secondary);
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
  font-size: 13px; font-weight: 700;
  text-transform: uppercase; letter-spacing: 0.06em;
  color: var(--text-secondary);
}
.compare-card-title svg { color: var(--color-primary); font-size: 15px; }
.compare-card-meta {
  font-size: 12px; color: var(--text-tertiary);
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
  font-size: 12px; font-weight: 700;
  color: var(--text-tertiary);
  text-transform: uppercase; letter-spacing: 0.06em;
}
.compare-stat-value {
  font-size: 23px; font-weight: 700; line-height: 1.1;
  margin-top: 4px;
  font-variant-numeric: tabular-nums;
  color: var(--text-primary);
}
.compare-stat-meta {
  font-size: 12.5px; color: var(--text-secondary);
  margin-top: 4px;
}
@media (max-width: 760px) {
  .compare-stat-strip { grid-template-columns: repeat(2, minmax(0, 1fr)); }
}
@media (max-width: 540px) {
  .compare-stat-strip { grid-template-columns: 1fr; }
}

/* DT polish */
table.dataTable thead th {
  font-size: 12px !important;
  font-weight: 700 !important;
  text-transform: uppercase;
  letter-spacing: 0.05em;
  color: var(--text-secondary) !important;
  border-bottom: 2px solid var(--border-color) !important;
}
table.dataTable tbody td {
  font-size: 14px !important;
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
  font-size: 13px !important;
}
.dataTables_wrapper .dataTables_info,
.dataTables_wrapper .dataTables_paginate { font-size: 13px !important; }

/* Responsive (map) */
/* Responsive (map) */
@media (max-width: 1320px) {
  /* Below this the centered bar gets tight, so hide the colour legend and give
     the metric cards their room back. */
  .kpi-legend { display: none; }
}
@media (max-width: 1180px) {
  .kpi-stat-value { font-size: 19px; }
}
@media (max-width: 880px) {
  .kpi-panel-body { flex-wrap: wrap; }
  .kpi-stat { border-right: 0; border-bottom: 1px solid var(--border-color); }
}
@media (max-width: 760px) {
  .control-panel { width: calc(100vw - 32px); top: 16px; left: 16px; }
  .kpi-row {
    top: auto; bottom: 56px; left: 16px; right: 16px;
    transform: none; max-width: none;
  }
  .detail-panel { display: none; }
}

/* ============================================================
   ONBOARDING — SECTION HEADINGS
   Small uppercase eyebrow style with an accent gradient bar
   to anchor each section visually inside the modal body.
   ============================================================ */
.onb-section-heading {
  display: flex;
  align-items: center;
  gap: 9px;
  font-size: 13.5px;
  font-weight: 700;
  letter-spacing: 0.07em;
  text-transform: uppercase;
  color: #475569;
  margin: 4px 0 12px;
}
.onb-section-heading::before {
  content: '';
  display: block;
  width: 3px;
  height: 13px;
  background: linear-gradient(180deg, #2563eb 0%, #6366f1 100%);
  border-radius: 2px;
}
.onb-section-heading.is-spaced { margin-top: 22px; }

/* ============================================================
   ONBOARDING — SCORE SCALE
   Horizontal gradient bar with percentile tick marks below.
   Communicates the 0-100 national-percentile scale at a glance.
   ============================================================ */
.score-scale-block {
  margin: 0 0 6px;
  padding: 14px 20px 18px;
  background: #f8fafc;
  border: 1px solid #eef2f6;
  border-radius: 12px;
}
.score-scale-meta {
  display: flex;
  justify-content: space-between;
  align-items: baseline;
  margin-bottom: 4px;
  font-size: 12px;
  font-weight: 600;
  color: #64748b;
}
.score-scale-meta strong {
  color: #0f172a;
  font-size: 13.5px;
  font-weight: 700;
  letter-spacing: -0.005em;
}
.score-scale-track {
  position: relative;
  height: 10px;
  background: linear-gradient(90deg, #fda4af 0%, #fcd34d 50%, #6ee7b7 100%);
  border-radius: 999px;
  margin: 22px 4px 30px;
  box-shadow:
    inset 0 0 0 1px rgba(15, 23, 42, 0.08),
    0 1px 2px rgba(15, 23, 42, 0.06);
}
.score-scale-marker {
  position: absolute;
  top: -6px;
  bottom: -18px;
  width: 1.5px;
  background: #64748b;
  pointer-events: none;
  border-radius: 1px;
}
.score-scale-marker.is-strong {
  background: #0f172a;
  width: 2px;
}
.score-scale-marker-label {
  position: absolute;
  top: calc(100% + 5px);
  left: 50%;
  transform: translateX(-50%);
  white-space: nowrap;
  font-size: 11.5px;
  font-weight: 600;
  color: #475569;
  font-variant-numeric: tabular-nums;
}
.score-scale-marker.is-strong .score-scale-marker-label {
  color: #0f172a;
  font-weight: 700;
}
.score-scale-caption {
  font-size: 13.5px;
  color: #475569;
  line-height: 1.55;
  margin: 0;
}
.score-scale-caption strong { color: #0f172a; font-weight: 600; }

/* ============================================================
   ONBOARDING — INDICATOR WEIGHT BARS
   Six horizontal bars whose fill width is the literal weight
   (30%, 20%, 10%) so users can see at a glance how each input
   contributes to the Overall Score.
   ============================================================ */
.indicator-bars {
  display: flex;
  flex-direction: column;
  gap: 14px;
  margin: 0 0 18px;
}
.indicator-bar { display: flex; flex-direction: column; gap: 5px; }
.indicator-bar-row {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 8px;
}
.indicator-bar-name {
  display: inline-flex;
  align-items: center;
  gap: 8px;
  font-size: 14px;
  font-weight: 600;
  color: #0f172a;
  letter-spacing: -0.005em;
}
.indicator-bar-name svg {
  color: #2563eb;
  font-size: 14px;
  flex-shrink: 0;
}
.indicator-bar-weight {
  font-size: 12.5px;
  font-weight: 700;
  color: #2563eb;
  font-variant-numeric: tabular-nums;
  background: rgba(37, 99, 235, 0.10);
  padding: 2px 9px;
  border-radius: 999px;
  letter-spacing: 0.01em;
}
.indicator-bar-track {
  position: relative;
  height: 6px;
  background: #f1f5f9;
  border-radius: 999px;
  overflow: hidden;
}
.indicator-bar-fill {
  position: absolute;
  inset: 0 auto 0 0;
  background: linear-gradient(90deg, #2563eb 0%, #6366f1 100%);
  border-radius: 999px;
  box-shadow: 0 1px 2px rgba(37, 99, 235, 0.30);
}
.indicator-bar-desc {
  font-size: 12.5px;
  color: #64748b;
  line-height: 1.45;
  margin: 1px 0 0;
}

/* ============================================================
   ONBOARDING — METRIC / DATA DEFINITION ROWS
   Reused for the About-the-data rows and the What-each-KPI-
   metric-means rows: an icon chip + bold name (optional data-
   year tag) + a plain-language definition.
   ============================================================ */
.metric-def-list {
  display: flex;
  flex-direction: column;
  gap: 10px;
  margin: 0 0 6px;
}
.metric-def {
  display: flex;
  align-items: flex-start;
  gap: 12px;
  padding: 12px 14px;
  background: #f8fafc;
  border: 1px solid #eef2f6;
  border-radius: 12px;
  transition: border-color 0.15s ease, background 0.15s ease;
}
.metric-def:hover {
  border-color: rgba(37, 99, 235, 0.20);
  background: #f0f7ff;
}
.metric-def-icon {
  width: 34px; height: 34px;
  flex-shrink: 0;
  display: flex; align-items: center; justify-content: center;
  background: #eff6ff;
  color: #2563eb;
  border-radius: 9px;
  font-size: 17px;
}
.metric-def-text { flex: 1; min-width: 0; }
.metric-def-name {
  display: flex;
  align-items: center;
  gap: 8px;
  flex-wrap: wrap;
  font-size: 16px;
  font-weight: 700;
  color: #0f172a;
  letter-spacing: -0.01em;
  margin-bottom: 3px;
}
.metric-def-tag {
  font-size: 12px;
  font-weight: 700;
  text-transform: uppercase;
  letter-spacing: 0.05em;
  color: #2563eb;
  background: rgba(37, 99, 235, 0.10);
  padding: 2px 8px;
  border-radius: 999px;
}
.metric-def-desc {
  font-size: 14.5px;
  color: #475569;
  line-height: 1.5;
  margin: 0;
}

/* ============================================================
   ONBOARDING — DATA SOURCES TABLE + COVERAGE NOTES
   A scannable per-source / per-year table plus two left-accent
   callouts (one info, one amber warning) for the CCD nuance and
   the assessment-suppression caveat.
   ============================================================ */
.data-source-card {
  background: #ffffff;
  border: 1px solid #eef2f6;
  border-radius: 12px;
  padding: 6px 8px 2px;
  margin-bottom: 12px;
}
.data-source-table {
  width: 100%;
  border-collapse: collapse;
  font-size: 14.5px;
}
.data-source-table thead th {
  text-align: left;
  font-size: 12.5px;
  font-weight: 700;
  text-transform: uppercase;
  letter-spacing: 0.05em;
  color: #64748b;
  padding: 8px 12px 7px;
  border-bottom: 1px solid #e2e8f0;
}
.data-source-table thead th:last-child { text-align: right; }
.data-source-table tbody td {
  padding: 9px 12px;
  border-bottom: 1px solid #f1f5f9;
  color: #475569;
  vertical-align: top;
  line-height: 1.4;
}
.data-source-table tbody tr:last-child td { border-bottom: 0; }
.data-source-table tbody td:first-child {
  font-weight: 600;
  color: #0f172a;
}
.data-source-table tbody td:last-child {
  text-align: right;
  font-variant-numeric: tabular-nums;
  white-space: nowrap;
  color: #2563eb;
  font-weight: 600;
}
.data-note {
  display: flex;
  align-items: flex-start;
  gap: 8px;
  padding: 10px 13px;
  margin-bottom: 10px;
  background: #f8fafc;
  border-left: 3px solid #2563eb;
  border-radius: 0 8px 8px 0;
  font-size: 13.5px;
  color: var(--text-secondary);
  line-height: 1.5;
}
.data-note > svg:first-child {
  color: #2563eb;
  font-size: 15px;
  flex-shrink: 0;
  margin-top: 1px;
}
.data-note strong { color: #0f172a; font-weight: 600; }
.data-note a { color: #2563eb; font-weight: 600; text-decoration: none; }
.data-note a:hover { text-decoration: underline; }
.data-note.is-warn { border-left-color: #f59e0b; }
.data-note.is-warn > svg:first-child { color: #f59e0b; }

/* ============================================================
   ONBOARDING — KEY HIGHLIGHT CALLOUT
   Amber-highlighted, bolded banner at the top of the modal body
   clarifying that the 2025-2026 edition label is not the data
   year — the underlying metrics are 2022-2023 data.
   ============================================================ */
.onb-highlight {
  display: flex;
  gap: 11px;
  align-items: flex-start;
  padding: 13px 15px;
  margin-bottom: 18px;
  background: linear-gradient(135deg, #fffbeb 0%, #fef3c7 100%);
  border: 1px solid #fde68a;
  border-left: 4px solid #f59e0b;
  border-radius: 10px;
}
.onb-highlight > svg:first-child {
  color: #b45309;
  font-size: 18px;
  flex-shrink: 0;
  margin-top: 1px;
}
.onb-highlight-lead {
  font-size: 15.5px;
  font-weight: 700;
  color: #0f172a;
  letter-spacing: -0.01em;
  margin: 0 0 4px;
  line-height: 1.35;
}
.onb-highlight-body {
  font-size: 14.5px;
  color: #44403c;
  line-height: 1.55;
  margin: 0;
}
.onb-highlight-body strong { color: #0f172a; font-weight: 700; }

/* ============================================================
   ONBOARDING — REOPEN HINT (modal footer left side)
   ============================================================ */
.onb-reopen-hint {
  display: inline-flex;
  align-items: center;
  gap: 7px;
  font-size: 12.5px;
  color: #64748b;
  margin: 0;
  line-height: 1.4;
}
.onb-reopen-hint svg { color: #2563eb; font-size: 13px; flex-shrink: 0; }

/* ============================================================
   COMPARE TAB — METHODOLOGY CONTEXT STRIP
   Small gradient ribbon at the top of the Compare tab linking
   users back to the onboarding guide. Also visible as a CTA
   when first arriving on the tab from the Map.
   ============================================================ */
.compare-info-strip {
  display: flex;
  align-items: center;
  gap: 12px;
  padding: 11px 16px;
  margin-bottom: 18px;
  background: linear-gradient(135deg, #eff6ff 0%, #f5f3ff 100%);
  border: 1px solid rgba(37, 99, 235, 0.14);
  border-radius: 12px;
  font-size: 13.5px;
  color: #475569;
  line-height: 1.5;
}
.compare-info-strip > svg:first-child {
  color: #2563eb;
  font-size: 17px;
  flex-shrink: 0;
}
.compare-info-strip strong { color: #0f172a; font-weight: 600; }
.compare-info-link {
  margin-left: auto;
  display: inline-flex;
  align-items: center;
  gap: 6px;
  padding: 7px 12px;
  background: white;
  border: 1px solid rgba(37, 99, 235, 0.22);
  border-radius: 8px;
  color: #2563eb;
  font-size: 13px;
  font-weight: 600;
  cursor: pointer;
  white-space: nowrap;
  transition:
    background 0.15s ease,
    color 0.15s ease,
    transform 0.15s ease,
    box-shadow 0.15s ease,
    border-color 0.15s ease;
}
.compare-info-link:hover {
  background: #2563eb;
  color: white;
  border-color: #2563eb;
  transform: translateY(-1px);
  box-shadow: 0 4px 12px rgba(37, 99, 235, 0.28);
}
.compare-info-link svg { font-size: 11.5px; transition: transform 0.15s ease; }
.compare-info-link:hover svg { transform: translateX(2px); }
@media (max-width: 720px) {
  .compare-info-strip { flex-wrap: wrap; }
  .compare-info-link {
    margin-left: 0;
    width: 100%;
    justify-content: center;
  }
}

/* ============================================================
   COMPARE TAB — PER-METRIC DESCRIPTION
   Inline help text below the filter grid; updates as the user
   changes the metric dropdown. Uses an accent left border for
   a 'callout' feel without dominating the controls card.
   ============================================================ */
.compare-metric-desc {
  display: flex;
  align-items: flex-start;
  gap: 9px;
  margin-top: 16px;
  padding: 10px 13px;
  background: #f8fafc;
  border-left: 3px solid #2563eb;
  border-radius: 0 8px 8px 0;
  font-size: 13.5px;
  color: #475569;
  line-height: 1.5;
}
.compare-metric-desc > svg:first-child {
  color: #2563eb;
  font-size: 14.5px;
  flex-shrink: 0;
  margin-top: 2px;
}
.compare-metric-desc strong { color: #0f172a; font-weight: 600; }
"

# ============================================================================
# ONBOARDING MODAL + SCRIPT
# Welcome / methodology guide. Auto-opens on first visit (localStorage-gated)
# and can be reopened anytime via the help (?) icon in the navbar.
# ============================================================================

# One definition row inside the modal: an icon chip, a bold name (with an
# optional data-year tag), and a plain-language definition. Reused for both
# the "About the data" rows and the "What each KPI metric means" rows.
onb_def_row <- function(icon, name, desc, tag = NULL) {
  div(class = "metric-def",
    div(class = "metric-def-icon", bsicons::bs_icon(icon)),
    div(class = "metric-def-text",
      div(class = "metric-def-name",
        span(name),
        if (!is.null(tag)) span(class = "metric-def-tag", tag)
      ),
      p(class = "metric-def-desc", desc)
    )
  )
}

# Definitions for the six metrics shown in the KPI bar. Wording follows
# U.S. News & World Report's 2025-2026 Best High Schools methodology
# (verified against usnews.com), not assumed. Tags note the data year.
kpi_metric_defs <- list(
  list(icon = "pencil-square", name = "AP Taken", tag = "2022-2023",
       desc = "The percentage of a school's 12th-graders who took at least one AP or IB exam by the end of senior year. U.S. News calls this the participation rate — one of the two parts of its College Readiness Index."),
  list(icon = "patch-check-fill", name = "AP Passed", tag = "2022-2023",
       desc = "The percentage of 12th-graders who took an exam and earned a qualifying score — an AP score of 3 or higher, or an IB score of 4 or higher — on at least one AP or IB exam. U.S. News calls this the quality-adjusted participation rate."),
  list(icon = "calculator", name = "Math Proficiency", tag = "2022-2023",
       desc = "The share of students who scored proficient or above on Utah's statewide mathematics assessment. U.S. News combines math, reading, and science proficiency into one State Assessment indicator and compares schools within their state; each state sets its own proficiency levels."),
  list(icon = "book", name = "Reading Proficiency", tag = "2022-2023",
       desc = "The share of students who scored proficient or above on Utah's statewide reading and language-arts assessment, as reported by the state. Reading is one of the subjects U.S. News combines into that State Assessment proficiency indicator."),
  list(icon = "lightbulb", name = "Science Proficiency", tag = "2022-2023",
       desc = "The share of students who scored proficient or above on Utah's statewide science assessment. Science is combined with math and reading in U.S. News' State Assessment proficiency indicator."),
  list(icon = "mortarboard-fill", name = "Graduation Rate", tag = "Class of 2023",
       desc = "The four-year adjusted cohort rate: of the students who entered 9th grade in 2019-2020, the proportion who graduated within four years, by 2023.")
)

# "About the data" rows — high-level provenance + scope note. The per-source
# breakdown and coverage years live in the data_sources table below.
about_data_rows <- list(
  list(icon = "database-fill", name = "Where the data comes from",
       desc = "Every figure comes from U.S. News & World Report's 2025-2026 Best High Schools rankings, compiled with RTI International. U.S. News does not collect data from schools directly — it relies entirely on the third-party sources listed below."),
  list(icon = "ui-checks", name = "What this dashboard focuses on",
       desc = "U.S. News publishes many statistics for each school. This dashboard focuses on the six headline metrics in the KPI bar — AP Taken, AP Passed, Math, Reading, and Science proficiency, and Graduation Rate — each defined below.")
)

# Per-source provenance and the school year each input covers, taken from the
# U.S. News 2025-2026 methodology. Surfaced as a scannable table in the modal.
# All ranking inputs align to the 2022-2023 school year.
data_sources <- list(
  list(source = "State education agencies",   data = "Math, reading & science assessments", year = "2022-2023"),
  list(source = "State education agencies",   data = "Four-year graduation rates",           year = "2022-2023"),
  list(source = "College Board",              data = "AP exam results (grade 12)",            year = "2022-2023"),
  list(source = "International Baccalaureate", data = "IB exam results (grade 12)",            year = "2022-2023"),
  list(source = "Common Core of Data (NCES)", data = "Enrollment (grade 12), ethnicity, free/reduced-price lunch", year = "2022-2023")
)

onboarding_modal_ui <- div(
  id = "onboarding_overlay", class = "onboarding-overlay",
  div(id = "onb_modal", class = "onboarding-modal onb-carousel is-first",
      role = "dialog", `aria-modal` = "true", `aria-labelledby` = "onb_title",

    # Persistent close button — floats over every slide.
    tags$button(class = "btn-close-modal onb-close-float", `data-onb-close` = "1",
                type = "button", `aria-label` = "Close",
                bsicons::bs_icon("x-lg")),

    # ---- Slides viewport ----------------------------------------------
    div(class = "onb-carousel-viewport",
      div(class = "onb-carousel-track", id = "onb_track",

        # === SLIDE 1 — quote ==========================================
        div(class = "onb-slide onb-slide-quote",
          tags$img(class = "onb-quote-img", src = "quote.jpg",
                   alt = "Without data you are just another person with an opinion. — W. Edwards Deming, Data Scientist"),
          p(class = "onb-quote-caption", "Use the arrows below to continue")
        ),

        # === SLIDE 2 — mission ========================================
        div(class = "onb-slide",
          div(class = "onb-slide-body onb-mission",
            span(class = "onb-header-eyebrow", "Why this dashboard exists"),
            h2(class = "onb-header-title", "Transparency, so communities can act"),
            p(class = "onb-mission-lead",
              "This dashboard visualizes education-metric trends across public high schools nationwide. Its purpose is simple: help parents and communities see where their students are actually scoring today."),
            do.call(div, c(list(class = "metric-def-list"), list(
              onb_def_row("people-fill", "Built for parents & communities",
                "It gathers each school's and district's scores in one place so families and neighborhoods anywhere can stay informed about how their local students are doing."),
              onb_def_row("building", "A call for an official, current tool",
                "The hope is that state education agencies — and ultimately the U.S. Department of Education — will one day build and maintain an up-to-date version of something like this: one that students, parents, faculty, and policymakers can all use to see transparent, current scores of where students are."),
              onb_def_row("bar-chart-line-fill", "Data, not prescriptions",
                "This app does not claim to provide solutions for how schools can better serve students. It is an attempt to visualize and compare the data so that parents and leaders in every community can decide what to do with it."),
              onb_def_row("calendar-x", "A note on the data",
                "U.S. News publishes only the current edition — there is no year-over-year database, so trends over time cannot be shown here. And for some reason the current 2025-2026 edition reports scores from 2022-2023, which is poor practice for timely decisions.")
            ))),
            div(class = "onb-mission-close",
              bsicons::bs_icon("megaphone-fill"),
              span(
                tags$strong("The first step to real change is being honest about where we are."),
                " Whether you are a legislator, a school board member, or a parent, the hope is that this dashboard gives you a clearer picture of how our students are being educated — shown as faithfully as the available data allows.")
            )
          )
        ),

        # === SLIDE 3 — the guide ======================================
        div(class = "onb-slide",

          # ---- Header ----------------------------------------------------
          div(class = "onboarding-header",
            div(class = "onb-header-mark", bsicons::bs_icon("mortarboard-fill")),
            div(class = "onb-header-text",
              span(class = "onb-header-eyebrow",
                   "U.S. News 2025-2026 Best High Schools"),
              h2(id = "onb_title", class = "onb-header-title",
                 "Welcome to the U.S. Public High Schools dashboard"),
              p(class = "onb-header-sub",
                sprintf(
                  "An interactive geospatial view of every ranked public high school in the dataset — %s schools across %d districts in %d states.",
                  formatC(nrow(schools), big.mark = ","),
                  n_districts, n_states))
            )
          ),

          # ---- Body ------------------------------------------------------
          div(class = "onb-slide-body",

      # --- Key clarification: edition label vs. data year --------------
      div(class = "onb-highlight",
        bsicons::bs_icon("exclamation-circle-fill"),
        div(
          p(class = "onb-highlight-lead",
            "The '2025-2026' label is the ranking edition — not the data year."),
          p(class = "onb-highlight-body",
            "U.S. News calls these the ", tags$strong("2025-2026"),
            " Best High Schools rankings, but every metric shown here is calculated from ",
            tags$strong("2022-2023 data"),
            " — the most recent figures U.S. News has released. This dashboard shows the ",
            tags$strong("same data U.S. News publishes"),
            "; it is fully current with their rankings, but those underlying figures are a few years old and may not reflect a school's performance today.")
        )
      ),

      # --- About the data ----------------------------------------------
      h3(class = "onb-section-heading", "About the data"),
      do.call(div, c(list(class = "metric-def-list"),
        lapply(about_data_rows, function(r)
          onb_def_row(r$icon, r$name, r$desc))
      )),

      # --- Data sources & coverage years -------------------------------
      h3(class = "onb-section-heading is-spaced",
         "Data sources & coverage years"),
      div(class = "data-source-card",
        tags$table(class = "data-source-table",
          tags$thead(tags$tr(
            tags$th("Source"),
            tags$th("Data used in the rankings"),
            tags$th("School year")
          )),
          do.call(tags$tbody, lapply(data_sources, function(s)
            tags$tr(
              tags$td(s$source),
              tags$td(s$data),
              tags$td(s$year)
            )
          ))
        )
      ),
      div(class = "data-note",
        bsicons::bs_icon("info-circle-fill"),
        span("The ",
          tags$a(href = "https://nces.ed.gov/ccd/", target = "_blank",
                 "Common Core of Data"),
          " (NCES), last updated in 2024, supplies enrollment, ethnicity, and free / reduced-price lunch figures. The rankings use ",
          tags$strong("2022-2023"),
          " CCD data to align with the assessment year, while each school's profile on usnews.com shows the more current ",
          tags$strong("2023-2024"),
          " figures.")
      ),
      div(class = "data-note is-warn",
        bsicons::bs_icon("exclamation-triangle-fill"),
        span(tags$strong("Assessment coverage varies. "),
          "State suppression rules sometimes limited subject-level detail — some schools were scored on only one or two subjects (which were then weighted more heavily), and schools without usable assessment data were not ranked.")
      ),

      # --- What each KPI metric means ----------------------------------
      h3(class = "onb-section-heading is-spaced",
         "What each KPI metric means"),
      do.call(div, c(list(class = "metric-def-list"),
        lapply(kpi_metric_defs, function(m)
          onb_def_row(m$icon, m$name, m$desc, m$tag))
      )),

      # --- Using the dashboard (2x2 card grid) -------------------------
      h3(class = "onb-section-heading is-spaced", "Using the dashboard"),
      div(class = "onb-grid",
        div(class = "onb-section",
          div(class = "onb-section-icon", bsicons::bs_icon("geo-alt-fill")),
          h4(class = "onb-section-title", "Explore the map"),
          p(class = "onb-section-body",
            "Pan and zoom Utah. Hover a marker for a quick scorecard; click any district polygon to filter the dashboard to that district.")
        ),
        div(class = "onb-section",
          div(class = "onb-section-icon", bsicons::bs_icon("bar-chart-line-fill")),
          h4(class = "onb-section-title", "Rank and compare"),
          p(class = "onb-section-body",
            "Open the Compare Schools tab to rank any metric statewide or within a district, with an exportable, searchable table.")
        ),
        div(class = "onb-section",
          div(class = "onb-section-icon", bsicons::bs_icon("sliders")),
          h4(class = "onb-section-title", "Filter and drill in"),
          p(class = "onb-section-body",
            "Use the filter panel, the searchable district legend, or polygon clicks to scope the view. Reset returns to the statewide view.")
        ),
        div(class = "onb-section",
          div(class = "onb-section-icon", bsicons::bs_icon("clipboard-data")),
          h4(class = "onb-section-title", "Read each scorecard"),
          p(class = "onb-section-body",
            "Each school card shows Overall Score, Utah and national ranks, AP participation and pass rates, proficiency, and graduation.")
        )
      ),

      # --- Methodology details (collapsible disclosure) -----------------
      tags$details(class = "onb-method",
        tags$summary(class = "onb-method-summary",
          bsicons::bs_icon("file-earmark-text", class = "method-lead-icon"),
          span("Methodology, data sources, and limitations"),
          bsicons::bs_icon("chevron-right", class = "method-chev")
        ),
        div(class = "onb-method-content",
          p(tags$strong("How the Overall Score works"),
            " — the six metrics above are a subset of the inputs U.S. News uses. It standardizes six weighted indicators — College Readiness (30%), State Assessment Proficiency (20%), State Assessment Performance (20%), College Curriculum Breadth (10%), Underserved Student Performance (10%), and Graduation Rate (10%) — sums them, and converts the result to a 0-100 national percentile across roughly 18,000 ranked public high schools. A score of 80 means the school outperformed 80% of ranked schools."),
          p(tags$strong("Why some values show 'n/a'"),
            " — U.S. News reports certain figures as ranges or buckets (for example '>= 80%' or '< 10%') rather than exact numbers. These are not numeric, so they are excluded from the averages shown here."),
          tags$ul(
            tags$li(tags$strong("Charter schools"),
                    " are ranked. Each charter appears as its own LEA with no boundary polygon — they are statewide schools-of-choice."),
            tags$li(tags$strong("Private schools"),
                    " are not ranked due to limited public data."),
            tags$li(tags$strong("Bottom-quartile schools"),
                    " (below the 25th percentile) have their exact rank concealed by U.S. News and are shown as a ranking range.")
          ),
          p("For the full national methodology and per-state assessment notes, see the ",
            tags$a(href = "https://www.usnews.com/education/best-high-schools/articles/how-us-news-calculated-the-rankings",
                   target = "_blank",
                   "U.S. News Best High Schools methodology"),
            ".")
        )
      )
          )
        )
      )
    ),

    # ---- Nav bar (arrows + dots + start) ------------------------------
    div(class = "onb-carousel-nav",
      tags$button(id = "onb_prev", class = "onb-arrow onb-prev",
                  type = "button", `aria-label` = "Previous slide",
                  bsicons::bs_icon("chevron-left")),
      div(class = "onb-dots", id = "onb_dots",
        tags$button(class = "onb-dot is-active", type = "button",
                    `data-onb-goto` = "0", `aria-label` = "Go to slide 1"),
        tags$button(class = "onb-dot", type = "button",
                    `data-onb-goto` = "1", `aria-label` = "Go to slide 2"),
        tags$button(class = "onb-dot", type = "button",
                    `data-onb-goto` = "2", `aria-label` = "Go to slide 3")
      ),
      div(class = "onb-nav-right",
        tags$button(id = "onb_next", class = "onb-arrow onb-next",
                    type = "button", `aria-label` = "Next slide",
                    bsicons::bs_icon("chevron-right")),
        tags$button(id = "onb_start", class = "btn-primary-modal onb-start",
                    `data-onb-close` = "1", type = "button",
          span("Start exploring"),
          bsicons::bs_icon("arrow-right")
        )
      )
    )
  )
)

# Vanilla JS for the modal — runs without a server round-trip:
#   * Auto-shows the modal on first visit (localStorage-gated).
#   * Wires #open_onboarding (navbar help icon) to re-open.
#   * Closes on close-button, "Start exploring", overlay click, or Escape.
#   * Exposes window.utahHsOpenOnboarding so the Compare-tab CTA can call it.
onboarding_js <- '
(function() {
  var STORAGE_KEY = "utah_hs_onboarded_v1";
  var SLIDES = 3;
  var current = 0;
  var lastFocus = null;

  function getOverlay() {
    return document.getElementById("onboarding_overlay");
  }

  function updateNav() {
    var track = document.getElementById("onb_track");
    if (track) track.style.transform = "translateX(" + (-current * 100) + "%)";
    var modal = document.getElementById("onb_modal");
    if (modal) {
      modal.classList.toggle("is-first", current === 0);
      modal.classList.toggle("is-last", current === (SLIDES - 1));
    }
    var prev = document.getElementById("onb_prev");
    if (prev) prev.disabled = (current === 0);
    var dots = document.querySelectorAll("#onb_dots .onb-dot");
    for (var i = 0; i < dots.length; i++) {
      if (i === current) dots[i].classList.add("is-active");
      else dots[i].classList.remove("is-active");
    }
    var slides = document.querySelectorAll("#onb_track .onb-slide");
    for (var s = 0; s < slides.length; s++) {
      slides[s].setAttribute("aria-hidden", s === current ? "false" : "true");
      slides[s].inert = (s !== current);
      if (s === current) slides[s].scrollTop = 0;
    }
  }

  function goToSlide(i) {
    if (i < 0) i = 0;
    if (i > SLIDES - 1) i = SLIDES - 1;
    current = i;
    updateNav();
  }

  function openOnb() {
    var ov = getOverlay();
    if (!ov) return;
    lastFocus = document.activeElement;
    ov.classList.add("is-visible");
    document.body.style.overflow = "hidden";
    goToSlide(0);
    var closeBtn = ov.querySelector(".onb-close-float");
    if (closeBtn) closeBtn.focus();
  }

  function closeOnb() {
    var ov = getOverlay();
    if (ov) {
      ov.classList.remove("is-visible");
      document.body.style.overflow = "";
    }
    try { localStorage.setItem(STORAGE_KEY, "1"); } catch (e) {}
    if (lastFocus && lastFocus.focus) lastFocus.focus();
  }

  function maybeAutoShow() {
    var seen = false;
    try { seen = !!localStorage.getItem(STORAGE_KEY); } catch (e) {}
    if (!seen) setTimeout(openOnb, 600);
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", maybeAutoShow);
  } else {
    maybeAutoShow();
  }

  document.addEventListener("click", function(e) {
    if (e.target.closest("#open_onboarding")) {
      e.preventDefault();
      openOnb();
      return;
    }
    if (e.target.closest("#onb_next")) {
      e.preventDefault();
      goToSlide(current + 1);
      return;
    }
    if (e.target.closest("#onb_prev")) {
      e.preventDefault();
      goToSlide(current - 1);
      return;
    }
    var dot = e.target.closest("[data-onb-goto]");
    if (dot) {
      e.preventDefault();
      goToSlide(parseInt(dot.getAttribute("data-onb-goto"), 10));
      return;
    }
    if (e.target.closest("[data-onb-close]")) {
      e.preventDefault();
      closeOnb();
      return;
    }
    var ov = getOverlay();
    if (ov && e.target === ov) closeOnb();
  });

  document.addEventListener("keydown", function(e) {
    var ov = getOverlay();
    if (!ov || !ov.classList.contains("is-visible")) return;
    if (e.key === "Escape") { closeOnb(); return; }
    if (e.key === "ArrowRight") { goToSlide(current + 1); return; }
    if (e.key === "ArrowLeft") { goToSlide(current - 1); return; }
    if (e.key === "Tab") {
      var modal = document.getElementById("onb_modal");
      if (!modal) return;
      var nodes = modal.querySelectorAll("button:not([disabled]), a[href], [tabindex]");
      var list = [];
      for (var i = 0; i < nodes.length; i++) {
        var el = nodes[i];
        if (el.getAttribute("tabindex") === "-1") continue;
        var slide = el.closest(".onb-slide");
        if (slide && slide.inert) continue;
        if (el.offsetParent === null) continue;
        list.push(el);
      }
      if (!list.length) return;
      var first = list[0], lastEl = list[list.length - 1];
      if (!modal.contains(document.activeElement)) {
        e.preventDefault(); first.focus();
      } else if (e.shiftKey && document.activeElement === first) {
        e.preventDefault(); lastEl.focus();
      } else if (!e.shiftKey && document.activeElement === lastEl) {
        e.preventDefault(); first.focus();
      }
    }
  });

  window.utahHsOpenOnboarding = openOnb;
  window.utahHsCloseOnboarding = closeOnb;
})();
'

# ============================================================================
# UI
# ============================================================================
bslib::page_navbar(
  title = div(class = "navbar-brand-content",
    div(class = "brand-mark", bsicons::bs_icon("geo-alt-fill")),
    div(
      div(class = "brand-title", "U.S. Public High Schools"),
      div(class = "brand-subtitle", "U.S. News Best High Schools 2025-2026")
    )
  ),
  # The `title` above is rich HTML (icon + two text lines). Left to its default
  # (window_title = NA), bslib infers the browser-tab <title> by stringifying
  # that HTML, which dumps the bs_icon() <svg> markup into the tab. Setting
  # window_title explicitly gives the tab a clean, plain-text label and skips
  # the inference entirely.
  window_title = "U.S. Public High Schools",
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
    font_scale    = 1.05
  ),

  header = tagList(
    tags$meta(name = "viewport", content = "width=device-width, initial-scale=1"),
    # Custom favicon. Lives at www/education.png; Shiny serves www/ at the web
    # root, so href = 'education.png' resolves to /education.png. tags$head() is
    # hoisted into the document <head> by htmltools wherever it sits in the UI.
    tags$head(
      tags$link(rel = "icon", type = "image/jpg", href = "education.jpg")
    ),
    tags$style(HTML(app_css)),
    shinyjs::useShinyjs(),
    # Onboarding overlay + handler script. Position:fixed in CSS, so the
    # DOM placement is irrelevant; injecting in the header keeps it loaded
    # before the first paint so the auto-show timer can fire immediately.
    onboarding_modal_ui,
    tags$script(HTML(onboarding_js))
  ),

  # =========== TAB 1: Map dashboard ========================================
  bslib::nav_panel(
    title = tagList(bsicons::bs_icon("geo-alt"), "Map Dashboard"),
    value = "tab_map",

    div(class = "map-shell",
      leafletOutput("map", width = "100%", height = "100%"),

      # KPI row: a single metrics panel whose right-most cell is the proficiency
      # colour-scale legend (added inside kpi_cards' body, server.R).
      div(class = "kpi-row",
        div(class = "kpi-panel", id = "kpi_panel",
          uiOutput("kpi_cards")
        )
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
            tags$label("States", class = "field-label"),
            # Multi-select; every available state is selected by default. The
            # server scopes the District/School dropdowns, map, and legend to
            # whatever subset stays selected.
            selectInput("states", NULL,
              choices  = all_states,
              selected = all_states,
              multiple = TRUE, width = "100%")
          ),
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
          # Appears only when drilled into a district/school: steps back up to
          # the state level (all its districts) without resetting to all states.
          uiOutput("back_to_state_ui"),
          actionButton("reset_view",
            label = tagList(bsicons::bs_icon("arrow-counterclockwise"), "Reset view"),
            class = "btn-modern", style = "width:100%"),
          uiOutput("scope_block"),

          # --- District legend --------------------------------------------
          div(class = "legend-section",
            div(class = "legend-section-head",
              div(class = "legend-section-title",
                bsicons::bs_icon("palette-fill"),
                span("Districts & schools")
              ),
              span(class = "legend-section-count",
                   sprintf("%d districts · %d states", n_districts, n_states))
            ),
            div(class = "legend-search-wrap",
              bsicons::bs_icon("search"),
              textInput("legend_search", NULL,
                        value = "",
                        placeholder = "Search districts or schools...")
            ),
            div(class = "legend-list", id = "legend_list",
              uiOutput("district_legend")
            )
          )
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

      # State ranking panel (right side) — visible only in the all-states view.
      # Ranks states by an equal-weighted average of reading/math/science
      # proficiency. Click a row to drill into that state.
      div(class = "glass state-rank-panel", id = "state_rank_panel",
        div(class = "panel-head",
          div(class = "panel-title",
            bsicons::bs_icon("trophy-fill"), span("Rankings")),
          bslib::tooltip(
            span(class = "srank-info", bsicons::bs_icon("info-circle")),
            "Proficiency Index = the average of each group's reading, math & science proficiency (only the subjects actually reported). Higher is better; graduation and AP are excluded on purpose. Click a row to drill in: state → district → school.",
            placement = "left"
          )
        ),
        div(class = "srank-crumbs-bar",
          uiOutput("rank_breadcrumb")
        ),
        div(class = "srank-body",
          DT::DTOutput("state_rank_table")
        ),
        div(class = "srank-foot",
          bsicons::bs_icon("info-circle"),
          span("Index = avg of reading, math & science (subjects reported). Click a row to drill in; use the breadcrumb to go back. Blank = not reported — ",
               actionLink("data_coverage_info", "why?", class = "dn-link"))
        )
      ),

      # Map footer
      div(class = "map-footer",
        div(class = "footer-left",
          bsicons::bs_icon("database"),
          span("Sources:"),
          tags$a(href = "https://www.usnews.com/education/best-high-schools/utah/rankings",
                 target = "_blank", "U.S. News"),
          span("·"), span("U.S. Census / ArcGIS / OSM"), span("·"), span("Census TIGER 2023")
        ),
        div(class = "footer-right",
          actionLink("data_coverage_info_foot", tagList(
            bsicons::bs_icon("clipboard2-data"), "Data coverage"), class = "footer-link"),
          span("·"),
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

      # Methodology context strip — links back to the onboarding guide.
      # Visible at the top of the Compare tab so users always have a path
      # from "what does this number mean?" to the full scoring explainer.
      div(class = "compare-info-strip",
        bsicons::bs_icon("info-circle-fill"),
        span("Metrics here drive the ",
             tags$strong("U.S. News 2025-2026 Best High Schools"),
             " rankings — six indicators standardized into a 0-100 national percentile."),
        tags$button(class = "compare-info-link", type = "button",
                    onclick = "utahHsOpenOnboarding()",
          span("How is this scored?"),
          bsicons::bs_icon("arrow-right")
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
          ),

          # Plain-language explanation of the currently selected metric —
          # updates reactively as the user changes the Metric dropdown.
          uiOutput("cmp_metric_desc")
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
            # Height is sized to the row count in the server so bars stay
            # readable even with "All schools" (219 rows) selected.
            uiOutput("compare_chart_wrap")
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
  # Help icon — re-opens the onboarding/methodology modal.
  bslib::nav_item(
    bslib::tooltip(
      tags$button(
        id = "open_onboarding",
        class = "btn-navbar-icon",
        type = "button",
        `aria-label` = "Open dashboard guide",
        bsicons::bs_icon("question-circle")
      ),
      "How to use this dashboard",
      placement = "bottom"
    )
  ),
  bslib::nav_item(
    div(class = "navbar-stats",
      bsicons::bs_icon("buildings-fill"),
      div(class = "navbar-stat",
        span(class = "navbar-stat-num", nrow(schools)),
        span(class = "navbar-stat-label", "Schools")
      ),
      div(class = "navbar-stat-sep navbar-stat-extra"),
      div(class = "navbar-stat navbar-stat-extra",
        span(class = "navbar-stat-num", n_districts),
        span(class = "navbar-stat-label", "Districts")
      ),
      div(class = "navbar-stat-sep navbar-stat-extra"),
      div(class = "navbar-stat navbar-stat-extra",
        span(class = "navbar-stat-num", n_states),
        span(class = "navbar-stat-label", "States")
      )
    )
  )
)
