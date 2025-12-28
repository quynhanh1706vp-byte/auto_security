#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need curl
command -v systemctl >/dev/null 2>&1 || true

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
W="wsgi_vsp_ui_gateway.py"

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$W" "${W}.bak_auditroots_${TS}"
echo "[BACKUP] ${W}.bak_auditroots_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("wsgi_vsp_ui_gateway.py")
s=p.read_text(encoding="utf-8", errors="replace")

if "VSP_P1_AUDIT_PACK_DOWNLOAD_V1" not in s:
    print("[ERR] audit pack marker not found")
    raise SystemExit(2)

# Replace only the _RUN_ROOTS list inside the audit pack block.
# Add /home/test/Data/SECURITY_BUNDLE/out_ci (your CI RID pattern suggests this).
s2 = s
s2 = re.sub(
    r"_RUN_ROOTS\s*=\s*\[\s*Path\(\"/home/test/Data/SECURITY_BUNDLE/out\"\)\s*,\s*Path\(\"/home/test/Data/SECURITY_BUNDLE/ui/out_ci\"\)\s*\]\s*",
    "_RUN_ROOTS = [\n        Path(\"/home/test/Data/SECURITY_BUNDLE/out\"),\n        Path(\"/home/test/Data/SECURITY_BUNDLE/out_ci\"),\n        Path(\"/home/test/Data/SECURITY_BUNDLE/ui/out_ci\"),\n    ]\n",
    s2,
    flags=re.S
)

p.write_text(s2, encoding="utf-8")
print("[OK] audit pack roots patched (added /home/test/Data/SECURITY_BUNDLE/out_ci)")
PY

systemctl restart "$SVC" 2>/dev/null || true

echo "== smoke: resolve RID then GET headers/body head =="
RID="$(curl -fsS "$BASE/api/vsp/runs?limit=1" | python3 -c 'import sys,json; j=json.load(sys.stdin); r=(j.get("runs") or [{}])[0]; print(r.get("rid") or r.get("run_id") or "")')"
echo "[RID]=$RID"
U="$BASE/api/vsp/audit_pack_download?rid=$RID"
H="/tmp/vsp_audit_hdr.$$"
B="/tmp/vsp_audit_body.$$"
curl -sS -D "$H" "$U" -o "$B" || true

echo "-- HEAD (first 25 lines) --"
sed -n '1,25p' "$H" || true
echo "-- BODY bytes --"
python3 - <<PY
import os
print("bytes=", os.path.getsize("$B") if os.path.exists("$B") else -1)
PY
echo "-- If JSON error (show 220 chars) --"
head -c 220 "$B" 2>/dev/null || true; echo

rm -f "$H" "$B" || true
echo "[DONE]"
