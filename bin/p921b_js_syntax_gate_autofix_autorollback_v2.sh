#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
TS="$(date +%Y%m%d_%H%M%S)"
OUT="out_ci/p921b_js_${TS}"
mkdir -p "$OUT"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need node; need python3; need curl; need date
command -v sudo >/dev/null 2>&1 || true

FILES=(
  "static/js/vsp_c_settings_v1.js"
)

log(){ echo "$*" | tee -a "$OUT/summary.txt"; }

node_check(){
  local f="$1"
  node --check "$f" >/dev/null 2>&1
}

sanitize_js_inplace(){
  local f="$1"
  python3 - <<PY
from pathlib import Path
p=Path("$f")
b=p.read_bytes()

# normalize line endings
b=b.replace(b"\r\n", b"\n").replace(b"\r", b"\n")

# drop NUL bytes
b=b.replace(b"\x00", b"")

# remove UTF-8 BOM anywhere
b=b.replace(b"\xef\xbb\xbf", b"")

# decode/encode with replacement then remove dangerous unicode separators
s=b.decode("utf-8","replace")
s=s.replace("\u2028","\\n").replace("\u2029","\\n").replace("\ufeff","")

# remove other control chars except \n \t
clean=[]
for ch in s:
    o=ord(ch)
    if ch in ("\n","\t") or o>=32:
        clean.append(ch)
s="".join(clean)

if not s.endswith("\n"):
    s += "\n"
p.write_text(s, encoding="utf-8")
PY
}

good_backup_restore(){
  local f="$1"
  local ok=1
  # backups are created like: file.js.bak_p916b_YYYY... OR file.js.bak_ensureRid_...
  # so match: "${f}.bak_*"
  local cand
  for cand in $(ls -1t "${f}.bak_"* 2>/dev/null || true); do
    if node --check "$cand" >/dev/null 2>&1; then
      cp -f "$cand" "$f"
      log "[OK] rollback from good backup: $cand -> $f"
      ok=0
      break
    fi
  done
  return $ok
}

changed=0
for f in "${FILES[@]}"; do
  if [ ! -f "$f" ]; then
    log "[WARN] missing file: $f (skip)"
    continue
  fi

  if node_check "$f"; then
    log "[OK] js syntax OK: $f"
    continue
  fi

  log "[WARN] js syntax FAIL: $f"
  badbk="${f}.bak_p921b_bad_${TS}"
  cp -f "$f" "$badbk"
  log "[OK] backup bad => $badbk"

  log "== sanitize in-place =="
  sanitize_js_inplace "$f"

  if node_check "$f"; then
    log "[OK] sanitize fixed syntax: $f"
    changed=1
    continue
  fi

  log "[WARN] sanitize not enough, try rollback from any good backup =="
  if good_backup_restore "$f"; then
    log "[FAIL] no good backup found for $f"
    exit 3
  fi

  changed=1
done

if [ "$changed" -eq 1 ]; then
  log "== restart service =="
  sudo systemctl restart "$SVC" || true
fi

log "== quick verify (tabs + key APIs) =="
bash bin/p918_p0_smoke_no_error_v1.sh | tee -a "$OUT/smoke.txt"

log "[OK] P921B done. Open: $BASE/c/settings (Ctrl+Shift+R) and check console."
log "[OK] Evidence: $OUT"
