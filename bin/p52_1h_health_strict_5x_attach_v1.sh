#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
OUT="out_ci"
RELROOT="$OUT/releases"
TS="$(date +%Y%m%d_%H%M%S)"
EVID="$OUT/p52_1h_${TS}"
mkdir -p "$EVID"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need date; need ls; need head; need curl; need python3; need mkdir; need cp

log(){ echo "[$(date +%H:%M:%S)] $*"; }

latest_release="$(ls -1dt "$RELROOT"/RELEASE_UI_* 2>/dev/null | head -n 1 || true)"
[ -n "${latest_release:-}" ] && [ -d "$latest_release" ] || { echo "[ERR] no release found"; exit 2; }
ATT="$latest_release/evidence/p52_1h_${TS}"
mkdir -p "$ATT"

log "[OK] latest_release=$latest_release"
log "== [P52.1h] strict check: /vsp5 must be 200 for 5 consecutive tries =="

ok=1
: > "$EVID/checks.txt"
for i in 1 2 3 4 5; do
  code="$(curl -sS -o /dev/null -w '%{http_code}' --connect-timeout 2 --max-time 4 "$BASE/vsp5" || true)"
  echo "try#$i http_code=$code" | tee -a "$EVID/checks.txt" >/dev/null
  if [ "$code" != "200" ]; then ok=0; fi
  sleep 0.4
done

curl -sS -D- -o /dev/null --connect-timeout 2 --max-time 4 "$BASE/vsp5" > "$EVID/vsp5_headers.txt" 2>&1 || true

VER="$OUT/p52_1h_verdict_${TS}.json"
python3 - <<PY
import json, time
j={"ok": bool(int("$ok")),
   "ts": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
   "p52_1h": {"base":"$BASE","latest_release":"$latest_release",
              "evidence_dir":"$EVID","attached_dir":"$ATT"}}
print(json.dumps(j, indent=2))
open("$VER","w").write(json.dumps(j, indent=2))
PY

cp -f "$EVID/"* "$ATT/" 2>/dev/null || true
cp -f "$VER" "$ATT/" 2>/dev/null || true

if [ "$ok" -eq 1 ]; then
  log "[PASS] /vsp5 stable 5/5"
  log "[DONE] P52.1h PASS"
else
  log "[FAIL] /vsp5 not stable"
  log "[DONE] P52.1h FAIL"
  exit 2
fi
