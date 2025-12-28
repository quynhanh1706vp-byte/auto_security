#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing cmd: $1"; exit 2; }; }
need python3; need date
TS="$(date +%Y%m%d_%H%M%S)"
echo "[INFO] TS=$TS"

F="static/js/vsp_bundle_commercial_v1.js"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

# (1) restore from latest backup if exists (important)
BK="$(ls -1t "${F}.bak_invalidtoken_"* 2>/dev/null | head -n1 || true)"
if [ -n "$BK" ]; then
  echo "[INFO] restore from backup: $BK"
  cp -f "$BK" "$F"
else
  echo "[WARN] no backup found ${F}.bak_invalidtoken_* (continue with current file)"
fi

cp -f "$F" "${F}.bak_before_v3_${TS}"
echo "[BACKUP] ${F}.bak_before_v3_${TS}"

# (2) sanitize without introducing replacement char "�"
python3 - "$F" <<'PY'
from pathlib import Path
import sys

p = Path(sys.argv[1])
b = p.read_bytes()

# strip UTF-8 BOM
if b.startswith(b"\xef\xbb\xbf"):
    b = b[3:]

# remove NUL bytes
b = b.replace(b"\x00", b"")

# remove ASCII control bytes except \n \r \t
clean = bytearray()
for x in b:
    if x in (9, 10, 13):  # \t \n \r
        clean.append(x)
    elif 32 <= x <= 126:
        clean.append(x)
    else:
        # keep bytes >= 0x80 for utf-8 decoding stage
        clean.append(x)

# decode as utf-8 but DROP invalid sequences (no "�")
s = bytes(clean).decode("utf-8", errors="ignore")

# normalize unicode separators + zero-width junk that can break parsing if outside strings
BAD = [
    "\u2028", "\u2029",  # line/paragraph separators
    "\ufeff",            # BOM char
    "\u200b", "\u200c", "\u200d", "\u2060",  # zero-width
    "\u00a0",            # NBSP
]
for ch in BAD:
    s = s.replace(ch, "\n" if ch in ("\u2028","\u2029") else " ")

# normalize newlines
s = s.replace("\r\n", "\n").replace("\r", "\n")
if not s.endswith("\n"):
    s += "\n"

p.write_text(s, encoding="utf-8")
print("[OK] sanitized:", p)
PY

# (3) syntax check
if command -v node >/dev/null 2>&1; then
  echo "== node --check $F =="
  node --check "$F"
  echo "[OK] JS parse OK"
else
  echo "[WARN] node not installed; skip parse check"
fi
