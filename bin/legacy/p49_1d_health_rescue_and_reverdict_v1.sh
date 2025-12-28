#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
OUT="out_ci"
RELROOT="$OUT/releases"
TS="$(date +%Y%m%d_%H%M%S)"
EVID="$OUT/p49_1d_${TS}"
mkdir -p "$OUT" "$EVID"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need date; need ls; need head; need tail; need grep; need awk; need sed; need find; need sort; need wc; need stat; need python3; need curl
need sudo
command -v systemctl >/dev/null 2>&1 || true
command -v ss >/dev/null 2>&1 || true

log(){ echo "[$(date +%H:%M:%S)] $*"; }

latest_release="$(ls -1dt "$RELROOT"/RELEASE_UI_* 2>/dev/null | head -n 1 || true)"
[ -n "${latest_release:-}" ] && [ -d "$latest_release" ] || { echo "[ERR] no release in $RELROOT"; exit 2; }
log "[OK] latest_release=$latest_release"
mkdir -p "$latest_release/evidence/p49_1d_${TS}"

log "== [P49.1d/0] capture pre-restart diagnostics =="
{
  echo "BASE=$BASE"
  echo "SVC=$SVC"
  echo "TS=$TS"
  echo
  echo "## systemctl is-active"
  systemctl is-active "$SVC" 2>/dev/null || true
  echo
  echo "## systemctl status"
  systemctl status "$SVC" --no-pager 2>/dev/null || true
  echo
  echo "## DropInPaths + ExecStart"
  systemctl show "$SVC" -p DropInPaths -p ExecStart -p ActiveState -p SubState 2>/dev/null || true
  echo
  echo "## ss -ltnp (port 8910)"
  ss -ltnp 2>/dev/null | grep -E '(:8910\b)' || true
  echo
  echo "## curl headers (best effort)"
  curl -sS -D- -o /dev/null --connect-timeout 2 --max-time 4 "$BASE/vsp5" || true
  echo
  echo "## journalctl -n 200"
  journalctl -u "$SVC" -n 200 --no-pager 2>/dev/null || true
} | tee "$EVID/pre_diag_${TS}.txt" >/dev/null

log "== [P49.1d/1] restart service (rescue) =="
sudo systemctl daemon-reload >/dev/null 2>&1 || true
sudo systemctl restart "$SVC"

log "== [P49.1d/2] wait for /vsp5 200 (max ~30s) =="
ok=0
for i in $(seq 1 60); do
  code="$(curl -sS -o /dev/null -w '%{http_code}' --connect-timeout 1 --max-time 2 "$BASE/vsp5" || true)"
  echo "try#$i http_code=$code" >> "$EVID/wait_${TS}.txt"
  if [ "$code" = "200" ]; then ok=1; break; fi
  sleep 0.5
done

log "== [P49.1d/3] capture post-restart proof =="
curl -fsS --connect-timeout 2 --max-time 6 "$BASE/vsp5" -o "$EVID/vsp5_after.html" || true
curl -sS -D- -o /dev/null --connect-timeout 2 --max-time 6 "$BASE/vsp5" > "$EVID/vsp5_after_headers_${TS}.txt" || true
systemctl status "$SVC" --no-pager > "$EVID/status_after_${TS}.txt" 2>&1 || true
ss -ltnp 2>/dev/null | grep -E '(:8910\b)' > "$EVID/ss_8910_after_${TS}.txt" || true

# attach evidence to release
cp -f "$EVID/"* "$latest_release/evidence/p49_1d_${TS}/" 2>/dev/null || true

log "== [P49.1d/4] update COMMERCIAL_LOCK.md with live health result =="
LOCK="$latest_release/COMMERCIAL_LOCK.md"
if [ -f "$LOCK" ]; then
  echo "" >> "$LOCK"
  echo "## Live health (post-rescue)" >> "$LOCK"
  echo "checked_at: $(date +'%Y-%m-%d %H:%M:%S %z')" >> "$LOCK"
  echo "base: $BASE" >> "$LOCK"
  echo "GET /vsp5 => $([ "$ok" -eq 1 ] && echo PASS || echo FAIL)" >> "$LOCK"
  echo "evidence: evidence/p49_1d_${TS}/" >> "$LOCK"
fi

log "== [P49.1d/5] verdict json =="
VERDICT="$OUT/p49_1d_verdict_${TS}.json"
python3 - <<PY
import json, time
ok = bool(int("$ok"))
verdict = {
  "ok": ok,
  "ts": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
  "p49_1d": {
    "base": "$BASE",
    "service": "$SVC",
    "latest_release": "$latest_release",
    "evidence_dir": "$EVID",
    "attached": f"{latest_release}/evidence/p49_1d_${TS}/"
  }
}
print(json.dumps(verdict, indent=2))
open("$VERDICT","w").write(json.dumps(verdict, indent=2))
PY

cp -f "$VERDICT" "$latest_release/evidence/p49_1d_${TS}/" 2>/dev/null || true

if [ "$ok" -eq 1 ]; then
  log "[PASS] wrote $VERDICT"
  log "[DONE] P49.1d PASS (P49 can be considered GREEN after rescue)"
else
  log "[FAIL] wrote $VERDICT"
  log "[DONE] P49.1d FAIL (service still not responding on $BASE/vsp5)"
  exit 2
fi
