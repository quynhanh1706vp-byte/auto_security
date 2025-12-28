#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need grep
command -v systemctl >/dev/null 2>&1 || true

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
TS="$(date +%Y%m%d_%H%M%S)"

echo "== [0] find templates mentioning data_source + vsp_data_source_lazy_v1.js =="
TPL="$(python3 - <<'PY'
from pathlib import Path
root = Path("templates")
cands=[]
if root.exists():
  for p in root.rglob("*.html"):
    s = p.read_text(encoding="utf-8", errors="ignore")
    if "data_source" in s and "vsp_data_source_lazy_v1.js" in s:
      cands.append(str(p))
print(cands[0] if cands else "")
PY
)"
[ -n "$TPL" ] || { echo "[ERR] cannot locate data_source template that includes vsp_data_source_lazy_v1.js"; exit 2; }
echo "[OK] template=$TPL"

cp -f "$TPL" "${TPL}.bak_bsfix_${TS}"
echo "[BACKUP] ${TPL}.bak_bsfix_${TS}"

python3 - <<'PY'
import os, re
from pathlib import Path

tpl = Path(os.environ["TPL"])
s = tpl.read_text(encoding="utf-8", errors="replace")

# Replace any accidental backslash right after js filename (or before closing quote)
# Examples: vsp_data_source_lazy_v1.js\  OR  vsp_data_source_lazy_v1.js\/
s2 = re.sub(r"(vsp_data_source_lazy_v1\.js)\\+","\\1", s)

if s2 == s:
  print("[WARN] no backslash pattern found; leaving template unchanged")
else:
  tpl.write_text(s2, encoding="utf-8")
  print("[OK] removed stray backslash in JS URL include")
PY

systemctl restart "$SVC" 2>/dev/null || true
echo "[DONE] data_source template cleaned"
