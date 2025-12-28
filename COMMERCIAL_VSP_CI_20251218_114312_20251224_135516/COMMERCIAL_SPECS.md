# VSP Commercial UI — Design & Contract Specs (CIO-level)

## 1) Design philosophy
### 1.1 CIO-level visibility
Dashboard is landing page:
- Total findings, severity distribution (6 buckets), trend, top risk, top module, top CWE.
- No config, no debug/dev content.
- Less text, more insights; clear “what to do next”.

### 1.2 BE → API → FE mapping (stateless)
Golden rule: FE never reads internal files/paths.
Each tab uses its own API contract; state comes from BE JSON:
- Dashboard: dashboard_v3 (prefer single-contract)
- Runs: runs_v3 + report links
- Releases: release_latest + release_download/audit
- Data Source: paging/filter/search API (no run_file_allow path)
- Settings/Rule Overrides: dedicated APIs

### 1.3 Component-based UI
Each component:
- 1 HTML section with stable id
- 1 API provides data
- 1 JS module: loadXxx() / renderXxx(data)

Core components:
KPI cards, donut, trendline, tool bars, top tables, filter/search.

### 1.4 Dark enterprise theme
Font: Inter (fallback system-ui)
Palette: #020617/#0f172a background, #111827 panels, borders #1f2937/#334155
Text: #e5e7eb primary, #9ca3af secondary
Severity colors:
CRITICAL #f97373; HIGH #fb923c; MEDIUM #facc15; LOW #22c55e; INFO #38bdf8; TRACE #a855f7
