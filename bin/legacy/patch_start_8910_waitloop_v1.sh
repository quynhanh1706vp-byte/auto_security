#!/usr/bin/env bash
set -euo pipefail

F="/home/test/Data/SECURITY_BUNDLE/ui/bin/start_8910.sh"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_waitloop_${TS}"
echo "[BACKUP] $F.bak_waitloop_${TS}"

python3 - "$F" <<'PY'
import sys, re
from pathlib import Path

p = Path(sys.argv[1])
txt = p.read_text(encoding="utf-8", errors="ignore")

if "VSP_START_8910_WAITLOOP_V1" in txt:
    print("[OK] already patched.")
    raise SystemExit(0)

# Append a wait loop at the end (safe)
addon = r'''
# === VSP_START_8910_WAITLOOP_V1 ===
# Wait up to 10s for port to open; if fail, print last traceback lines.
ok="0"
for i in 1 2 3 4 5 6 7 8 9 10; do
  if curl -sS -o /dev/null "http://localhost:8910/" ; then
    ok="1"
    break
  fi
  sleep 1
done

if [ "$ok" != "1" ]; then
  echo "[ERR] 8910 not responding after 10s. Showing last 120 lines of out_ci/ui_8910.log"
  tail -n 120 "/home/test/Data/SECURITY_BUNDLE/ui/out_ci/ui_8910.log" 2>/dev/null || true
  exit 1
fi
# === END VSP_START_8910_WAITLOOP_V1 ===
'''.lstrip("\n")

p.write_text(txt.rstrip() + "\n\n" + addon + "\n", encoding="utf-8")
print("[OK] patched start_8910.sh with waitloop V1")
PY

chmod +x "$F"
echo "[OK] chmod +x $F"
