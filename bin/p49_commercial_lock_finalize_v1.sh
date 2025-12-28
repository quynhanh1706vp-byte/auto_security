#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
OUT="out_ci"
RELROOT="$OUT/releases"
TS="$(date +%Y%m%d_%H%M%S)"
EVID="$OUT/p49_${TS}"
mkdir -p "$OUT" "$EVID"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need date; need ls; need head; need tail; need grep; need awk; need sed; need find; need sort; need wc; need stat; need sha256sum; need python3; need curl
command -v systemctl >/dev/null 2>&1 || true

log(){ echo "[$(date +%H:%M:%S)] $*"; }
warn(){ echo "[WARN] $*" >&2; }

PASS=1
REASONS=()

log "== [P49/0] locate latest release =="
latest_release="$(ls -1dt "$RELROOT"/RELEASE_UI_* 2>/dev/null | head -n 1 || true)"
if [ -z "${latest_release:-}" ] || [ ! -d "$latest_release" ]; then
  echo "[FAIL] no release found under $RELROOT" >&2
  exit 2
fi
log "[OK] latest_release=$latest_release"

mkdir -p "$latest_release/evidence/p49_${TS}"

log "== [P49/1] quick live health proof (for demo confidence) =="
curl -fsS --connect-timeout 2 --max-time 4 "$BASE/vsp5" -o "$EVID/vsp5.html" || { PASS=0; REASONS+=("vsp5_fetch_failed"); }
http_code="$(curl -sS -o /dev/null -w '%{http_code}' --connect-timeout 2 --max-time 4 "$BASE/vsp5" || true)"
echo "http_code_vsp5=$http_code" | tee "$EVID/health_${TS}.txt" >/dev/null
if [ "$http_code" != "200" ]; then PASS=0; REASONS+=("vsp5_http_$http_code"); fi

log "== [P49/2] collect key verdicts (best effort) =="
# Grab latest relevant verdicts
p46="$(ls -1t "$OUT"/p46_verdict_*.json 2>/dev/null | head -n 1 || true)"
p47e="$(ls -1t "$OUT"/p47_3e_verdict_*.json 2>/dev/null | head -n 1 || true)"
p48_fail="$(ls -1t "$OUT"/p48_verdict_*.json 2>/dev/null | head -n 1 || true)"
p48_0b="$(ls -1t "$OUT"/p48_0b_verdict_*.json 2>/dev/null | head -n 1 || true)"

{
  echo "p46=$p46"
  echo "p47_3e=$p47e"
  echo "p48_fail=$p48_fail"
  echo "p48_0b=$p48_0b"
} | tee "$EVID/verdict_paths_${TS}.txt" >/dev/null

cp_if(){ local f="$1"; [ -n "$f" ] && [ -f "$f" ] && cp -f "$f" "$EVID/" && echo "[OK] copied $(basename "$f")" || echo "[WARN] missing $f"; }
cp_if "$p46"
cp_if "$p47e"
cp_if "$p48_fail"
cp_if "$p48_0b"

# require p48_0b ok=true as final gate
if [ -z "${p48_0b:-}" ] || [ ! -f "$p48_0b" ]; then
  PASS=0; REASONS+=("missing_p48_0b_verdict")
else
  if ! python3 -c 'import json,sys; j=json.load(open(sys.argv[1])); sys.exit(0 if j.get("ok") else 2)' "$p48_0b"; then
    PASS=0; REASONS+=("p48_0b_not_ok")
  fi
fi

log "== [P49/3] attach evidence + verdicts into release =="
cp -f "$EVID/"* "$latest_release/evidence/p49_${TS}/" 2>/dev/null || true

# also attach p47 clean varlog proof if exists
p47_clean="$(ls -1t "$OUT"/p47_clean_varlog_*.txt 2>/dev/null | head -n 1 || true)"
if [ -n "$p47_clean" ] && [ -f "$p47_clean" ]; then
  cp -f "$p47_clean" "$latest_release/evidence/p49_${TS}/" || true
  log "[OK] attached $(basename "$p47_clean")"
fi

log "== [P49/4] write COMMERCIAL_LOCK.md (single-page executive proof) =="
LOCK="$latest_release/COMMERCIAL_LOCK.md"
cat > "$LOCK" <<EOF
# COMMERCIAL LOCK — VSP UI Release

Release folder: $(basename "$latest_release")
Locked at: $(date +'%Y-%m-%d %H:%M:%S %z')
Service: ${SVC}
Base URL: ${BASE}

