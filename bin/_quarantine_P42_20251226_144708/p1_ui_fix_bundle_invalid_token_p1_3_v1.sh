#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing cmd: $1"; exit 2; }; }
need python3; need date

TS="$(date +%Y%m%d_%H%M%S)"
echo "[INFO] TS=$TS"

# find bundle files that likely trigger the console error
FILES="$(ls -1 static/js/vsp_bundle_commercial*.js 2>/dev/null || true)"
if [ -z "$FILES" ]; then
  echo "[WARN] no static/js/vsp_bundle_commercial*.js found"
  exit 0
fi

for f in $FILES; do
  echo "== FIX $f =="
  cp -f "$f" "$f.bak_invalidtoken_${TS}"
  python3 - <<'PY'
from pathlib import Path
import sys

p = Path(sys.argv[1])
b = p.read_bytes()

# strip UTF-8 BOM if present
if b.startswith(b"\xef\xbb\xbf"):
    b = b[3:]

# remove NULL bytes
b = b.replace(b"\x00", b"")

# decode robustly, then normalize unicode separators & BOM char
s = b.decode("utf-8", errors="replace")
s = s.replace("\ufeff", "")          # BOM char
s = s.replace("\u2028", "\n")        # line separator
s = s.replace("\u2029", "\n")        # paragraph separator
s = s.replace("\r\n", "\n").replace("\r", "\n")

# ensure ends with newline
if not s.endswith("\n"):
    s += "\n"

p.write_text(s, encoding="utf-8")
print("[OK] normalized bytes/unicode in", p)
PY "$f"

  if command -v node >/dev/null 2>&1; then
    echo "== node --check $f =="
    node --check "$f" && echo "[OK] JS parse OK" || echo "[ERR] JS still invalid (needs manual inspect)"
  else
    echo "[WARN] node not installed; skip parse check"
  fi
done

echo "[DONE] bundle normalization complete"
