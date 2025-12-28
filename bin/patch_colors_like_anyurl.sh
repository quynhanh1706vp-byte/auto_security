#!/usr/bin/env bash
set -euo pipefail

TPL="templates/index.html"
echo "[i] TPL = $TPL"

[ -f "$TPL" ] || { echo "[ERR] Không tìm thấy $TPL"; exit 1; }

python3 - "$TPL" <<'PY'
import sys

path = sys.argv[1]
html = open(path, "r", encoding="utf-8").read()

start = html.find("<style>")
end   = html.find("</style>", start)
if start == -1 or end == -1:
    print("[ERR] Không tìm thấy block <style> trong index.html")
    sys.exit(1)
end += len("</style>")

new_style = """    <style>
      /* Palette & layout giống ANY-URL 4-Layer */
      body {
        margin: 0;
        font-family: system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
        color: #f9fbff;
        background: radial-gradient(circle at top, #0b1120 0, #020617 55%, #00010a 100%);
      }
      .sb-layout { display: flex; min-height: 100vh; }
      .sb-sidebar {
        width: 260px;
        padding: 20px 18px;
        background: linear-gradient(180deg, #020617, #020617 40%, #020314 100%);
        box-shadow: 0 0 40px rgba(0,0,0,0.7);
      }
      .sb-brand { display:flex;align-items:center;gap:10px;margin-bottom:24px; }
      .sb-brand-ring {
        width: 32px; height: 32px; border-radius:999px;
        background: conic-gradient(from 210deg,#22c55e,#38bdf8,#a855f7,#f97316,#22c55e);
        padding:2px;
      }
      .sb-brand-ring-inner {
        width:100%;height:100%;border-radius:999px;background:#020617;
        display:flex;align-items:center;justify-content:center;font-size:11px;
      }
      .sb-brand-title {
        font-size:14px;text-transform:uppercase;letter-spacing:.15em;
      }
      .sb-brand-sub { font-size:11px;opacity:.75; }

      .sb-nav { margin-top:20px; }
      .sb-nav-item {
        display:flex;align-items:center;gap:8px;
        padding:8px 10px;border-radius:999px;font-size:13px;
        margin-bottom:6px;opacity:.85;
        text-decoration:none;color:inherit;
        transition:background .18s ease, opacity .18s ease, transform .12s ease;
      }
      .sb-nav-item:hover {
        background:linear-gradient(90deg,#1d4ed8,#7c3aed);
        opacity:1;
        transform:translateX(2px);
      }
      .sb-nav-item.active {
        background:linear-gradient(90deg,#4f46e5,#ec4899);
        opacity:1;
      }
      .sb-nav-dot { width:6px;height:6px;border-radius:999px;background:#fff; }

      .sb-main {
        flex:1;padding:22px 28px 32px;
        overflow-x:hidden;overflow-y:auto;
      }
      .sb-main-header {
        display:flex;justify-content:space-between;align-items:center;
        margin-bottom:20px;
      }
      .sb-main-title {
        font-size:18px;font-weight:600;
        letter-spacing:.09em;text-transform:uppercase;
      }
      .sb-profile-badges { display:flex;gap:8px;font-size:11px; }
      .sb-pill {
        border-radius:999px;padding:4px 10px;
        background:rgba(15,23,42,0.9);
        border:1px solid rgba(148,163,184,0.4);
      }

      .sb-target-row {
        display:grid;
        grid-template-columns:minmax(0,2fr) minmax(0,2fr) auto;
        gap:10px;margin-bottom:16px;align-items:center;
      }
      .sb-input-shell {
        padding:7px 12px;border-radius:999px;
        border:1px solid rgba(30,64,175,0.9);
        font-size:12px;opacity:.95;
        background:#020617;
        box-shadow:0 0 0 1px rgba(15,23,42,0.8);
      }
      .sb-input-label {
        font-size:11px;text-transform:uppercase;
        letter-spacing:.12em;opacity:.7;margin-bottom:3px;
      }
      .sb-target-group { display:flex;flex-direction:column;gap:2px; }
      .sb-button-primary {
        border-radius:999px;padding:8px 18px;border:none;cursor:pointer;
        font-size:13px;
        background:linear-gradient(135deg,#22c55e,#16a3ff);
        color:#020617;
        box-shadow:0 12px 30px rgba(15,23,42,0.9);
      }

      .sb-grid-main {
        display:grid;
        grid-template-columns:minmax(0,3.2fr) minmax(0,1.6fr);
        gap:22px;
      }
      .sb-card {
        background:radial-gradient(circle at top left,#020617,#020617 40%,#020314 100%);
        border-radius:22px;
        box-shadow:0 0 0 1px rgba(15,23,42,0.9);
        padding:16px 18px 14px;
      }
      .sb-card-header {
        display:flex;justify-content:space-between;align-items:baseline;
        margin-bottom:10px;
      }
      .sb-card-title {
        font-size:13px;text-transform:uppercase;
        letter-spacing:.12em;opacity:.78;
      }

      .sb-metric-row {
        display:grid;grid-template-columns:repeat(3,minmax(0,1fr));
        gap:12px;margin-bottom:14px;
      }
      .sb-metric {
        background:rgba(15,23,42,0.9);
        border-radius:16px;padding:10px 12px;
        box-shadow:0 0 0 1px rgba(30,64,175,0.5);
      }
      .sb-metric-label {
        font-size:11px;text-transform:uppercase;
        letter-spacing:.12em;opacity:.7;margin-bottom:3px;
      }
      .sb-metric-value { font-size:22px;font-weight:600; }
      .sb-metric-sub { font-size:11px;opacity:.8; }

      .sb-severity-wrapper { margin-top:6px; }

      .sb-bottom-grid {
        display:grid;
        grid-template-columns:minmax(0,2.2fr) minmax(0,1.5fr);
        gap:18px;margin-top:18px;
      }
      @media (max-width:1100px) {
        .sb-grid-main { grid-template-columns:minmax(0,1fr); }
        .sb-bottom-grid { grid-template-columns:minmax(0,1fr); }
      }

      .sb-table-wrapper { max-height:260px;overflow:auto; }
      .sb-table {
        width:100%;border-collapse:collapse;font-size:12px;
      }
      .sb-table th,.sb-table td {
        padding:5px 6px;
        border-bottom:1px solid rgba(31,41,55,0.9);
      }
      .sb-table th {
        font-size:11px;text-transform:uppercase;
        letter-spacing:.12em;opacity:.78;text-align:left;
      }
      .sb-table td.right { text-align:right; }
      .sb-table td.mono {
        font-family:"Fira Code","SF Mono",monospace;
        font-size:11px;
      }
      .sb-table td.small { font-size:11px; }

      .sb-sev-pill {
        display:inline-flex;align-items:center;
        padding:2px 8px;border-radius:999px;font-size:11px;
      }
      .sb-sev-pill.high {
        background:rgba(251,146,60,0.16);color:#fdba74;
      }
      .sb-sev-pill.critical {
        background:rgba(248,113,113,0.18);color:#fecaca;
      }

      .sb-section-title {
        font-size:13px;text-transform:uppercase;
        letter-spacing:.12em;opacity:.8;margin:6px 0 6px;
      }
    </style>"""

html = html[:start] + new_style + html[end:]
open(path, "w", encoding="utf-8").write(html)
print("[OK] Đã thay block <style> bằng palette giống ANY-URL.")
PY
