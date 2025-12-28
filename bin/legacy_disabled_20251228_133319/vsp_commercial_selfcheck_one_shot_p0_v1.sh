#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

TS="$(date +%Y%m%d_%H%M%S)"
OUT="out_ci"
mkdir -p "$OUT"
RPT="$OUT/commercial_selfcheck_${TS}.txt"
JSON="$OUT/commercial_selfcheck_${TS}.json"

UI="http://127.0.0.1:8910"
PAGE="/vsp4"
API1="/api/vsp/run_status_v1"
API2="/api/vsp/run_status_v2"

exec > >(tee "$RPT") 2>&1
echo "== VSP COMMERCIAL SELFCHECK P0 =="
echo "[TS] $TS"
echo "[PWD] $(pwd)"
echo

echo "== (A) Service/Port =="
ss -lntp | grep ':8910' || echo "[WARN] 8910 not listening"
ps -ef | grep -E 'gunicorn .*8910|wsgi_vsp_ui_gateway' | grep -v grep || true
echo

echo "== (B) Python compile sanity =="
/home/test/Data/SECURITY_BUNDLE/ui/.venv/bin/python -m py_compile vsp_demo_app.py wsgi_vsp_ui_gateway.py && echo "[OK] py_compile core OK" || echo "[ERR] py_compile core FAIL"
echo

echo "== (C) Boot/Error logs tail =="
tail -n 120 out_ci/ui_8910.boot.log 2>/dev/null || true
echo "----"
tail -n 120 out_ci/ui_8910.error.log 2>/dev/null || true
echo

echo "== (D) HTTP checks (HTML + APIs) =="
echo "[GET] $UI$PAGE"
curl -sS -D - "$UI$PAGE" -o "$OUT/page_${TS}.html" | head -n 30 || true
echo
echo "[GET] $UI$API1"
curl -sS -D - "$UI$API1" -o "$OUT/api1_${TS}.json" | head -n 30 || true
echo
echo "[GET] $UI$API2"
curl -sS -D - "$UI$API2" -o "$OUT/api2_${TS}.json" | head -n 30 || true
echo

echo "== (E) What scripts are actually served? (parse HTML) =="
python3 - <<PY
import re, json, pathlib
html = pathlib.Path("$OUT/page_${TS}.html").read_text(encoding="utf-8", errors="ignore")
srcs = re.findall(r'<script[^>]+src=["\\\']([^"\\\']+)["\\\']', html, flags=re.I)
print("[SCRIPTS] count=", len(srcs))
for s in srcs[:200]:
    print(" -", s)
# dump json summary
data = {
  "ts": "$TS",
  "scripts": srcs,
  "has_drilldown_stub": any("drilldown" in s and "stub" in s for s in srcs),
  "has_drilldown_impl": any("drilldown" in s and "impl" in s for s in srcs),
  "has_loader": any("vsp_ui_loader_route" in s for s in srcs),
}
pathlib.Path("$JSON").write_text(json.dumps(data, indent=2), encoding="utf-8")
print("[OK] wrote", "$JSON")
PY
echo

echo "== (F) JS syntax check for key files (node --check) =="
KEY_JS=(
  static/js/vsp_ui_loader_route_v1.js
  static/js/vsp_dashboard_enhance_v1.js
  static/js/vsp_dashboard_charts_pretty_v3.js
  static/js/vsp_tabs_hash_router_v1.js
  static/js/vsp_runs_tab_resolved_v1.js
  static/js/vsp_rule_overrides_tab_v1.js
  static/js/vsp_drilldown_stub_safe_v1.js
  static/js/vsp_drilldown_artifacts_impl_commercial_v1.js
)
for f in "${KEY_JS[@]}"; do
  [ -f "$f" ] || { echo "[MISS] $f"; continue; }
  node --check "$f" >/dev/null && echo "[OK] node --check $f" || echo "[ERR] node --check FAIL $f"
done
echo

echo "== (G) Grep: drilldown callsite correctness =="
echo "[1] bare calls that can be shadowed (BAD):"
grep -RIn --line-number -E '(?<![\w\.])VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2\s*\(' static/js/vsp_dashboard_enhance_v1.js static/js/vsp_runs_tab_resolved_v1.js 2>/dev/null || echo "[OK] none"
echo
echo "[2] window calls (GOOD):"
grep -RIn --line-number -E 'window\.VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2\s*\(' static/js/vsp_dashboard_enhance_v1.js static/js/vsp_runs_tab_resolved_v1.js 2>/dev/null || echo "[WARN] none"
echo

echo "== (H) Grep: drilldown stub presence in repo (templates/static) =="
grep -RIn "vsp_drilldown_stub_safe_v1.js" templates static/js 2>/dev/null || echo "[OK] no direct refs"
echo

echo "== (I) Leak text markers in templates (should be NONE) =="
grep -RIn -E "__VSP_DD_|DD_SAFE|try\\{if \\(typeof h|function __VSP_DD" templates 2>/dev/null || echo "[OK] no leak markers"
echo

echo "== (J) jq quick view (if JSON is JSON) =="
if command -v jq >/dev/null 2>&1; then
  for jf in "$OUT/api1_${TS}.json" "$OUT/api2_${TS}.json"; do
    [ -s "$jf" ] || continue
    echo "[JQ] $jf"
    jq -r '[
      ("keys=" + ((keys|length|tostring) // "null")),
      ("overall=" + ((.overall_pass|tostring) // (.overall|tostring) // "null")),
      ("rid=" + ((.rid|tostring) // "null"))
    ] | .[]' "$jf" 2>/dev/null || echo "[WARN] $jf not JSON"
  done
else
  echo "[WARN] jq not installed"
fi
echo

echo "== (K) Recent modified frontend files (helps find clobbers) =="
ls -lt static/js | head -n 30 || true
echo

echo "== DONE =="
echo "[REPORT] $RPT"
echo "[JSON]   $JSON"
