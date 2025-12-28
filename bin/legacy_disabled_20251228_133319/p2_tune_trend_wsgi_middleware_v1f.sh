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
cp -f "$W" "${W}.bak_trend_v1f_${TS}"
echo "[BACKUP] ${W}.bak_trend_v1f_${TS}"

python3 - "$W" <<'PY'
from pathlib import Path
import re, sys

p = Path(sys.argv[1])
s = p.read_text(encoding="utf-8", errors="replace")

if "VSP_P2_WSGI_TREND_OVERRIDE_V1E" not in s:
    print("[ERR] missing V1E marker in wsgi file (install V1E first)")
    raise SystemExit(2)

if "VSP_P2_WSGI_TREND_TUNE_V1F" in s:
    print("[OK] V1F already applied; skip")
    raise SystemExit(0)

# Patch inside the V1E middleware class:
# 1) strengthen _total_from_gate
s2 = s

# Replace the existing _total_from_gate method body with a stronger one (best-effort regex).
pat_total = re.compile(r'(?s)def _total_from_gate\(self,\s*j\):\s*.*?return None\s*', re.M)
m = pat_total.search(s2)
if not m:
    print("[ERR] cannot find _total_from_gate in V1E block")
    raise SystemExit(2)

new_total = r'''def _total_from_gate(self, j):
            # VSP_P2_WSGI_TREND_TUNE_V1F: support gate schema (counts_total, overall, maps)
            if not isinstance(j, dict):
                return None

            # direct ints (your run_gate_summary has counts_total)
            for k in ("counts_total", "total", "total_findings", "findings_total", "total_unified"):
                v = j.get(k)
                if isinstance(v, int):
                    return v

            # nested overall
            ov = j.get("overall")
            if isinstance(ov, dict):
                for k in ("counts_total", "total", "total_findings"):
                    v = ov.get(k)
                    if isinstance(v, int):
                        return v

            # maps: by_severity / counts / severity_counts / by_tool_severity
            for mk in ("by_severity", "counts", "severity_counts", "counts_by_severity"):
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

            # sometimes gate has by_tool -> per tool counts dict
            bt = j.get("by_tool")
            if isinstance(bt, dict):
                sm = 0
                hit = False
                for toolv in bt.values():
                    if isinstance(toolv, dict):
                        for kk in ("counts_total","total"):
                            vv = toolv.get(kk)
                            if isinstance(vv, int):
                                sm += vv
                                hit = True
                                break
                if hit:
                    return sm

            return None
'''
s2 = s2[:m.start()] + new_total + s2[m.end():]

# 2) Add filtering in _list_run_dirs: keep commercial-ish runs
pat_list = re.compile(r'(?s)def _list_run_dirs\(self,\s*limit:\s*int\):.*?return dirs\[:\s*max\(limit\*3,\s*limit\)\]\s*', re.M)
m2 = pat_list.search(s2)
if not m2:
    print("[ERR] cannot find _list_run_dirs in V1E block")
    raise SystemExit(2)

new_list = r'''def _list_run_dirs(self, limit: int):
            # VSP_P2_WSGI_TREND_TUNE_V1F: filter to commercial-ish run ids
            roots = ["/home/test/Data/SECURITY_BUNDLE/out_ci", "/home/test/Data/SECURITY_BUNDLE/out"]
            roots = [r for r in roots if os.path.isdir(r)]
            dirs = []
            for r in roots:
                try:
                    for name in os.listdir(r):
                        # keep only VSP CI / VSP full runs (clean chart)
                        if not (name.startswith("VSP_CI_") or name.startswith("RUN_VSP_")):
                            continue
                        full = os.path.join(r, name)
                        if os.path.isdir(full):
                            try:
                                mt = os.path.getmtime(full)
                            except Exception:
                                mt = 0
                            dirs.append((mt, name, full))
                except Exception:
                    pass
            dirs.sort(key=lambda x: x[0], reverse=True)
            return dirs[: max(limit*3, limit)]
'''
s2 = s2[:m2.start()] + new_list + s2[m2.end():]

# 3) Add extra fallback to findings_unified_commercial.json in __call__ where it loads fu
# Find the fu load line and extend with commercial json.
s2 = s2.replace(
    'fu = self._load_json(os.path.join(d, "findings_unified.json")) or self._load_json(os.path.join(d, "reports", "findings_unified.json"))',
    'fu = (self._load_json(os.path.join(d, "findings_unified_commercial.json"))\n'
    '                          or self._load_json(os.path.join(d, "findings_unified.json"))\n'
    '                          or self._load_json(os.path.join(d, "reports", "findings_unified.json")))',
    1
)

# 4) If fu is dict and has "total" int, use it; if "findings" empty but "items" exists, use items
insert_pat = re.compile(r'(?s)if total is None:\s*\n\s*fu = .*?\n\s*if isinstance\(fu, list\):\s*\n\s*total = len\(fu\)\s*\n\s*elif isinstance\(fu, dict\) and isinstance\(fu\.get\("findings"\), list\):\s*\n\s*total = len\(fu\.get\("findings"\)\)\s*', re.M)
m3 = insert_pat.search(s2)
if m3:
    repl = r'''if total is None:
                    fu = (self._load_json(os.path.join(d, "findings_unified_commercial.json"))
                          or self._load_json(os.path.join(d, "findings_unified.json"))
                          or self._load_json(os.path.join(d, "reports", "findings_unified.json")))
                    if isinstance(fu, list):
                        total = len(fu)
                    elif isinstance(fu, dict):
                        if isinstance(fu.get("total"), int):
                            total = int(fu.get("total"))
                        elif isinstance(fu.get("findings"), list):
                            total = len(fu.get("findings"))
                        elif isinstance(fu.get("items"), list):
                            total = len(fu.get("items"))
'''
    s2 = s2[:m3.start()] + repl + s2[m3.end():]
else:
    # If structure changed, we already improved load/total_from_gate; leave it.
    pass

# add marker comment once
s2 += "\n# VSP_P2_WSGI_TREND_TUNE_V1F\n"

p.write_text(s2, encoding="utf-8")
print("[OK] applied V1F tune:", p)
PY

python3 -m py_compile "$W"
echo "[OK] py_compile OK"

sudo systemctl restart "$SVC"

RID="$(curl -fsS "$BASE/api/vsp/rid_latest" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("rid",""))')"
echo "[INFO] RID=$RID"
echo "== [SMOKE] trend_v1 sample points (should be cleaner + totals non-zero if available) =="
curl -sS "$BASE/api/vsp/trend_v1?rid=$RID&limit=8" | python3 - <<'PY'
import sys, json
j=json.load(sys.stdin)
print("ok=", j.get("ok"), "marker=", j.get("marker"))
pts=j.get("points") or []
for p in pts[:8]:
    print("-", p.get("run_id"), "total=", p.get("total"))
PY
