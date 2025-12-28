#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
OUT="out_ci"
RELROOT="$OUT/releases"
TS="$(date +%Y%m%d_%H%M%S)"
EVID="$OUT/p49_1f_${TS}"
mkdir -p "$EVID"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need date; need curl; need python3; need sudo; need tail; need head; need ls
command -v systemctl >/dev/null 2>&1 || { echo "[ERR] systemctl not found"; exit 2; }
command -v ss >/dev/null 2>&1 || true

log(){ echo "[$(date +%H:%M:%S)] $*"; }

latest_release="$(ls -1dt "$RELROOT"/RELEASE_UI_* 2>/dev/null | head -n 1 || true)"
[ -n "${latest_release:-}" ] && [ -d "$latest_release" ] || { echo "[ERR] no release in $RELROOT"; exit 2; }
ATT="$latest_release/evidence/p49_1f_${TS}"
mkdir -p "$ATT"
log "[OK] latest_release=$latest_release"

log "== [P49.1f/0] restart service =="
sudo systemctl reset-failed "$SVC" >/dev/null 2>&1 || true
sudo systemctl daemon-reload >/dev/null 2>&1 || true
sudo systemctl restart "$SVC" || true

log "== [P49.1f/1] wait for /vsp5 to be HTTP 200 (max 45s) =="
ok=0
for i in $(seq 1 90); do
  code="$(curl -sS -o /dev/null -w '%{http_code}' --connect-timeout 1 --max-time 2 "$BASE/vsp5" 2>/dev/null || true)"
  echo "try#$i http_code=$code" >> "$EVID/wait_${TS}.txt"
  if [ "$code" = "200" ]; then ok=1; break; fi
  sleep 0.5
done

log "== [P49.1f/2] collect proofs =="
systemctl status "$SVC" --no-pager -n 120 > "$EVID/status_${TS}.txt" 2>&1 || true
systemctl show "$SVC" -p ActiveState -p SubState -p ExecStart -p DropInPaths > "$EVID/show_${TS}.txt" 2>&1 || true
journalctl -u "$SVC" -n 200 --no-pager > "$EVID/journal_${TS}.txt" 2>&1 || true
if command -v ss >/dev/null 2>&1; then ss -ltnp | grep -E '(:8910\b)' > "$EVID/ss_8910_${TS}.txt" 2>&1 || true; fi
curl -sS -D- -o /dev/null --connect-timeout 2 --max-time 4 "$BASE/vsp5" > "$EVID/vsp5_headers_${TS}.txt" 2>&1 || true
if [ "$ok" -eq 1 ]; then
  curl -fsS --connect-timeout 2 --max-time 6 "$BASE/vsp5" -o "$EVID/vsp5_body_${TS}.html" || true
fi

log "== [P49.1f/3] verdict json (STRICT) =="
VER="$OUT/p49_1f_verdict_${TS}.json"
python3 - <<PY
import json, time
ok = bool(int("$ok"))
j = {
  "ok": ok,
  "ts": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
  "p49_1f": {
    "base": "$BASE",
    "service": "$SVC",
    "latest_release": "$latest_release",
    "evidence_dir": "$EVID",
    "attached_dir": "$ATT"
  }
}
print(json.dumps(j, indent=2))
open("$VER","w").write(json.dumps(j, indent=2))
PY

cp -f "$EVID/"* "$ATT/" 2>/dev/null || true
cp -f "$VER" "$ATT/" 2>/dev/null || true

if [ "$ok" -eq 1 ]; then
  log "[PASS] wrote $VER"
  log "[DONE] P49.1f PASS (HTTP 200 confirmed)"
else
  log "[FAIL] wrote $VER"
  log "[DONE] P49.1f FAIL (no HTTP 200 on $BASE/vsp5)"
  exit 2
fi
