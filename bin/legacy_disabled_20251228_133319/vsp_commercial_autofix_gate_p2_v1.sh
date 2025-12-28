#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

BASE="http://127.0.0.1:8910"
TS="$(date +%Y%m%d_%H%M%S)"
OUT="out_ci/COMMERCIAL_${TS}"
mkdir -p "$OUT"

log(){ echo "$*" | tee -a "$OUT/gate.log"; }

log "== VSP COMMERCIAL AUTO-FIX + GATE P2 ==" 
log "[BASE]=$BASE"
log "[TS]=$TS"

# ---------- helper: quick http code ----------
code(){ curl -sS -m 4 -o /dev/null -w '%{http_code}' "$1" 2>/dev/null || echo 000; }

# ---------- helper: restart ----------
restart(){ bash /home/test/Data/SECURITY_BUNDLE/ui/bin/restart_ui_8910_hardreset_p0_v1.sh >/dev/null; }

# ---------- (1) ensure BE commercial APIs exist ----------
PYF="vsp_demo_app.py"
if ! grep -q "/api/vsp/dashboard_commercial_v1" "$PYF"; then
  log "[FIX] missing dashboard_commercial_v1 → run patch_api_dashboard_and_findings_commercial_p0_v1.sh"
  bash /home/test/Data/SECURITY_BUNDLE/ui/bin/patch_api_dashboard_and_findings_commercial_p0_v1.sh >/dev/null || true
fi
if ! grep -q "/api/vsp/rule_overrides_v1" "$PYF"; then
  log "[FIX] missing rule_overrides_v1 → patch now"
  bash /home/test/Data/SECURITY_BUNDLE/ui/bin/patch_rule_overrides_api_p1_v1.sh >/dev/null || true
fi

# ---------- (2) ensure FE uses commercial dashboard (safe needle replace) ----------
JSF="static/js/vsp_bundle_commercial_v2.js"
if ! grep -q "VSP_DASH_USE_COMMERCIAL_P1_SAFE_V1" "$JSF"; then
  log "[FIX] FE not using dashboard_commercial_v1 → patch safely"
  python3 - <<'PY'
from pathlib import Path
p=Path("static/js/vsp_bundle_commercial_v2.js")
s=p.read_text(encoding="utf-8", errors="replace")
needle="STATE.dashboard = await fetchJson('/api/vsp/dashboard_v3?ts=' + Date.now());"
if needle in s and "VSP_DASH_USE_COMMERCIAL_P1_SAFE_V1" not in s:
    rep="""// VSP_DASH_USE_COMMERCIAL_P1_SAFE_V1
      try{
        STATE.dashboard = await fetchJson('/api/vsp/dashboard_commercial_v1?ts=' + Date.now());
      }catch(_e1){
        STATE.dashboard = await fetchJson('/api/vsp/dashboard_v3?ts=' + Date.now());
      }"""
    s=s.replace(needle, rep, 1)
    p.write_text(s, encoding="utf-8")
    print("[OK] patched FE dashboard commercial")
else:
    print("[OK] needle missing or already patched")
PY
  node --check "$JSF" >/dev/null
  restart
fi

# ---------- (3) snapshot: latest rid/run_dir ----------
log "== SNAP latest_rid_v1 =="
curl -sS "$BASE/api/vsp/latest_rid_v1?ts=$TS" | tee "$OUT/latest_rid_v1.json" >/dev/null || true
RD="$(cat "$OUT/latest_rid_v1.json" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("ci_run_dir",""))' 2>/dev/null || true)"
log "[RUN_DIR]=$RD"

# ---------- (4) endpoint health ----------
log "== HEALTH endpoints =="
URLS=(
  "$BASE/vsp4"
  "$BASE/static/js/vsp_bundle_commercial_v2.js"
  "$BASE/api/vsp/latest_rid_v1"
  "$BASE/api/vsp/dashboard_commercial_v2"
  "$BASE/api/vsp/dashboard_commercial_v1"
  "$BASE/api/vsp/findings_latest_v1?limit=3"
  "$BASE/api/vsp/runs_index_v3_fs_resolved?limit=1"
  "$BASE/api/vsp/rule_overrides_v1"
)
fails=0
for u in "${URLS[@]}"; do
  c="$(code "$u")"
  log "[HTTP] $c $u"
  [ "$c" = "200" ] || fails=$((fails+1))
done
log "[HEALTH_FAILS]=$fails"

# ---------- (5) verify SHA + export TGZ header ----------
if [ -n "${RD:-}" ]; then
  QRD="$(python3 -c 'import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1]))' "$RD")"
  log "== VERIFY SHA =="
  curl -sS "$BASE/api/vsp/verify_report_sha_v1?run_dir=$QRD&ts=$TS" | tee "$OUT/verify_sha.json" >/dev/null || true
  log "== EXPORT TGZ (HEAD) =="
  curl -sS -I "$BASE/api/vsp/export_report_tgz_v1?run_dir=$QRD&ts=$TS" | tee "$OUT/export_head.txt" >/dev/null || true
fi

# ---------- (6) stability: 10 minutes ----------
log "== STABILITY 10min (no non-200) =="
bash /home/test/Data/SECURITY_BUNDLE/ui/bin/vsp_ui_stability_smoke_p0_v1.sh 600 | tee "$OUT/stability_10min.log" >/dev/null || true

# ---------- (7) log scan ----------
log "== LOG SCAN =="
ERR="out_ci/ui_8910.error.log"
ACC="out_ci/ui_8910.access.log"
cp -f "$ERR" "$OUT/ui_8910.error.log" 2>/dev/null || true
cp -f "$ACC" "$OUT/ui_8910.access.log" 2>/dev/null || true
grep -nE "Traceback|SyntaxError|ReferenceError|TypeError|HTTP_500| 500 " "$OUT/ui_8910.error.log" | head -n 120 > "$OUT/error_scan.txt" || true
log "[ERROR_SCAN_LINES] $(wc -l < "$OUT/error_scan.txt" 2>/dev/null || echo 0)"

# ---------- (8) degrade reasons snapshot ----------
log "== DASH snapshot (commercial) =="
curl -sS "$BASE/api/vsp/dashboard_commercial_v2?ts=$TS" | tee "$OUT/dashboard_commercial_v2.json" || true
curl -sS "$BASE/api/vsp/dashboard_commercial_v1?ts=$TS" | tee "$OUT/dashboard_commercial_v1.json" >/dev/null || true

# ---------- (9) pack evidence ----------
log "== PACK evidence =="
tgz="out_ci/COMMERCIAL_${TS}.tgz"
tar -czf "$tgz" -C out_ci "COMMERCIAL_${TS}"
( cd out_ci && sha256sum "COMMERCIAL_${TS}.tgz" > "COMMERCIAL_${TS}.SHA256SUMS.txt" )
log "[OK] $tgz"
log "[OK] out_ci/COMMERCIAL_${TS}.SHA256SUMS.txt"
log "[NEXT] Open UI: $BASE/vsp4  (Ctrl+Shift+R)."
