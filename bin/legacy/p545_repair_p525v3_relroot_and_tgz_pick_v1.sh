#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="bin/p525_verify_release_and_customer_smoke_v3.sh"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_p545_${TS}"
echo "[OK] backup => ${F}.bak_p545_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("bin/p525_verify_release_and_customer_smoke_v3.sh")
s = p.read_text(encoding="utf-8", errors="replace")

# Find the point where the script starts printing BASE/latest_dir/tgz
m = re.search(r'^\s*echo\s+"\[P525v3\]\s+BASE=', s, flags=re.M)
if not m:
    raise SystemExit("[ERR] cannot find marker: echo \"[P525v3] BASE=...\"")

tail = s[m.start():]  # keep the rest intact

# Build a clean, correct header (RELROOT default + TGZ_ARG support + tgz picking)
header = """#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

# [P545_REPAIR_P525V3_V1] fix RELROOT nounset + fix tgz picking + accept optional TGZ arg
RELROOT="${RELROOT:-/home/test/Data/SECURITY_BUNDLE/ui/out_ci/releases}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
TS="$(date +%Y%m%d_%H%M%S)"

TGZ_ARG="${1:-}"
if [ -n "$TGZ_ARG" ]; then
  if [ -f "$TGZ_ARG" ]; then
    TGZ_ARG="$(python3 -c 'import os,sys; print(os.path.abspath(sys.argv[1]))' "$TGZ_ARG")"
  else
    echo "[WARN] TGZ_ARG provided but not found: $TGZ_ARG (fallback to latest)" >&2
    TGZ_ARG=""
  fi
fi

latest_dir="$(ls -1dt "$RELROOT"/RELEASE_UI_* 2>/dev/null | head -n1 || true)"
[ -n "$latest_dir" ] || { echo "[FAIL] no RELEASE_UI_* under $RELROOT"; exit 2; }

tgz="$(ls -1 "$latest_dir"/*.tgz 2>/dev/null | head -n1 || true)"
tgz="${TGZ_ARG:-$tgz}"
[ -n "$tgz" ] || { echo "[FAIL] no .tgz found in $latest_dir"; exit 2; }

"""

# Replace everything before the marker with header
s2 = header + tail

# Sanity: ensure we did not accidentally duplicate another shebang later
# (not strictly required, but keeps it clean)
s2 = re.sub(r'(?m)^#!/usr/bin/env bash\s*\n', '#!/usr/bin/env bash\n', s2, count=1)

p.write_text(s2, encoding="utf-8")
print("[OK] repaired header and tgz selection")
PY

bash -n "$F"
echo "[OK] bash -n PASS"
