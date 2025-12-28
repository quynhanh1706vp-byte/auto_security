#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="bin/vsp_iso_evidence_pack_p4_v1.sh"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_envfix_${TS}"
echo "[BACKUP] $F.bak_envfix_${TS}"

python3 - <<'PY'
from pathlib import Path
p=Path("bin/vsp_iso_evidence_pack_p4_v1.sh")
s=p.read_text(encoding="utf-8", errors="replace")

MARK="VSP_ISO_ENVFIX_P0_V1"
if MARK in s:
    print("[OK] already patched:", MARK)
    raise SystemExit(0)

# insert ISO_DIR + export before python block
needle="echo \"[RUN_DIR]=$RUN_DIR\""
ins = needle + "\n" + \
      "\n# " + MARK + "\n" + \
      "ISO_DIR=\"$RUN_DIR/report/__meta/iso\"\n" + \
      "mkdir -p \"$ISO_DIR\"\n" + \
      "export RID RUN_DIR ISO_DIR\n"

if needle not in s:
    raise SystemExit("[ERR] cannot find insertion point")

s=s.replace(needle, ins, 1)
p.write_text(s, encoding="utf-8")
print("[OK] patched:", MARK)
PY

echo "== bash -n =="
bash -n "$F"
echo "[OK] envfix applied"
