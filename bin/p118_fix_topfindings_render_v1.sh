#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need curl; need python3; need date; need head; need sed

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
RID="${1:-}"

if [ -z "$RID" ]; then
  RID="$(curl -fsS "$BASE/api/ui/runs_v3?limit=1&include_ci=1" \
    | python3 -c 'import sys,json; j=json.load(sys.stdin); print(j["items"][0]["rid"])')"
fi

echo "[INFO] RID=$RID"

echo "== [A] probe top_findings_v2 raw keys =="
curl -fsS "$BASE/api/vsp/top_findings_v2?limit=20&rid=$RID" \
 | python3 - <<'PY'
import sys,json
j=json.load(sys.stdin)
print("keys=",sorted(j.keys())[:60])
for k in ["items","rows","data","result","findings"]:
    v=j.get(k)
    if isinstance(v,list):
        print("list_field=",k,"len=",len(v))
        if v:
            print("sample_keys=",sorted(v[0].keys())[:40])
        break
else:
    # maybe top-level is list
    if isinstance(j,list):
        print("top_level_list len=",len(j))
        if j: print("sample_keys=",sorted(j[0].keys())[:40])
    else:
        print("no obvious list field; type=",type(j).__name__)
PY

# Patch JS to be more robust (just the extraction + message fix)
F="static/js/vsp_c_dashboard_v1.js"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }
TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_p118_${TS}"
echo "[OK] backup: ${F}.bak_p118_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("static/js/vsp_c_dashboard_v1.js")
s=p.read_text(encoding="utf-8", errors="replace")

# 1) fix placeholder text "No TopCWE data" in Top Findings render
s = s.replace("No TopCWE data", "No findings")

# 2) make top findings list extraction try more fields
# replace: const items = top.json.items ?? top.json.data ?? top.json.rows ?? [];
pat = re.compile(r'const items\s*=\s*top\.json\.items\s*\?\?\s*top\.json\.data\s*\?\?\s*top\.json\.rows\s*\?\?\s*\[\]\s*;')
if pat.search(s):
    s = pat.sub(
        "const items = top.json.items ?? top.json.rows ?? top.json.data ?? top.json.result ?? top.json.findings ?? (Array.isArray(top.json)?top.json:[]) ?? [];",
        s, count=1
    )
else:
    # try a looser replace for older variants
    s = s.replace(
        "const items = top.json.items ?? top.json.data ?? top.json.rows ?? [];",
        "const items = top.json.items ?? top.json.rows ?? top.json.data ?? top.json.result ?? top.json.findings ?? (Array.isArray(top.json)?top.json:[]) ?? [];"
    )

# 3) ensure normalizeFinding uses common keys (title/tool/file)
# If already good, no-op.
p.write_text(s, encoding="utf-8")
print("[OK] patched vsp_c_dashboard_v1.js (P118 robust list + message)")
PY

echo "[OK] done. Now hard refresh: Ctrl+Shift+R"
