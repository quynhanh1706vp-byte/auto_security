#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
OUT="out_ci"
RELROOT="$OUT/releases"
TS="$(date +%Y%m%d_%H%M%S)"
EVID="$OUT/p49_1e_${TS}"
mkdir -p "$OUT" "$EVID"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need date; need ls; need head; need tail; need grep; need awk; need sed; need python3; need curl
need sudo
command -v systemctl >/dev/null 2>&1 || true
command -v ss >/dev/null 2>&1 || true
command -v ps >/dev/null 2>&1 || true

log(){ echo "[$(date +%H:%M:%S)] $*"; }

latest_release="$(ls -1dt "$RELROOT"/RELEASE_UI_* 2>/dev/null | head -n 1 || true)"
[ -n "${latest_release:-}" ] && [ -d "$latest_release" ] || { echo "[ERR] no release in $RELROOT"; exit 2; }
log "[OK] latest_release=$latest_release"
ATTACH_DIR="$latest_release/evidence/p49_1e_${TS}"
mkdir -p "$ATTACH_DIR"

diag(){
  local tag="$1"
  local f="$EVID/${tag}_${TS}.txt"
  {
    echo "== $tag =="
    echo "BASE=$BASE"
    echo "SVC=$SVC"
    echo "TIME=$(date +'%Y-%m-%d %H:%M:%S %z')"
    echo
    echo "## systemctl is-active"
    systemctl is-active "$SVC" 2>/dev/null || true
    echo
    echo "## systemctl status (short)"
    systemctl status "$SVC" --no-pager -n 80 2>/dev/null || true
    echo
    echo "## systemctl show (DropInPaths/ExecStart/ActiveState/SubState)"
    systemctl show "$SVC" -p DropInPaths -p ExecStart -p ActiveState -p SubState -p FragmentPath -p UnitFileState 2>/dev/null || true
    echo
    echo "## ss -ltnp :8910"
    ss -ltnp 2>/dev/null | grep -E '(:8910\b)' || true
    echo
    echo "## ps (gunicorn/python)"
    ps aux 2>/dev/null | grep -E 'gunicorn|vsp_demo_app|wsgi_vsp_ui_gateway|:8910' | grep -v grep || true
    echo
    echo "## curl headers (best effort)"
    curl -sS -D- -o /dev/null --connect-timeout 2 --max-time 4 "$BASE/vsp5" || true
    echo
    echo "## journalctl -u (last 200)"
    journalctl -u "$SVC" -n 200 --no-pager 2>/dev/null || true
  } | tee "$f" >/dev/null
}

log "== [P49.1e/0] pre diagnostics =="
diag "pre"

log "== [P49.1e/1] restart rescue (with reset-failed) =="
sudo systemctl reset-failed "$SVC" >/dev/null 2>&1 || true
sudo systemctl daemon-reload >/dev/null 2>&1 || true
sudo systemctl restart "$SVC" || true

log "== [P49.1e/2] wait /vsp5 200 (max 45s) =="
ok=0
WAIT="$EVID/wait_${TS}.txt"
: > "$WAIT"
for i in $(seq 1 90); do
  code="$(curl -sS -o /dev/null -w '%{http_code}' --connect-timeout 1 --max-time 2 "$BASE/vsp5" || true)"
  echo "try#$i http_code=$code" >> "$WAIT"
  if [ "$code" = "200" ]; then ok=1; break; fi
  sleep 0.5
done

log "== [P49.1e/3] post diagnostics =="
diag "post"

log "== [P49.1e/4] capture /vsp5 body if OK =="
if [ "$ok" -eq 1 ]; then
  curl -fsS --connect-timeout 2 --max-time 6 "$BASE/vsp5" -o "$EVID/vsp5_after_${TS}.html" || true
fi

log "== [P49.1e/5] attach evidence to release =="
cp -f "$EVID/"* "$ATTACH_DIR/" 2>/dev/null || true

log "== [P49.1e/6] update COMMERCIAL_LOCK.md =="
LOCK="$latest_release/COMMERCIAL_LOCK.md"
if [ -f "$LOCK" ]; then
  {
    echo
    echo "## Live health (P49.1e)"
    echo "checked_at: $(date +'%Y-%m-%d %H:%M:%S %z')"
    echo "base: $BASE"
    echo "GET /vsp5 => $([ "$ok" -eq 1 ] && echo PASS || echo FAIL)"
    echo "evidence: evidence/p49_1e_${TS}/"
  } >> "$LOCK"
fi

log "== [P49.1e/7] verdict json (no crash) =="
VERDICT="$OUT/p49_1e_verdict_${TS}.json"
python3 - <<PY
import json, time
ok = bool(int("$ok"))
verdict = {
  "ok": ok,
  "ts": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
  "p49_1e": {
    "base": "$BASE",
    "service": "$SVC",
    "latest_release": "$latest_release",
    "evidence_dir": "$EVID",
    "attached_dir": "$ATTACH_DIR"
  }
}
print(json.dumps(verdict, indent=2))
open("$VERDICT","w").write(json.dumps(verdict, indent=2))
PY

cp -f "$VERDICT" "$ATTACH_DIR/" 2>/dev/null || true

if [ "$ok" -eq 1 ]; then
  log "[PASS] wrote $VERDICT"
  log "[DONE] P49.1e PASS"
else
  log "[FAIL] wrote $VERDICT"
  log "[DONE] P49.1e FAIL (service not serving $BASE/vsp5)"
  exit 2
fi
