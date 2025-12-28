#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CSS="$ROOT/static/css/vsp_v25_polish.css"
LOG="[VSP_THEME_COLORS]"

if [ -f "$CSS" ]; then
  BAK="$CSS.bak_sev_colors_$(date +%Y%m%d_%H%M%S)"
  cp "$CSS" "$BAK"
  echo "$LOG Backup $CSS -> $BAK"
fi

cat >> "$CSS" << 'CSS'

/* === VSP 2025 – Severity & gate colors (shared across 5 tabs) === */

.vsp-badge {
  display:inline-flex;
  align-items:center;
  padding:2px 8px;
  border-radius:999px;
  font-size:11px;
  font-weight:500;
  letter-spacing:0.02em;
  border:1px solid rgba(148,163,184,0.5);
  background:rgba(15,23,42,0.9);
  color:#e5e7eb;
}

.vsp-badge-red {
  border-color: rgba(248,113,113,0.9);
  background: radial-gradient(circle at top left,#450a0a,#111827);
  color:#fecaca;
}
.vsp-badge-amber {
  border-color: rgba(251,191,36,0.9);
  background: radial-gradient(circle at top left,#451a03,#111827);
  color:#fcd34d;
}
.vsp-badge-green {
  border-color: rgba(74,222,128,0.9);
  background: radial-gradient(circle at top left,#022c22,#020617);
  color:#bbf7d0;
}
.vsp-badge-blue {
  border-color: rgba(56,189,248,0.9);
  background: radial-gradient(circle at top left,#082f49,#020617);
  color:#e0f2fe;
}
.vsp-badge-purple {
  border-color: rgba(168,85,247,0.9);
  background: radial-gradient(circle at top left,#3b0764,#020617);
  color:#f5d0fe;
}

/* Severity text helpers (nếu cần dùng trong bảng) */
.vsp-sev-critical { color:#fecaca; }
.vsp-sev-high     { color:#fed7aa; }
.vsp-sev-medium   { color:#fef3c7; }
.vsp-sev-low      { color:#bbf7d0; }
.vsp-sev-info     { color:#bae6fd; }
.vsp-sev-trace    { color:#e9d5ff; }

/* CI Gate – Latest Run floating card polish */
#vsp-ci-gate-global-card {
  border-radius: 18px;
  background: radial-gradient(circle at top left,#111827,#020617);
  border:1px solid rgba(148,163,184,0.4);
}
#vsp-ci-gate-global-card .vsp-table-card-header {
  padding-bottom:4px;
}
#vsp-ci-gate-sev-chips span {
  background: rgba(15,23,42,0.8);
  border-radius:999px;
  border:1px solid rgba(55,65,81,0.8);
}

CSS

echo "$LOG Appended severity / gate colors to $CSS"
