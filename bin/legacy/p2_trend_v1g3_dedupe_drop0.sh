#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need date; need python3; need curl; need systemctl; need grep

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
W="wsgi_vsp_ui_gateway.py"
[ -f "$W" ] || { echo "[ERR] missing $W"; exit 2; }

# must have V1G2 block present
grep -q "VSP_P2_WSGI_TREND_TOTAL_FIX_V1G2" "$W" || { echo "[ERR] V1G2 not present in $W"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$W" "${W}.bak_trend_v1g3_${TS}"
echo "[BACKUP] ${W}.bak_trend_v1g3_${TS}"

python3 - "$W" <<'PY'
from pathlib import Path
import sys, re

p=Path(sys.argv[1])
s=p.read_text(encoding="utf-8", errors="replace")

if "VSP_P2_TREND_DEDUPE_DROP0_V1G3" in s:
    print("[OK] V1G3 already applied; skip")
    raise SystemExit(0)

# Patch inside V1G2 __call__ loop: normalize run_id + dedupe + drop total==0
# We find the block that appends points and replace it with a safer variant.
needle = 'points.append({"label": label, "run_id": name, "total": int(total), "ts": ts})'
idx = s.find(needle)
if idx < 0:
    print("[ERR] cannot find points.append line in V1G2")
    raise SystemExit(2)

# Insert seen set earlier inside the /api/vsp/trend_v1 handler: right after points=[]
ins_anchor = 'points = []'
idx2 = s.find(ins_anchor)
if idx2 < 0:
    print("[ERR] cannot find points = []")
    raise SystemExit(2)

# only patch within the V1G2 block area near the end by operating on last occurrence
idx2 = s.rfind(ins_anchor)
idx = s.rfind(needle)

s = s[:idx2+len(ins_anchor)] + '\n                seen = set()  # VSP_P2_TREND_DEDUPE_DROP0_V1G3\n' + s[idx2+len(ins_anchor):]

# Replace append line with logic
replacement = r'''
                    # VSP_P2_TREND_DEDUPE_DROP0_V1G3: normalize + dedupe + hide zero totals
                    norm = name
                    if norm.startswith("VSP_CI_RUN_"):
                        norm = "VSP_CI_" + norm[len("VSP_CI_RUN_"):]
                    if int(total) <= 0:
                        continue
                    if norm in seen:
                        continue
                    seen.add(norm)
                    points.append({"label": label, "run_id": norm, "total": int(total), "ts": ts})
'''.strip("\n")

s = s[:idx] + replacement + s[idx+len(needle):]

# Add marker at file end
s += "\n# VSP_P2_TREND_DEDUPE_DROP0_V1G3\n"
p.write_text(s, encoding="utf-8")
print("[OK] applied V1G3: dedupe + drop0")
PY

python3 -m py_compile "$W"
echo "[OK] py_compile OK"

sudo systemctl restart "$SVC"

RID="$(curl -fsS "$BASE/api/vsp/rid_latest" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("rid",""))')"
echo "[INFO] RID=$RID"
echo "== [SMOKE] trend_v1 first 10 points (no dup, no zero) =="
curl -sS "$BASE/api/vsp/trend_v1?rid=$RID&limit=10" | python3 - <<'PY'
import sys,json
j=json.load(sys.stdin)
print("ok=", j.get("ok"), "marker=", j.get("marker"), "points=", len(j.get("points") or []))
for p in (j.get("points") or [])[:10]:
    print("-", p.get("run_id"), "total=", p.get("total"))
PY