## Operating mode (HARDENED)
- log location (ops): /var/log/vsp-ui-8910/ui_8910.access.log
- log location (ops): /var/log/vsp-ui-8910/ui_8910.error.log
- logrotate rule: /etc/logrotate.d/vsp-ui-8910
- drop-in (varlog mode): zzzz-99999-execstart-varlog.conf

## Evidence policy
- out_ci = evidence/audit artifacts (DO NOT rotate operationally)
- /var/log = operations logs (rotated by logrotate)

## Verdict chain
- P46 verdict (release pass): $(basename "${p46:-N/A}")
- P47.3e verdict (logrotate varlog bind): $(basename "${p47e:-N/A}")
- P48 verdict (fail record - false positive): $(basename "${p48_fail:-N/A}")
- P48.0b verdict (final pass): $(basename "${p48_0b:-N/A}")

All copied under:
- evidence/p49_${TS}/

## Quick health
- GET /vsp5 => expected 200
- captured: evidence/p49_${TS}/health_${TS}.txt
EOF

log "[OK] wrote $(basename "$LOCK")"

log "== [P49/5] refresh HANDOVER.md (ensure lock pointers exist) =="
H="$latest_release/HANDOVER.md"
[ -f "$H" ] || echo "# HANDOVER" > "$H"
grep -q '^commercial lock: COMMERCIAL_LOCK\.md' "$H" || echo "commercial lock: COMMERCIAL_LOCK.md" >> "$H"
grep -q '^evidence: evidence/p49_' "$H" || echo "evidence: evidence/p49_${TS}/" >> "$H"

log "== [P49/6] build CHECKSUMS.sha256 + RELEASE_MANIFEST.json =="
CHK="$latest_release/CHECKSUMS.sha256"
MAN="$latest_release/RELEASE_MANIFEST.json"

# checksums for the most important deliverables only
( cd "$latest_release" && \
  { \
    [ -f "HANDOVER.md" ] && sha256sum "HANDOVER.md"; \
    [ -f "COMMERCIAL_LOCK.md" ] && sha256sum "COMMERCIAL_LOCK.md"; \
    [ -f "OPS_RUNBOOK.md" ] && sha256sum "OPS_RUNBOOK.md"; \
    find evidence -type f -maxdepth 3 -print0 2>/dev/null | xargs -0 sha256sum 2>/dev/null || true; \
  } ) > "$CHK"

python3 - <<PY
import os, json, time
root = "$latest_release"
items=[]
for dirpath, dirnames, filenames in os.walk(root):
    for fn in filenames:
        p=os.path.join(dirpath, fn)
        rel=os.path.relpath(p, root)
        st=os.stat(p)
        items.append({
            "path": rel,
            "size": st.st_size,
            "mtime": time.strftime("%Y-%m-%dT%H:%M:%S%z", time.localtime(st.st_mtime))
        })
items.sort(key=lambda x: x["path"])
j={"ok": True, "root": os.path.basename(root), "generated_at": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
   "count": len(items), "items": items}
open("$MAN","w").write(json.dumps(j, indent=2))
print("[OK] manifest items =", len(items))
PY

log "== [P49/7] verdict json =="
VERDICT="$OUT/p49_verdict_${TS}.json"
python3 - <<PY
import json, time
ok = bool(int("$PASS"))
reasons = ${REASONS[@]+"["$(printf '"%s",' "${REASONS[@]}" | sed 's/,$//')"]"}
if reasons == "" or reasons is None:
    reasons = []
verdict = {
  "ok": ok,
  "ts": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
  "p49": {
    "release": "$latest_release",
    "commercial_lock": "COMMERCIAL_LOCK.md",
    "checksums": "CHECKSUMS.sha256",
    "manifest": "RELEASE_MANIFEST.json",
    "evidence_dir": "$EVID",
    "reasons": reasons
  }
}
print(json.dumps(verdict, indent=2))
open("$VERDICT","w").write(json.dumps(verdict, indent=2))
PY

cp -f "$VERDICT" "$latest_release/evidence/p49_${TS}/" 2>/dev/null || true

if [ "$PASS" -eq 1 ]; then
  log "[PASS] wrote $VERDICT"
  log "[DONE] P49 PASS (commercial lock finalized)"
else
  log "[FAIL] wrote $VERDICT"
  log "[DONE] P49 FAIL (see reasons in verdict)"
  exit 2
fi
