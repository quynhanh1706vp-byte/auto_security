#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE

F="bin/run_all_tools_v2.sh"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_gatepolicystub2_${TS}"
echo "[BACKUP] $F.bak_gatepolicystub2_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("bin/run_all_tools_v2.sh")
s=p.read_text(encoding="utf-8", errors="ignore")

m=re.search(r"# === VSP_GATEPOLICY_STUB_V1.*?# === /VSP_GATEPOLICY_STUB_V1 ===", s, re.S)
if not m:
    print("[ERR] cannot find VSP_GATEPOLICY_STUB_V1 block")
    raise SystemExit(2)

blk=m.group(0)

# Replace OUT_DIR gating with GP_OUT=(OUT_DIR or RUN_DIR)
blk2=blk
blk2=re.sub(
    r'if \[ -n "\$\{OUT_DIR:-\}" \ ] && \[ -d "\$\{OUT_DIR:-\}" \ ]; then',
    'GP_OUT="${OUT_DIR:-${RUN_DIR:-}}"\nif [ -n "${GP_OUT:-}" ] && [ -d "${GP_OUT:-}" ]; then',
    blk2
)

# Replace $OUT_DIR/ with $GP_OUT/
blk2=blk2.replace('$OUT_DIR/', '$GP_OUT/')

# Also in python snippet: read OUT_DIR env → GP_OUT env
blk2=blk2.replace('out_dir=os.environ.get("OUT_DIR")', 'out_dir=os.environ.get("GP_OUT") or os.environ.get("OUT_DIR")')

s2=s[:m.start()]+blk2+s[m.end():]
p.write_text(s2, encoding="utf-8")
print("[OK] patched stub to use GP_OUT=(OUT_DIR or RUN_DIR)")
PY

bash -n "$F" && echo "[OK] bash -n OK"
