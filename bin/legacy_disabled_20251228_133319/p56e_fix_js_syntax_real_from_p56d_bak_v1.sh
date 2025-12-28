#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

OUT="out_ci"
TS="$(date +%Y%m%d_%H%M%S)"
EVID="$OUT/p56e_fix_js_${TS}"
mkdir -p "$EVID"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need node; need ls; need head; need cp; need sed; need grep

log(){ echo "[$(date +%H:%M:%S)] $*"; }

FILES=(
  "static/js/vsp_tabs4_autorid_v1.js"
  "static/js/vsp_dashboard_luxe_v1.js"
  "static/js/vsp_dashboard_consistency_patch_v1.js"
)

latest_bak(){
  local f="$1"
  ls -1t "${f}.bak_p56d_"* 2>/dev/null | head -n 1 || true
}

log "== [P56E/1] restore originals from latest .bak_p56d_* =="
for f in "${FILES[@]}"; do
  b="$(latest_bak "$f")"
  if [ -z "${b:-}" ]; then
    log "[ERR] no .bak_p56d_* found for $f (can't restore original)"
    exit 2
  fi
  cp -f "$f" "$EVID/$(basename "$f").pre_restore" 2>/dev/null || true
  cp -f "$b" "$f"
  log "[OK] restored $f <= $b"
done

log "== [P56E/2] apply targeted fixes =="
python3 - <<'PY'
from pathlib import Path
import re, datetime

ts = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")

def patch_file(p: Path):
    s = p.read_text(encoding="utf-8", errors="replace")

    orig = s

    # Fix #1: missing "debug:" key before console.debug conditional (object literal)
    # Replace a line that starts with spaces + "console.debug ? console.debug.bind(console) : ()=>{}," into a proper property.
    s, n1 = re.subn(
        r'(?m)^(\s*)console\.debug\s*\?\s*console\.debug\.bind\(console\)\s*:\s*\(\)\s*=>\s*\{\}\s*,\s*$',
        r'\1debug: (console.debug ? console.debug.bind(console) : (()=>{})),',
        s
    )

    # Fix #2/#3: sev object has trailing ",0" -> should be ",TRACE:0"
    # Handles: "INFO:0,0}" and "INFO:0, 0 }" and also closing with "};"
    s, n2 = re.subn(
        r'INFO\s*:\s*0\s*,\s*0(\s*[}\]])',
        r'INFO:0, TRACE:0\1',
        s
    )

    if s != orig:
        bak = p.with_name(p.name + f".bak_p56e_{ts}")
        bak.write_text(orig, encoding="utf-8")
        p.write_text(s, encoding="utf-8")
        print("[PATCHED]", p, "n1=", n1, "n2=", n2, "bak=", bak.name)
    else:
        print("[NOCHANGE]", p, "(pattern not found!)")

for f in [
    "static/js/vsp_tabs4_autorid_v1.js",
    "static/js/vsp_dashboard_luxe_v1.js",
    "static/js/vsp_dashboard_consistency_patch_v1.js",
]:
    patch_file(Path(f))
PY

log "== [P56E/3] node --check =="
ok=1
for f in "${FILES[@]}"; do
  if node --check "$f" >/dev/null 2>"$EVID/$(basename "$f").node.err"; then
    log "[OK] syntax OK: $f"
  else
    log "[FAIL] syntax FAIL: $f"
    tail -n 40 "$EVID/$(basename "$f").node.err" || true
    ok=0
  fi
done

if [ "$ok" -ne 1 ]; then
  log "[ERR] still failing. Evidence: $EVID"
  exit 1
fi

log "[DONE] P56E PASS. Now hard refresh browser: Ctrl+Shift+R"
log "Evidence: $EVID"
