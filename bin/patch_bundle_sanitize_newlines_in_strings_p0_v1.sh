#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

B="static/js/vsp_bundle_commercial_v1.js"
TS="$(date +%Y%m%d_%H%M%S)"
[ -f "$B" ] || { echo "[ERR] missing $B"; exit 2; }

cp -f "$B" "$B.bak_sanitize_nl_${TS}"
echo "[BACKUP] $B.bak_sanitize_nl_${TS}"

python3 - <<'PY'
from pathlib import Path

p = Path("static/js/vsp_bundle_commercial_v1.js")
s = p.read_text(encoding="utf-8", errors="replace")

out = []
i = 0
n = len(s)

in_sq = False   # '
in_dq = False   # "
in_bt = False   # `
escaped = False
fixes = 0

while i < n:
  ch = s[i]

  if escaped:
    out.append(ch)
    escaped = False
    i += 1
    continue

  if ch == "\\":
    out.append(ch)
    escaped = True
    i += 1
    continue

  # handle template literal (backticks) - allow newlines
  if not in_sq and not in_dq and ch == "`":
    in_bt = not in_bt
    out.append(ch)
    i += 1
    continue

  # start/end single/double quote only when NOT in template literal
  if not in_bt:
    if not in_dq and ch == "'" :
      in_sq = not in_sq
      out.append(ch)
      i += 1
      continue
    if not in_sq and ch == '"':
      in_dq = not in_dq
      out.append(ch)
      i += 1
      continue

  # if we're inside single/double quote, raw newline is illegal -> escape it
  if (in_sq or in_dq) and (ch == "\n" or ch == "\r"):
    # normalize CRLF/CR to \n
    if ch == "\r":
      # if next is \n, consume it
      if i + 1 < n and s[i+1] == "\n":
        i += 1
    out.append("\\n")
    fixes += 1
    i += 1
    continue

  out.append(ch)
  i += 1

new = "".join(out)
p.write_text(new, encoding="utf-8")
print("[OK] sanitized bundle newlines-in-strings fixes=", fixes, "bytes=", p.stat().st_size)
PY

echo "== node --check bundle =="
node --check "$B" && echo "[OK] bundle syntax OK"

echo "== DONE =="
echo "[NEXT] restart 8910 + Ctrl+Shift+R"
