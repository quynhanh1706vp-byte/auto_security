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
BOOT="$OUT/ui_8910.boot.log"
ERR="$OUT/ui_8910.error.log"

exec > >(tee "$RPT") 2>&1

echo "== VSP COMMERCIAL SELFCHECK P0 (v2) =="
echo "[TS] $TS"
echo "[PWD] $(pwd)"
echo

echo "== (0) STOP 8910 clean =="
PID="$(cat $OUT/ui_8910.pid 2>/dev/null || true)"
[ -n "${PID:-}" ] && kill -TERM "$PID" 2>/dev/null || true
pkill -f 'gunicorn .*8910' 2>/dev/null || true
sleep 0.6
fuser -k 8910/tcp 2>/dev/null || true
sleep 0.4

echo "== (1) py_compile core =="
/home/test/Data/SECURITY_BUNDLE/ui/.venv/bin/python -m py_compile vsp_demo_app.py wsgi_vsp_ui_gateway.py \
  && echo "[OK] py_compile core OK" || { echo "[ERR] py_compile core FAIL"; exit 2; }
echo

echo "== (2) START 8910 (manual gunicorn) =="
nohup /home/test/Data/SECURITY_BUNDLE/ui/.venv/bin/gunicorn wsgi_vsp_ui_gateway:application \
  --workers 2 --worker-class gthread --threads 4 \
  --timeout 60 --graceful-timeout 15 \
  --chdir /home/test/Data/SECURITY_BUNDLE/ui --pythonpath /home/test/Data/SECURITY_BUNDLE/ui \
  --bind 127.0.0.1:8910 --pid $OUT/ui_8910.pid \
  --access-logfile $OUT/ui_8910.access.log --error-logfile "$ERR" \
  >"$BOOT" 2>&1 &
sleep 0.4

echo "== (3) WAIT HTTP READY (max 6s) =="
ok=0
for i in 1 2 3 4 5 6; do
  if curl -fsS "$UI$PAGE" >/dev/null 2>&1; then ok=1; break; fi
  sleep 1
done
if [ "$ok" != "1" ]; then
  echo "[FAIL] UI not responding: $UI$PAGE"
  echo "---- boot log tail ----"; tail -n 200 "$BOOT" 2>/dev/null || true
  echo "---- error log tail ----"; tail -n 200 "$ERR" 2>/dev/null || true
  echo "---- ss -lntp ----"; ss -lntp | grep ':8910' || true
  exit 3
fi
echo "[OK] HTTP ready"
echo

echo "== (4) FETCH HTML + APIs =="
curl -fsS "$UI$PAGE" -o "$OUT/page_${TS}.html"
curl -fsS "$UI$API1" -o "$OUT/api1_${TS}.json" || true
curl -fsS "$UI$API2" -o "$OUT/api2_${TS}.json" || true
echo "[OK] fetched: page_${TS}.html api1_${TS}.json api2_${TS}.json"
echo

echo "== (5) PARSE scripts from HTML (regex fixed) =="
python3 - <<PY
import re, json, pathlib
html = pathlib.Path("$OUT/page_${TS}.html").read_text(encoding="utf-8", errors="ignore")
# use double-quoted python string to avoid quote collisions
srcs = re.findall(r"<script[^>]+src=[\"']([^\"']+)[\"']", html, flags=re.I)
has_stub = any("vsp_drilldown_stub_safe_v1.js" in s for s in srcs)
has_impl = any("vsp_drilldown_artifacts_impl_commercial_v1.js" in s for s in srcs)
has_loader = any("vsp_ui_loader_route" in s for s in srcs)

print("[SCRIPTS] count=", len(srcs))
for s in srcs[:250]:
    print(" -", s)

data = {
  "ts": "$TS",
  "scripts_count": len(srcs),
  "has_stub": has_stub,
  "has_impl": has_impl,
  "has_loader": has_loader,
  "scripts": srcs,
}
pathlib.Path("$JSON").write_text(json.dumps(data, indent=2), encoding="utf-8")
print("[OK] wrote", "$JSON")
PY
echo

echo "== (6) node --check key JS =="
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
  node --check "$f" >/dev/null && echo "[OK] $f" || echo "[ERR] node --check FAIL $f"
done
echo

echo "== (7) drilldown callsite audit (BAD vs GOOD) =="
echo "[BAD] bare calls:"
grep -RIn -E '(?<![\w\.])VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2\s*\(' \
  static/js/vsp_dashboard_enhance_v1.js static/js/vsp_runs_tab_resolved_v1.js 2>/dev/null || echo "[OK] none"
echo
echo "[GOOD] window calls:"
grep -RIn -E 'window\.VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2\s*\(' \
  static/js/vsp_dashboard_enhance_v1.js static/js/vsp_runs_tab_resolved_v1.js 2>/dev/null || echo "[WARN] none"
echo

echo "== (8) leak markers in templates (should be NONE) =="
grep -RIn -E "__VSP_DD_|DD_SAFE|try\{if \(typeof h" templates 2>/dev/null || echo "[OK] no leak markers"
echo

echo "== DONE =="
echo "[REPORT] $RPT"
echo "[JSON]   $JSON"
