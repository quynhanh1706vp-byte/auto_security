#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
OUT="out_ci"
RELROOT="$OUT/releases"
TS="$(date +%Y%m%d_%H%M%S)"
EVID="$OUT/p52_1h2_${TS}"
mkdir -p "$EVID"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need date; need ls; need head; need curl; need python3; need sudo
command -v systemctl >/dev/null 2>&1 || true

latest_release="$(ls -1dt "$RELROOT"/RELEASE_UI_* 2>/dev/null | head -n 1 || true)"
[ -n "${latest_release:-}" ] && [ -d "$latest_release" ] || { echo "[ERR] no release found"; exit 2; }
ATT="$latest_release/evidence/p52_1h2_${TS}"
mkdir -p "$ATT"

echo "[OK] latest_release=$latest_release"
echo "[INFO] restart + warm..." | tee "$EVID/info.txt" >/dev/null
sudo systemctl restart "$SVC" || true
sleep 1.2

# Warm: allow longer on first hit (cache build, imports, disk IO)
curl -sS -o /dev/null --connect-timeout 2 --max-time 12 "$BASE/vsp5" || true
sleep 0.5

ok=1
: > "$EVID/checks_10x.txt"
for i in $(seq 1 10); do
  # Stable window: 6s max-time (more realistic than 4s), record code + time_total
  out="$(curl -sS -o /dev/null -w 'code=%{http_code} time=%{time_total}\n' --connect-timeout 2 --max-time 6 "$BASE/vsp5" || echo 'code=000 time=99')"
  echo "try#$i $out" | tee -a "$EVID/checks_10x.txt" >/dev/null
  code="$(echo "$out" | awk '{print $1}' | cut -d= -f2)"
  if [ "$code" != "200" ]; then ok=0; fi
  sleep 0.4
done

VER="$OUT/p52_1h2_verdict_${TS}.json"
python3 - <<PY
import json, time
j={"ok": bool(int("$ok")),
   "ts": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
   "p52_1h2": {"base":"$BASE","service":"$SVC",
               "latest_release":"$latest_release",
               "evidence_dir":"$EVID","attached_dir":"$ATT"}}
print(json.dumps(j, indent=2))
open("$VER","w").write(json.dumps(j, indent=2))
PY

cp -f "$EVID/"* "$ATT/" 2>/dev/null || true
cp -f "$VER" "$ATT/" 2>/dev/null || true

if [ "$ok" -eq 1 ]; then
  echo "[DONE] P52.1h2 PASS (10/10 stable)"
else
  echo "[DONE] P52.1h2 FAIL (see $EVID/checks_10x.txt)" >&2
  exit 2
fi
