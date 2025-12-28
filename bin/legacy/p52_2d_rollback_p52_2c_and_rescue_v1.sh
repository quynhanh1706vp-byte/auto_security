#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
OUT="out_ci"
RELROOT="$OUT/releases"
TS="$(date +%Y%m%d_%H%M%S)"
EVID="$OUT/p52_2d_${TS}"
mkdir -p "$EVID"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need date; need ls; need head; need tail; need grep; need awk; need sed; need python3; need curl; need sudo; need cp; need mkdir
command -v systemctl >/dev/null 2>&1 || { echo "[ERR] systemctl missing"; exit 2; }
command -v ss >/dev/null 2>&1 || true

log(){ echo "[$(date +%H:%M:%S)] $*"; }

latest_release="$(ls -1dt "$RELROOT"/RELEASE_UI_* 2>/dev/null | head -n 1 || true)"
[ -n "${latest_release:-}" ] && [ -d "$latest_release" ] || { echo "[ERR] no release in $RELROOT"; exit 2; }
ATT="$latest_release/evidence/p52_2d_${TS}"
mkdir -p "$ATT"
log "[OK] latest_release=$latest_release"

W="wsgi_vsp_ui_gateway.py"
[ -f "$W" ] || { echo "[ERR] missing $W"; exit 2; }

diag(){
  local tag="$1"
  {
    echo "== $tag =="
    echo "TIME=$(date +'%Y-%m-%d %H:%M:%S %z')"
    echo "BASE=$BASE"
    echo "SVC=$SVC"
    echo
    echo "## systemctl is-active"
    systemctl is-active "$SVC" || true
    echo
    echo "## systemctl status -n 120"
    systemctl status "$SVC" --no-pager -n 120 || true
    echo
    echo "## ss :8910"
    ss -ltnp 2>/dev/null | grep -E '(:8910\b)' || true
    echo
    echo "## journalctl -u (last 220)"
    journalctl -u "$SVC" -n 220 --no-pager || true
  } > "$EVID/${tag}.txt" 2>&1
}

log "== [P52.2d/0] pre diagnostics =="
diag "pre"

log "== [P52.2d/1] rollback to latest bak_p52_2c_* (known good before wrap) =="
bak="$(ls -1t "$W".bak_p52_2c_* 2>/dev/null | head -n 1 || true)"
if [ -z "${bak:-}" ]; then
  echo "[ERR] no $W.bak_p52_2c_* found to rollback" | tee "$EVID/rollback.txt" >&2
  exit 2
fi
cp -f "$W" "$EVID/${W}.before_rollback_${TS}" 2>/dev/null || true
cp -f "$bak" "$W"
echo "[OK] rolled back to $bak" | tee "$EVID/rollback.txt" >/dev/null

log "== [P52.2d/2] py_compile gate (must pass) =="
python3 -m py_compile "$W" > "$EVID/py_compile_wsgigw.txt" 2>&1 || {
  echo "[ERR] py_compile still fails after rollback. See $EVID/py_compile_wsgigw.txt" >&2
  exit 2
}

log "== [P52.2d/3] restart service =="
sudo systemctl daemon-reload >/dev/null 2>&1 || true
sudo systemctl reset-failed "$SVC" >/dev/null 2>&1 || true
sudo systemctl restart "$SVC" || true

log "== [P52.2d/4] warm + health STRICT 5/5 =="
# warm (allow longer)
curl -sS -o /dev/null --connect-timeout 2 --max-time 10 "$BASE/vsp5" || true

ok=1
: > "$EVID/health_5x.txt"
for i in 1 2 3 4 5; do
  code="$(curl -sS -o /dev/null -w '%{http_code}' --connect-timeout 2 --max-time 6 "$BASE/vsp5" || true)"
  echo "try#$i http_code=$code" | tee -a "$EVID/health_5x.txt" >/dev/null
  if [ "$code" != "200" ]; then ok=0; fi
  sleep 0.5
done
curl -sS -D- -o /dev/null --connect-timeout 2 --max-time 6 "$BASE/vsp5" > "$EVID/vsp5_headers.txt" 2>&1 || true

log "== [P52.2d/5] post diagnostics =="
diag "post"

log "== [P52.2d/6] attach evidence =="
cp -f "$EVID/"* "$ATT/" 2>/dev/null || true

log "== [P52.2d/7] verdict =="
VER="$OUT/p52_2d_verdict_${TS}.json"
python3 - <<PY
import json, time
j={"ok": bool(int("$ok")),
   "ts": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
   "p52_2d": {"service":"$SVC","base":"$BASE",
              "rollback_from":"$bak",
              "latest_release":"$latest_release",
              "evidence_dir":"$EVID","attached_dir":"$ATT"}}
print(json.dumps(j, indent=2))
open("$VER","w").write(json.dumps(j, indent=2))
PY
cp -f "$VER" "$ATT/" 2>/dev/null || true

if [ "$ok" -eq 1 ]; then
  log "[PASS] /vsp5 stable 5/5 after rollback"
  log "[DONE] P52.2d PASS"
else
  log "[FAIL] /vsp5 not stable even after rollback"
  log "[DONE] P52.2d FAIL"
  exit 2
fi
