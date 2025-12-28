#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing cmd: $1"; exit 2; }; }
need python3; need date
command -v node >/dev/null 2>&1 || { echo "[ERR] missing node (needed for syntax check)"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
echo "[INFO] TS=$TS"

# ---- (1) Fix fillreal: hoist __vsp_mount_root + move __vsp_host init after it ----
JS="static/js/vsp_fill_real_data_5tabs_p1_v1.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

cp -f "$JS" "${JS}.bak_fix_${TS}"
echo "[BACKUP] ${JS}.bak_fix_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("static/js/vsp_fill_real_data_5tabs_p1_v1.js")
s=p.read_text(encoding="utf-8", errors="replace")

# 1) remove early host init if present
s = re.sub(r'^\s*const\s+__vsp_host\s*=\s*__vsp_mount_root\(\)\s*;\s*\n', '', s, flags=re.M)

# 2) convert "const __vsp_mount_root = () => { ... };" to hoisted function
#    so it can be called anytime
pat = r'const\s+__vsp_mount_root\s*=\s*\(\)\s*=>\s*\{'
if re.search(pat, s):
    s = re.sub(pat, 'function __vsp_mount_root(){', s, count=1)
    # close function: find the first occurrence of "};" after it (best-effort)
    # replace the first "};" after marker with "}"
    idx = s.find("function __vsp_mount_root(){")
    if idx >= 0:
        tail = s[idx:]
        j = tail.find("};")
        if j >= 0:
            tail2 = tail[:j] + "}\n" + tail[j+2:]
            s = s[:idx] + tail2

# 3) ensure we define host AFTER function exists (right after mount function block or after style append)
# place after the console.info line if exists, else after function definition line.
if "__vsp_mount_root" in s and "__vsp_host" not in s:
    insert_after = None
    m = re.search(r'console\.info\(\s*"\[VSP\]\[fillreal\]\s*mounted host"\s*\)\s*;?', s)
    if m:
        insert_after = m.end()
    else:
        m2 = re.search(r'function\s+__vsp_mount_root\(\)\{', s)
        if m2:
            # insert near end of function: after first "return host;" if exists
            m3 = re.search(r'return\s+host\s*;\s*', s)
            insert_after = m3.end() if m3 else m2.end()

    if insert_after:
        s = s[:insert_after] + "\n  const __vsp_host = __vsp_mount_root();\n" + s[insert_after:]
    else:
        # fallback append
        s += "\n  const __vsp_host = __vsp_mount_root();\n"

p.write_text(s, encoding="utf-8")
print("[OK] patched fillreal mount/hoist")
PY

node --check "$JS" >/dev/null
echo "[OK] node --check OK: $JS"

# ---- (2) Fix bundle commercial: if syntax error, auto-rollback to newest working .bak_* ----
fix_one_bundle () {
  local f="$1"
  if node --check "$f" >/dev/null 2>&1; then
    echo "[OK] bundle syntax OK: $f"
    return 0
  fi
  echo "[WARN] bundle syntax FAIL: $f"
  local dir base
  dir="$(dirname "$f")"
  base="$(basename "$f")"

  # find candidate backups (newest first)
  local cand
  cand="$(ls -1t "$dir/$base".bak_* "$dir/$base".bak* 2>/dev/null | head -n 50 || true)"
  if [ -z "$cand" ]; then
    echo "[ERR] no backups found for $f"
    return 1
  fi

  local okbak=""
  while IFS= read -r b; do
    [ -f "$b" ] || continue
    if node --check "$b" >/dev/null 2>&1; then
      okbak="$b"
      break
    fi
  done <<<"$cand"

  if [ -z "$okbak" ]; then
    echo "[ERR] no working backup passes node --check for $f"
    return 1
  fi

  cp -f "$f" "$f.bak_broken_${TS}" || true
  cp -f "$okbak" "$f"
  echo "[FIX] restored $f from: $okbak"
  node --check "$f" >/dev/null
  echo "[OK] bundle now OK: $f"
}

# try both v1/v2 etc if exist
shopt -s nullglob
BUNDLES=(static/js/vsp_bundle_commercial_v*.js static/js/vsp_bundle_commercial*.js)
if [ ${#BUNDLES[@]} -eq 0 ]; then
  echo "[WARN] no bundle commercial js found under static/js (skip)"
else
  for f in "${BUNDLES[@]}"; do
    # skip non-files
    [ -f "$f" ] || continue
    fix_one_bundle "$f" || true
  done
fi

echo "[NEXT] restart service"
echo "  sudo systemctl restart vsp-ui-8910.service"
