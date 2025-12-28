#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need node; need python3; need date; need sed; need awk; need head; need tail

ok(){ echo "[OK] $*"; }
warn(){ echo "[WARN] $*" >&2; }

TS="$(date +%Y%m%d_%H%M%S)"

FILES=(
  "static/js/vsp_bundle_tabs5_v1.js"
  "static/js/vsp_tabs4_autorid_v1.js"
)

node_check_show(){
  local f="$1"
  node --check "$f" 2>&1 | sed -n '1,6p'
}

extract_line(){
  # try parse "...:LINE" from node syntax error output
  # node usually prints: /path/file.js:43
  echo "$1" | awk '
    match($0, /:[0-9]+$/) { sub(/^.*:/,"",$0); print $0; exit }
    match($0, /:[0-9]+:[0-9]+$/) { gsub(/^.*:/,""); sub(/:.*$/,""); print $0; exit }
  ' | head -n 1
}

for f in "${FILES[@]}"; do
  [ -f "$f" ] || { echo "[ERR] missing $f"; exit 2; }
  cp -f "$f" "${f}.bak_sanitize_${TS}"
  ok "backup: ${f}.bak_sanitize_${TS}"

  if node --check "$f" >/dev/null 2>&1; then
    ok "syntax already OK: $f"
    continue
  fi

  warn "syntax FAIL, sanitizing: $f"
  # sanitize unicode/control chars that cause "Invalid or unexpected token"
  python3 - <<PY
from pathlib import Path
import re

p=Path("$f")
b=p.read_bytes()

# 1) Drop NUL bytes (rare, but fatal)
b=b.replace(b"\x00", b"")

# 2) Decode as UTF-8 with replacement, then scrub problematic unicode
s=b.decode("utf-8", errors="replace")

# Remove BOM + zero-width chars that break JS parsing in some contexts
s=s.replace("\ufeff","")
for ch in ["\u200b","\u200c","\u200d","\u2060","\u180e"]:
    s=s.replace(ch,"")

# Normalize newlines
s=s.replace("\r\n","\n").replace("\r","\n")

# Replace NBSP with normal space
s=s.replace("\u00a0"," ")

# Replace smart quotes/dashes/ellipsis with ASCII
rep = {
  "\u2018":"'","\u2019":"'","\u201c":'"',"\u201d":'"',
  "\u2013":"-","\u2014":"-",
  "\u2026":"...",
}
for k,v in rep.items():
    s=s.replace(k,v)

# If any remaining non-printable control chars (except \n \t) -> space
s="".join((c if (c=="\n" or c=="\t" or ord(c)>=32) else " ") for c in s)

p.write_text(s, encoding="utf-8")
print("[OK] sanitized", p)
PY

  if node --check "$f" >/dev/null 2>&1; then
    ok "syntax OK after sanitize: $f"
  else
    warn "still FAIL after sanitize: $f"
    out="$(node --check "$f" 2>&1 || true)"
    echo "$out" | sed -n '1,12p'
    # try show nearby lines
    line="$(python3 - <<PY
import re,sys
m=re.search(r':(\\d+)\\s*$', """$out""", re.M)
print(m.group(1) if m else "")
PY
)"
    if [ -n "${line:-}" ]; then
      warn "show context around line=$line in $f"
      nl -ba "$f" | sed -n "$((line-4)),$((line+4))p" || true
    fi
    exit 3
  fi
done

echo
ok "All targeted JS files passed node --check."
echo "[NEXT] Ctrl+Shift+R:"
echo "  http://127.0.0.1:8910/vsp5"
