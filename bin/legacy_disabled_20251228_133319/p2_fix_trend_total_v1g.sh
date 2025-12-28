#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need date; need python3; need curl; need systemctl

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
W="wsgi_vsp_ui_gateway.py"
[ -f "$W" ] || { echo "[ERR] missing $W"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$W" "${W}.bak_trend_total_v1g_${TS}"
echo "[BACKUP] ${W}.bak_trend_total_v1g_${TS}"

python3 - "$W" <<'PY'
from pathlib import Path
import re, sys, textwrap

p = Path(sys.argv[1])
s = p.read_text(encoding="utf-8", errors="replace")

MARK="VSP_P2_WSGI_TREND_TUNE_V1F2"
if MARK not in s:
    print("[ERR] V1F2 block not found")
    raise SystemExit(2)

if "VSP_P2_TREND_TOTAL_FIX_V1G" in s:
    print("[OK] V1G already applied; skip")
    raise SystemExit(0)

# Patch _total_from_gate inside V1F2 class
pat_gate = re.compile(r'(?s)\n\s*def _total_from_gate\(self, j\):.*?\n\s*return None\n', re.M)
m = pat_gate.search(s)
if not m:
    print("[ERR] cannot locate _total_from_gate")
    raise SystemExit(2)

new_gate = textwrap.dedent(r'''
        def _total_from_gate(self, j):
            # VSP_P2_TREND_TOTAL_FIX_V1G: support counts_total as dict + sum maps
            if not isinstance(j, dict):
                return None

            # direct ints
            for k in ("total", "total_findings", "findings_total", "total_unified"):
                v = j.get(k)
                if isinstance(v, int):
                    return v

            # counts_total can be int OR dict(severity->count)
            ct = j.get("counts_total")
            if isinstance(ct, int):
                return ct
            if isinstance(ct, dict):
                sm = 0
                hit = False
                for vv in ct.values():
                    if isinstance(vv, int):
                        sm += vv
                        hit = True
                if hit:
                    return sm

            ov = j.get("overall")
            if isinstance(ov, dict):
                for k in ("counts_total","total","total_findings"):
                    v = ov.get(k)
                    if isinstance(v, int):
                        return v
                ct2 = ov.get("counts_total")
                if isinstance(ct2, dict):
                    sm = 0
                    hit = False
                    for vv in ct2.values():
                        if isinstance(vv, int):
                            sm += vv
                            hit = True
                    if hit:
                        return sm

            # map sums
            for mk in ("by_severity","counts","severity_counts","counts_by_severity"):
                c = j.get(mk)
                if isinstance(c, dict):
                    sm = 0
                    hit = False
                    for vv in c.values():
                        if isinstance(vv, int):
                            sm += vv
                            hit = True
                    if hit:
                        return sm
            return None
''').rstrip() + "\n"
s = s[:m.start()] + "\n" + new_gate + s[m.end():]

# Patch _total_from_findings inside V1F2 class
pat_fin = re.compile(r'(?s)\n\s*def _total_from_findings\(self, fu\):.*?\n\s*return None\n', re.M)
m2 = pat_fin.search(s)
if not m2:
    print("[ERR] cannot locate _total_from_findings")
    raise SystemExit(2)

new_fin = textwrap.dedent(r'''
        def _total_from_findings(self, fu):
            # VSP_P2_TREND_TOTAL_FIX_V1G: prefer explicit totals / counts_by_severity
            if fu is None:
                return None
            if isinstance(fu, list):
                return len(fu)
            if isinstance(fu, dict):
                # explicit total
                if isinstance(fu.get("total"), int):
                    return int(fu.get("total"))

                # counts_by_severity sum (works even when findings is empty)
                cbs = fu.get("counts_by_severity")
                if isinstance(cbs, dict):
                    sm = 0
                    hit = False
                    for vv in cbs.values():
                        if isinstance(vv, int):
                            sm += vv
                            hit = True
                    if hit:
                        return sm

                # items/findings length (only if non-empty)
                items = fu.get("items")
                if isinstance(items, list) and len(items) > 0:
                    return len(items)
                findings = fu.get("findings")
                if isinstance(findings, list) and len(findings) > 0:
                    return len(findings)

            return None
''').rstrip() + "\n"
s = s[:m2.start()] + "\n" + new_fin + s[m2.end():]

# Add marker comment at end
s += "\n# VSP_P2_TREND_TOTAL_FIX_V1G\n"
p.write_text(s, encoding="utf-8")
print("[OK] applied V1G total fixes in V1F2 block:", p)
PY

python3 -m py_compile "$W"
echo "[OK] py_compile OK"

sudo systemctl restart "$SVC"

RID="$(curl -fsS "$BASE/api/vsp/rid_latest" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("rid",""))')"
echo "[INFO] RID=$RID"
echo "== [SMOKE] trend_v1 (show first 6 points) =="
curl -sS "$BASE/api/vsp/trend_v1?rid=$RID&limit=6" | python3 - <<'PY'
import sys, json
j=json.load(sys.stdin)
print("ok=", j.get("ok"), "marker=", j.get("marker"))
for p in (j.get("points") or [])[:6]:
    print("-", p.get("run_id"), "total=", p.get("total"))
PY
