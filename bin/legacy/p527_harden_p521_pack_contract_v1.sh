#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="bin/p521_commercial_release_pack_v2.sh"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_p527_${TS}"
echo "[OK] backup => ${F}.bak_p527_${TS}"

python3 - <<'PY'
from pathlib import Path
import re
p=Path("bin/p521_commercial_release_pack_v2.sh")
s=p.read_text(encoding="utf-8", errors="replace")

marker="P527_PACK_CONTRACT_GATE_V1"
if marker in s:
    print("[OK] already hardened")
    raise SystemExit(0)

# Insert right BEFORE: cd "$OUT_DIR" / tar -czf ...
pat=r'\n# 5\) Build tgz \+ sha256\s*\ncd "\$OUT_DIR"\n'
m=re.search(pat,s)
if not m:
    raise SystemExit("[ERR] cannot find insertion point in P521")

gate=r'''
# === P527_PACK_CONTRACT_GATE_V1: refuse to pack if missing required files ===
req_in_stage=(
  "$STAGE/config/systemd_unit.template"
  "$STAGE/config/logrotate_vsp-ui.template"
  "$STAGE/config/production.env"
)
for rf in "${req_in_stage[@]}"; do
  if [ ! -f "$rf" ]; then
    echo "[FAIL] missing required in stage: $rf" >&2
    echo "[HINT] ensure config/production.env exists AND templates written before tar" >&2
    find "$STAGE" -maxdepth 3 -type f | head -n 120 >&2 || true
    exit 2
  fi
done
echo "[OK] pack contract satisfied (templates + production.env present)"
# === end P527 gate ===
'''
s2=s[:m.start()]+"\n"+gate+"\n"+s[m.start():]
p.write_text(s2, encoding="utf-8")
print("[OK] hardened P521 with pack contract gate")
PY

bash -n bin/p521_commercial_release_pack_v2.sh
echo "[OK] bash -n passed"
