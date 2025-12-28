#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
TS="$(date +%Y%m%d_%H%M%S)"

APP="vsp_demo_app.py"
[ -f "$APP" ] || { echo "[ERR] missing $APP"; exit 2; }
cp -f "$APP" "$APP.bak_rid_fallback_${TS}" && echo "[BACKUP] $APP.bak_rid_fallback_${TS}"

python3 - <<'PY'
from pathlib import Path
import re
p=Path("vsp_demo_app.py")
s=p.read_text(encoding="utf-8", errors="ignore")
MARK="### VSP_RID_FALLBACK_FS_V1 ###"
if MARK in s:
    print("[SKIP] marker already present")
    raise SystemExit(0)

m = re.search(r"(?m)^\s*if\s+__name__\s*==\s*['\"]__main__['\"]\s*:", s)
inject_point = m.start() if m else len(s)

block = f"""
\n{MARK}
# commercial: RID fallback by filesystem when runs_index/dashboard returns null
import glob, os, json
from flask import jsonify, request

def _vsp_scan_latest_run_dirs(limit=50):
    pats = [
      "/home/test/Data/*/out_ci/VSP_CI_*",
      "/home/test/Data/*/out/VSP_CI_*",
      "/home/test/Data/SECURITY_BUNDLE/out_ci/VSP_CI_*",
      "/home/test/Data/SECURITY-10-10-v4/out_ci/VSP_CI_*",
    ]
    cands=[]
    for pat in pats:
        for d in glob.glob(pat):
            if os.path.isfile(os.path.join(d, "findings_unified.json")):
                try:
                    cands.append((os.path.getmtime(d), d))
                except Exception:
                    pass
    cands.sort(reverse=True)
    out=[]
    for _, d in cands[:max(1, int(limit))]:
        out.append({{
          "run_id": os.path.basename(d),
          "ci_run_dir": d,
          "has_findings_unified": True,
        }})
    return out

@app.get("/api/vsp/runs_index_safe_v1")
def api_vsp_runs_index_safe_v1():
    limit = int(request.args.get("limit","20"))
    items = _vsp_scan_latest_run_dirs(limit=limit)
    return jsonify({{"ok": True, "items": items, "items_n": len(items)}}), 200

@app.get("/api/vsp/latest_rid_v1")
def api_vsp_latest_rid_v1():
    items = _vsp_scan_latest_run_dirs(limit=1)
    if not items:
        return jsonify({{"ok": False, "error":"no_runs_found"}}), 200
    return jsonify({{"ok": True, "run_id": items[0]["run_id"], "ci_run_dir": items[0]["ci_run_dir"]}}), 200
"""
s2 = s[:inject_point] + block + "\n" + s[inject_point:]
p.write_text(s2, encoding="utf-8")
print("[OK] injected FS RID fallback endpoints")
PY

# Patch rid state JS to fallback to latest_rid_v1 if runs_index returns null/empty
JS="static/js/vsp_rid_state_v1.js"
if [ -f "$JS" ]; then
  cp -f "$JS" "$JS.bak_fallback_${TS}" && echo "[BACKUP] $JS.bak_fallback_${TS}"
  python3 - <<'PY'
from pathlib import Path
import re
p=Path("static/js/vsp_rid_state_v1.js")
s=p.read_text(encoding="utf-8", errors="ignore")
MARK="VSP_RID_STATE_FS_FALLBACK_V1"
if MARK in s:
    print("[SKIP] rid_state fallback already present")
    raise SystemExit(0)

# naive: after fetching runs_index json, if (!data || !data.items || !data.items.length) -> fetch latest_rid_v1
pat = r"(await\s+fetch\([^;]+runs_index_v3_fs_resolved[^;]+\)\s*;)"
if "runs_index_v3_fs_resolved" in s:
    # inject helper once
    helper = f"""
/* {MARK}: fallback RID from /api/vsp/latest_rid_v1 when runs_index/dashboard returns null */
async function __vspPickLatestRidFallback() {{
  try {{
    const r = await fetch("/api/vsp/latest_rid_v1");
    const j = await r.json();
    return (j && j.ok && j.run_id) ? j.run_id : null;
  }} catch(e) {{
    console.warn("[RID_FALLBACK] err", e);
    return null;
  }}
}}
"""
    s = helper + "\n" + s

    # inject into any "pick latest rid" logic: if json null -> fallback
    # best-effort: add a guard on ".items[0].run_id" access
    s = re.sub(r"(\.items\s*\[\s*0\s*\]\.run_id)", r"($1)", s)
    # add fallback near first occurrence of "items[0].run_id"
    s = re.sub(r"(const\s+latestRid\s*=\s*)([^;]*items\s*\[\s*0\s*\]\.run_id[^;]*);",
               r"\1\2;\n  if(!latestRid){ latestRid = await __vspPickLatestRidFallback(); }",
               s, count=1)

p.write_text(s, encoding="utf-8")
print("[OK] patched rid_state with FS fallback")
PY
  node --check "$JS" >/dev/null && echo "[OK] node --check rid_state OK"
else
  echo "[WARN] missing $JS (skip rid_state patch)"
fi

python3 -m py_compile vsp_demo_app.py
echo "[OK] py_compile OK"
echo "[DONE] patch_rid_fallback_fs_v1"
