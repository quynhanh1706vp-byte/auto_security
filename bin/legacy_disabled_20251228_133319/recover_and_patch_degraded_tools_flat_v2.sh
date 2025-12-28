#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

echo "[STEP 1] Find compilable candidate (current or backups)..."
mapfile -t CANDS < <(ls -1t "$F" "$F".bak_* 2>/dev/null || true)

GOOD=""
for c in "${CANDS[@]}"; do
  if python3 -m py_compile "$c" >/dev/null 2>&1; then
    GOOD="$c"
    break
  fi
done

if [ -z "$GOOD" ]; then
  echo "[ERR] No compilable candidate found among current+backups."
  echo "Candidates:"
  printf ' - %s\n' "${CANDS[@]}" || true
  exit 2
fi

if [ "$GOOD" != "$F" ]; then
  echo "[RECOVER] Restoring $F from $GOOD"
  cp -f "$GOOD" "$F"
fi

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_before_flat_${TS}"
echo "[BACKUP] $F.bak_before_flat_${TS}"

echo "[STEP 2] Patch wrapper: normalize degraded_tools to flat list..."
python3 - <<'PY'
from pathlib import Path
import re

p = Path("vsp_demo_app.py")
txt = p.read_text(encoding="utf-8", errors="ignore")

MARK = "VSP_DEGRADED_TOOLS_FLAT_V2"
if MARK in txt:
    print("[OK] already patched")
    raise SystemExit(0)

# Insert right before: new_resp = jsonify(data)
# Use the same indentation captured from the line.
pat = r"\n(\s*)new_resp\s*=\s*jsonify\(data\)\s*\n"
m = re.search(pat, txt)
if not m:
    raise SystemExit("[ERR] cannot find `new_resp = jsonify(data)` to patch (file differs).")

indent = m.group(1)

block = (
    f"\n{indent}# === {MARK} ===\n"
    f"{indent}dt = data.get('degraded_tools')\n"
    f"{indent}if isinstance(dt, dict) and isinstance(dt.get('items'), list):\n"
    f"{indent}  data['degraded_tools'] = dt['items']\n"
    f"{indent}elif isinstance(dt, list):\n"
    f"{indent}  data['degraded_tools'] = dt\n"
    f"{indent}elif dt is None:\n"
    f"{indent}  data['degraded_tools'] = []\n"
    f"{indent}else:\n"
    f"{indent}  # if some single dict/object slipped in, wrap as 1-item list\n"
    f"{indent}  data['degraded_tools'] = [dt]\n"
    f"{indent}# === END {MARK} ===\n"
)

txt2 = re.sub(pat, block + f"\n{indent}new_resp = jsonify(data)\n", txt, count=1)
p.write_text(txt2, encoding="utf-8")
print("[OK] inserted degraded_tools flatten block")
PY

python3 -m py_compile "$F" >/dev/null
echo "[OK] py_compile OK"

echo "[NEXT] Restart UI:"
echo "  cd /home/test/Data/SECURITY_BUNDLE/ui && ./bin/start_8910_clean_v2.sh"
