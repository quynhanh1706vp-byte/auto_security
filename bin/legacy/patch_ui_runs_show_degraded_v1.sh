#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

JS="static/js/vsp_runs_tab_simple_v2.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "$JS.bak_degraded_${TS}"
echo "[BACKUP] $JS.bak_degraded_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("static/js/vsp_runs_tab_simple_v2.js")
txt = p.read_text(encoding="utf-8", errors="ignore")
if "VSP_UI_DEGRADED_PANEL_V1" in txt:
    print("[OK] already patched")
    raise SystemExit(0)

panel = r'''
// === VSP_UI_DEGRADED_PANEL_V1 ===
function vspRenderDegradedToolsPanel(degraded) {
  try {
    if (!degraded || (typeof degraded !== 'object')) return '';
    var keys = Object.keys(degraded);
    if (!keys.length) return '';
    var rows = keys.map(function(k){
      var v = degraded[k] || {};
      var reason = (v.reason || v.status || v.error || 'degraded');
      var tsec = (v.timeout_sec || v.timeout || '');
      return '<tr>' +
        '<td style="padding:6px 8px;border-bottom:1px solid rgba(255,255,255,.06)">' + String(k) + '</td>' +
        '<td style="padding:6px 8px;border-bottom:1px solid rgba(255,255,255,.06)">' + String(reason) + '</td>' +
        '<td style="padding:6px 8px;border-bottom:1px solid rgba(255,255,255,.06)">' + String(tsec) + '</td>' +
      '</tr>';
    }).join('');
    return '' +
      '<div style="margin:10px 0;padding:12px;border:1px solid rgba(255,255,255,.08);border-radius:14px;background:rgba(255,255,255,.03)">' +
        '<div style="font-weight:700;margin-bottom:8px">Degraded tools</div>' +
        '<table style="width:100%;border-collapse:collapse;font-size:13px">' +
          '<thead><tr>' +
            '<th style="text-align:left;padding:6px 8px;border-bottom:1px solid rgba(255,255,255,.10)">Tool</th>' +
            '<th style="text-align:left;padding:6px 8px;border-bottom:1px solid rgba(255,255,255,.10)">Reason</th>' +
            '<th style="text-align:left;padding:6px 8px;border-bottom:1px solid rgba(255,255,255,.10)">Timeout (sec)</th>' +
          '</tr></thead>' +
          '<tbody>' + rows + '</tbody>' +
        '</table>' +
      '</div>';
  } catch (e) { return ''; }
}
// === END VSP_UI_DEGRADED_PANEL_V1 ===
'''

# Insert panel near top
txt = panel + "\n" + txt

# Heuristic: when rendering run detail/status, inject panel if we can find a place referencing run_status_v1 payload
# We search for 'run_status_v1' and insert after the first JSON parse handling.
idx = txt.find("run_status_v1")
if idx == -1:
    print("[WARN] cannot find run_status_v1 usage; panel added but not wired.")
else:
    # Try to find a variable named 'data' or 'status' after fetch.
    # Insert a small hook: html += vspRenderDegradedToolsPanel(data.degraded_tools)
    hook = r'''
    try {
      if (data && data.degraded_tools) {
        html += vspRenderDegradedToolsPanel(data.degraded_tools);
      }
      if (data && data.finish_reason) {
        html += '<div style="opacity:.85;font-size:12px;margin:6px 0 10px 0">finish_reason: <b>' + String(data.finish_reason) + '</b></div>';
      }
    } catch(e) {}
'''
    # Find first occurrence of "var html" after idx
    m = re.search(r'var\s+html\s*=\s*', txt[idx:])
    if m:
        ins = idx + m.start()
        # place hook shortly after html init (next newline)
        nl = txt.find("\n", ins)
        if nl != -1:
            txt = txt[:nl+1] + hook + txt[nl+1:]
            print("[OK] wired degraded panel into run detail render (best-effort).")
    else:
        print("[WARN] cannot find 'var html=' near run_status_v1; panel not wired.")

p.write_text(txt, encoding="utf-8")
print("[OK] patched", p)
PY
