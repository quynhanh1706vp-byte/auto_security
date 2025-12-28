#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing cmd: $1"; exit 2; }; }
need python3; need date

TS="$(date +%Y%m%d_%H%M%S)"
echo "[INFO] TS=$TS"

FILES="$(ls -1 static/js/vsp_bundle_commercial*.js 2>/dev/null || true)"
if [ -z "$FILES" ]; then
  echo "[WARN] no static/js/vsp_bundle_commercial*.js found"
  exit 0
fi

for f in $FILES; do
  echo "== FIX $f =="
  cp -f "$f" "$f.bak_invalidtoken_${TS}"

  python3 - "$f" <<'PY'
from pathlib import Path
import sys

p = Path(sys.argv[1])
b = p.read_bytes()

# strip UTF-8 BOM if present
if b.startswith(b"\xef\xbb\xbf"):
    b = b[3:]

# remove NULL bytes
b = b.replace(b"\x00", b"")

# decode robustly
s = b.decode("utf-8", errors="replace")

# normalize problematic unicode separators + BOM char
s = s.replace("\ufeff", "")
s = s.replace("\u2028", "\n")
s = s.replace("\u2029", "\n")

# normalize newlines
s = s.replace("\r\n", "\n").replace("\r", "\n")

if not s.endswith("\n"):
    s += "\n"

p.write_text(s, encoding="utf-8")
print("[OK] normalized:", p)
PY

  if command -v node >/dev/null 2>&1; then
    echo "== node --check $f =="
    node --check "$f" && echo "[OK] JS parse OK" || { echo "[ERR] JS still invalid: $f"; exit 3; }
  else
    echo "[WARN] node not installed; skip parse check"
  fi
done

echo "[DONE] bundle normalization complete"
