#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
OUT="out_ci"
RELROOT="$OUT/releases"
TS="$(date +%Y%m%d_%H%M%S)"
EVID="$OUT/p52_1g_${TS}"
mkdir -p "$EVID"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need date; need ls; need head; need tail; need grep; need awk; need sed; need python3; need curl; need sudo
command -v systemctl >/dev/null 2>&1 || { echo "[ERR] systemctl missing"; exit 2; }
command -v ss >/dev/null 2>&1 || true

log(){ echo "[$(date +%H:%M:%S)] $*"; }

latest_release="$(ls -1dt "$RELROOT"/RELEASE_UI_* 2>/dev/null | head -n 1 || true)"
[ -n "${latest_release:-}" ] && [ -d "$latest_release" ] || { echo "[ERR] no release in $RELROOT"; exit 2; }
ATT="$latest_release/evidence/p52_1g_${TS}"
mkdir -p "$ATT"
log "[OK] latest_release=$latest_release"

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
    echo "## curl /vsp5 (headers)"
    curl -sS -D- -o /dev/null --connect-timeout 2 --max-time 4 "$BASE/vsp5" || true
    echo
    echo "## journalctl -u (last 220)"
    journalctl -u "$SVC" -n 220 --no-pager || true
  } > "$EVID/${tag}.txt" 2>&1
}

log "== [P52.1g/0] pre diagnostics =="
diag "pre"

log "== [P52.1g/1] py_compile sanity (find crash fast) =="
pc="$EVID/py_compile_${TS}.txt"
set +e
python3 -m py_compile wsgi_vsp_ui_gateway.py >"$pc" 2>&1
rc1=$?
python3 -m py_compile vsp_demo_app.py >>"$pc" 2>&1
rc2=$?
set -e
echo "rc_wsgigw=$rc1 rc_demo=$rc2" | tee "$EVID/py_compile_rc.txt" >/dev/null

rollback_done=0
if [ "$rc1" -ne 0 ]; then
  log "[WARN] wsgi_vsp_ui_gateway.py compile FAIL -> rollback to latest .bak_p52_*"
  bak="$(ls -1t wsgi_vsp_ui_gateway.py.bak_p52_* 2>/dev/null | head -n 1 || true)"
  if [ -n "${bak:-}" ] && [ -f "$bak" ]; then
    cp -f "wsgi_vsp_ui_gateway.py" "$EVID/wsgi_vsp_ui_gateway.py.before_rollback_${TS}" 2>/dev/null || true
    cp -f "$bak" "wsgi_vsp_ui_gateway.py"
    echo "[OK] rolled back to $bak" | tee "$EVID/rollback_${TS}.txt" >/dev/null
    rollback_done=1
  else
    echo "[ERR] no backup found: wsgi_vsp_ui_gateway.py.bak_p52_*" | tee "$EVID/rollback_${TS}.txt" >&2
  fi
fi

log "== [P52.1g/2] restart service =="
sudo systemctl daemon-reload >/dev/null 2>&1 || true
sudo systemctl restart "$SVC" || true

log "== [P52.1g/3] wait /vsp5 200 (max 30s) =="
ok=0
for i in $(seq 1 60); do
  code="$(curl -sS -o /dev/null -w '%{http_code}' --connect-timeout 1 --max-time 2 "$BASE/vsp5" || true)"
  echo "try#$i http_code=$code" >> "$EVID/wait_${TS}.txt"
  if [ "$code" = "200" ]; then ok=1; break; fi
  sleep 0.5
done

log "== [P52.1g/4] post diagnostics =="
diag "post"

log "== [P52.1g/5] attach evidence to release =="
cp -f "$EVID/"* "$ATT/" 2>/dev/null || true

log "== [P52.1g/6] verdict json =="
VER="$OUT/p52_1g_verdict_${TS}.json"
python3 - <<PY
import json, time
j={
  "ok": bool(int("$ok")),
  "ts": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
  "p52_1g": {
    "service": "$SVC",
    "base": "$BASE",
    "latest_release": "$latest_release",
    "attached_dir": "$ATT",
    "py_compile_wsgigw_rc": int("$rc1"),
    "py_compile_demo_rc": int("$rc2"),
    "rollback_done": bool(int("$rollback_done"))
  }
}
print(json.dumps(j, indent=2))
open("$VER","w").write(json.dumps(j, indent=2))
PY
cp -f "$VER" "$ATT/" 2>/dev/null || true

if [ "$ok" -eq 1 ]; then
  log "[PASS] UI is back (HTTP 200 confirmed). Verdict: $VER"
  log "[DONE] P52.1g PASS"
else
  log "[FAIL] UI still down. Verdict: $VER"
  log "[DONE] P52.1g FAIL"
  exit 2
fi
