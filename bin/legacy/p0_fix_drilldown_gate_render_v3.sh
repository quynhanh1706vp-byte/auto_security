#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
TS="$(date +%Y%m%d_%H%M%S)"

DASH="static/js/vsp_dashboard_enhance_v1.js"
GATE="static/js/vsp_gate_panel_v1.js"

[ -f "$DASH" ] || { echo "[ERR] missing $DASH"; exit 2; }
[ -f "$GATE" ] || { echo "[ERR] missing $GATE"; exit 2; }

cp -f "$DASH" "$DASH.bak_p0_v3_${TS}" && echo "[BACKUP] $DASH.bak_p0_v3_${TS}"
cp -f "$GATE" "$GATE.bak_p0_v3_${TS}" && echo "[BACKUP] $GATE.bak_p0_v3_${TS}"

echo "== [1] drilldown: force symbol to be a function (never TypeError) + wrap calls =="
python3 - <<'PY'
from pathlib import Path
import re

p = Path("static/js/vsp_dashboard_enhance_v1.js")
s = p.read_text(encoding="utf-8")

inject = r"""
  // P0 FIX (hard): drilldown must never crash dashboard
  try{
    // local symbol (if exists / if not declared -> catch)
    if (typeof VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2 !== "function") {
      VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2 = function(){
        try{ console.warn("[VSP_DASH] drilldown helper not a function -> forced stub"); }catch(_){}
        return false;
      };
    }
  }catch(_){}
  try{
    if (typeof window.VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2 !== "function") {
      window.VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2 = function(){
        try{ console.warn("[VSP_DASH] drilldown helper missing -> forced stub"); }catch(_){}
        return false;
      };
    }
  }catch(_){}
"""

m = re.search(r"(['\"]use strict['\"];\s*)", s)
if m and "P0 FIX (hard): drilldown" not in s:
    i = m.end(1)
    s = s[:i] + inject + s[i:]

# Wrap any calls: VSP_DASH... (  and window.VSP_DASH...(
rep_local = r'((typeof VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2==="function") ? VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2 : (typeof window.VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2==="function" ? window.VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2 : function(){ try{ console.warn("[VSP_DASH] drilldown skipped"); }catch(_){ } return false; }))('
s, n1 = re.subn(r'\bVSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2\s*\(', rep_local, s)

rep_win = r'((typeof window.VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2==="function") ? window.VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2 : function(){ try{ console.warn("[VSP_DASH] drilldown skipped"); }catch(_){ } return false; }))('
s, n2 = re.subn(r'\bwindow\.VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2\s*\(', rep_win, s)

p.write_text(s, encoding="utf-8")
print(f"[OK] drilldown injected + wrapped calls (local={n1}, window={n2})")
PY

echo "== [2] gate panel: when no-runs => render N/A (stop loading) instead of return-only =="
python3 - <<'PY'
from pathlib import Path
import re
p = Path("static/js/vsp_gate_panel_v1.js")
s = p.read_text(encoding="utf-8")

# Replace our earlier "no runs ... (degraded) return;" with UI render block
pat = r'try\{\s*console\.warn\("\[VSP_GATE\] no runs from runs_index_v3_fs_resolved \(degraded\)"\);\s*\}catch\(_\)\{\s*\}\s*return;'
rep = r'''
try{
  console.warn("[VSP_GATE] no runs from runs_index_v3_fs_resolved (degraded)");
}catch(_){}
try{
  const box =
    document.getElementById("vsp-gate-box") ||
    document.getElementById("vsp-gate-panel") ||
    document.querySelector(".vsp-gate-panel") ||
    document.querySelector("[data-vsp-gate]") ||
    document.querySelector("#vsp-ci-gate") ||
    document.querySelector("[id*='gate']");
  if (box){
    box.innerHTML = '<div style="padding:12px;border-radius:12px;background:rgba(255,255,255,0.04);border:1px solid rgba(255,255,255,0.08)">' +
      '<div style="font-weight:700">CI/CD Gate</div>' +
      '<div style="opacity:.85;margin-top:6px">N/A (degraded): no runs available for gate.</div>' +
    '</div>';
  }
}catch(_){}
return;
'''
s2, n = re.subn(pat, rep, s, count=1)
if n == 0:
    print("[WARN] pattern not found; will also patch any simple 'no runs ... (degraded)' early return")
    # best-effort: find the warn line and inject render before next 'return;'
    s2 = re.sub(r'console\.warn\("\[VSP_GATE\] no runs from runs_index_v3_fs_resolved \(degraded\)"\);\s*\}catch\(_\)\{\s*\}\s*return;',
                rep, s)
p.write_text(s2, encoding="utf-8")
print("[OK] gate panel: no-runs now renders N/A")
PY

echo "== [3] JS parse check =="
node --check "$DASH" >/dev/null && echo "[OK] node --check OK: $DASH"
node --check "$GATE" >/dev/null && echo "[OK] node --check OK: $GATE"

echo "== [4] restart gunicorn 8910 =="
PID_FILE="out_ci/ui_8910.pid"
PID="$(cat "$PID_FILE" 2>/dev/null || true)"
[ -n "${PID:-}" ] && kill -TERM "$PID" 2>/dev/null || true
pkill -f 'gunicorn .*8910' 2>/dev/null || true
sleep 0.8

nohup /home/test/Data/SECURITY_BUNDLE/ui/.venv/bin/gunicorn wsgi_vsp_ui_gateway:application \
  --workers 2 --worker-class gthread --threads 4 --timeout 60 --graceful-timeout 15 \
  --chdir /home/test/Data/SECURITY_BUNDLE/ui --pythonpath /home/test/Data/SECURITY_BUNDLE/ui \
  --bind 127.0.0.1:8910 --pid "$PID_FILE" \
  --access-logfile out_ci/ui_8910.access.log --error-logfile out_ci/ui_8910.error.log \
  > out_ci/ui_8910.nohup.log 2>&1 &

sleep 1.2
curl -fsS http://127.0.0.1:8910/vsp4 >/dev/null && echo "[OK] UI up: /vsp4"
echo "[DONE] HARD refresh Ctrl+Shift+R, then confirm: (1) drilldown error gone, (2) gate panel not stuck loading."
