#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
APP="vsp_demo_app.py"
PY="/home/test/Data/SECURITY_BUNDLE/ui/.venv/bin/python3"
[ -x "$PY" ] || PY="$(command -v python3)"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need date; need curl; need head

[ -f "$APP" ] || { echo "[ERR] missing $APP"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$APP" "${APP}.bak_dedupe_v3_${TS}"
echo "[BACKUP] ${APP}.bak_dedupe_v3_${TS}"

"$PY" - <<'PY'
from pathlib import Path
import re, py_compile

p=Path("vsp_demo_app.py")
s=p.read_text(encoding="utf-8", errors="replace")

# Canonical list (the ones we care about for CIO v3)
routes = [
  "/api/vsp/dashboard_v3",
  "/api/vsp/rid_latest_v3",
  "/api/vsp/runs_v3",
  "/api/vsp/run_gate_v3",
  "/api/vsp/findings_v3",
  "/api/vsp/artifact_v3",
]
funcs = [
  "api_vsp_dashboard_v3",
  "api_vsp_rid_latest_v3",
  "api_vsp_runs_v3",
  "api_vsp_run_gate_v3",
  "api_vsp_findings_v3",
  "api_vsp_artifact_v3",
]

lines = s.splitlines(True)

def rename_dup_defs(lines, func_name):
    idxs=[]
    pat=re.compile(rf'^(?P<indent>\s*)def\s+{re.escape(func_name)}\s*\(')
    for i,l in enumerate(lines):
        if pat.search(l):
            idxs.append(i)
    if len(idxs) <= 1:
        return 0
    # keep first, rename others
    changed=0
    for k, i in enumerate(idxs[1:], start=1):
        lines[i] = pat.sub(rf'\g<indent>def {func_name}__dup{k}(', lines[i])
        changed += 1
    return changed

def move_dup_routes(lines, route):
    idxs=[]
    # handle @app.get("...") and @app.route("...", methods=[...])
    pat_get=re.compile(r'^(?P<indent>\s*)@app\.get\(\s*(?P<q>[\'"])' + re.escape(route) + r'(?P=q)\s*\)')
    pat_route=re.compile(r'^(?P<indent>\s*)@app\.route\(\s*(?P<q>[\'"])' + re.escape(route) + r'(?P=q)')
    for i,l in enumerate(lines):
        if pat_get.search(l) or pat_route.search(l):
            idxs.append(i)
    if len(idxs) <= 1:
        return 0
    changed=0
    for k, i in enumerate(idxs[1:], start=1):
        # Make URL unique to avoid ambiguous routing, and prevent any endpoint overwrite edge cases
        new_route = route + f"__dup{k}"
        if pat_get.search(lines[i]):
            lines[i] = pat_get.sub(rf'\g<indent>@app.get("\g<indent>".strip() and "{new_route}")', lines[i])  # dummy to keep format
            # The above is messy; do simpler safe replace on the line only:
            lines[i] = lines[i].replace(route, new_route)
        elif pat_route.search(lines[i]):
            lines[i] = lines[i].replace(route, new_route)
        changed += 1
    return changed

changed_total=0
for fn in funcs:
    changed_total += rename_dup_defs(lines, fn)

for rt in routes:
    # find duplicate decorators and rewrite their URL to /api/vsp/...__dupN
    # keep first intact
    # safer: count matches then patch by in-line replace
    hits=[]
    for i,l in enumerate(lines):
        if f'@app.get("{rt}")' in l or f"@app.get('{rt}')" in l or f'@app.route("{rt}"' in l or f"@app.route('{rt}'" in l:
            hits.append(i)
    if len(hits) > 1:
        for k,i in enumerate(hits[1:], start=1):
            lines[i] = lines[i].replace(rt, rt + f"__dup{k}")
            changed_total += 1

s2="".join(lines)

if s2 == s:
    print("[WARN] no dup patterns changed (maybe already fixed or different style).")
else:
    p.write_text(s2, encoding="utf-8")
    print(f"[OK] patched duplicates: changes={changed_total}")

py_compile.compile(str(p), doraise=True)
print("[OK] py_compile ok")
PY

echo "== [RESTART] =="
sudo systemctl restart "$SVC" || {
  echo "[ERR] restart failed; tail error log"
  tail -n 80 /home/test/Data/SECURITY_BUNDLE/ui/out_ci/ui_8910.error.log || true
  exit 3
}
echo "[OK] restarted $SVC"

echo "== [SMOKE] =="
curl -fsS "$BASE/runs" >/dev/null && echo "[OK] /runs"
curl -fsS "$BASE/api/vsp/rid_latest" | head -c 120; echo
# if v3 exists it should respond (even if empty)
curl -fsS "$BASE/api/vsp/dashboard_v3" | head -c 160; echo || echo "[WARN] /api/vsp/dashboard_v3 not reachable"
echo "[DONE]"
