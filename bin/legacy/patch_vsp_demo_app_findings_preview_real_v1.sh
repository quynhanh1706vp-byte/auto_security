#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_findings_preview_real_${TS}"
echo "[BACKUP] $F.bak_findings_preview_real_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("vsp_demo_app.py")
t = p.read_text(encoding="utf-8", errors="ignore")

TAG = "# === VSP_FINDINGS_PREVIEW_V1_REAL_V1 ==="
if TAG in t:
    print("[OK] already patched, skip")
    raise SystemExit(0)

block = r'''
# === VSP_FINDINGS_PREVIEW_V1_REAL_V1 ===
# Real implementation for UI Data Source (commercial)
import os, json
from pathlib import Path as _Path

def _vsp_norm_rid(rid: str) -> str:
    rid = (rid or "").strip()
    if rid.startswith("RUN_"):
        rid = rid[4:]
    return rid

def _vsp_guess_ci_dir(rid: str) -> str:
    rid = _vsp_norm_rid(rid)
    roots = [
        os.environ.get("VSP_OUT_CI_ROOT", "").strip(),
        "/home/test/Data/SECURITY-10-10-v4/out_ci",
        "/home/test/Data/SECURITY_BUNDLE/ui/out_ci",
        "/home/test/Data/SECURITY_BUNDLE/out_ci",
        "/home/test/Data/SECURITY_BUNDLE/out",
    ]
    for r in roots:
        if not r: 
            continue
        cand = _Path(r) / rid
        if cand.is_dir():
            return str(cand)
    # last resort: search (bounded)
    for r in roots:
        if not r: 
            continue
        base = _Path(r)
        if not base.is_dir():
            continue
        try:
            cand = next(base.glob(f"**/{rid}"))
            if cand.is_dir():
                return str(cand)
        except Exception:
            pass
    return ""

def _vsp_load_findings(ci_dir: str) -> tuple[list, str, str]:
    if not ci_dir:
        return [], "", "ci_dir_not_found"
    c = _Path(ci_dir)
    candidates = [
        c / "reports" / "findings_unified.json",
        c / "findings_unified.json",
        c / "reports" / "findings_unified.jsonl",
        c / "findings_unified.jsonl",
    ]
    for fp in candidates:
        if not fp.is_file():
            continue
        try:
            raw = fp.read_text(encoding="utf-8", errors="ignore").strip()
            if not raw:
                return [], str(fp), "empty_file"
            data = json.loads(raw)
            if isinstance(data, list):
                return data, str(fp), ""
            if isinstance(data, dict):
                items = data.get("items") or []
                if isinstance(items, list):
                    return items, str(fp), ""
            return [], str(fp), "unexpected_json_shape"
        except Exception as e:
            return [], str(fp), f"json_parse_error:{type(e).__name__}"
    return [], "", "findings_file_not_found"

def _vsp_match(item: dict, sev: str, tool: str, cwe: str, q: str, show_suppressed: bool) -> bool:
    if not isinstance(item, dict):
        return False
    if not show_suppressed:
        if item.get("suppressed") is True:
            return False
        if str(item.get("status","")).upper() in ("SUPPRESSED","IGNORE","IGNORED"):
            return False
    if sev:
        s = str(item.get("severity","")).upper()
        if s != sev:
            return False
    if tool:
        tl = str(item.get("tool","")).lower()
        if tl != tool.lower():
            return False
    if cwe:
        cw = str(item.get("cwe",""))
        if cw != cwe:
            return False
    if q:
        qq = q.lower()
        hay = " | ".join([
            str(item.get("title","")),
            str(item.get("file","")),
            str(item.get("rule","")),
            str(item.get("tool","")),
            str(item.get("cwe","")),
        ]).lower()
        if qq not in hay:
            return False
    return True

# NOTE: define both PATH + query styles
@app.route("/api/vsp/findings_preview_v1/<path:rid>")
@app.route("/api/vsp/findings_preview_v1", defaults={"rid": None})
def api_vsp_findings_preview_v1_real(rid=None):
    try:
        rid = rid or request.args.get("rid") or request.args.get("run_id") or request.args.get("request_id") or ""
        rid = str(rid).strip()
        if not rid:
            return jsonify(ok=False, total=None, items_n=None, warning="missing_rid", file=None, items=None)

        sev = (request.args.get("sev") or request.args.get("severity") or "").strip().upper()
        tool = (request.args.get("tool") or "").strip()
        cwe  = (request.args.get("cwe")  or "").strip()
        q    = (request.args.get("q") or request.args.get("text") or "").strip()
        show_supp = str(request.args.get("show_suppressed","0")).lower() in ("1","true","yes","on")

        try:
            limit = int(request.args.get("limit","200"))
        except Exception:
            limit = 200
        try:
            offset = int(request.args.get("offset","0"))
        except Exception:
            offset = 0
        limit = max(1, min(limit, 2000))
        offset = max(0, offset)

        # prefer ci_run_dir from run_status_v2 if available
        ci_dir = ""
        try:
            st = api_vsp_run_status_v2_winlast_v6(rid)  # may exist in your codebase
            # if Flask Response, ignore; if dict, use
            if isinstance(st, dict):
                ci_dir = st.get("ci_run_dir") or ""
        except Exception:
            pass

        if not ci_dir:
            ci_dir = _vsp_guess_ci_dir(rid)

        items, fp, warn = _vsp_load_findings(ci_dir)
        flt = [it for it in items if _vsp_match(it, sev, tool, cwe, q, show_supp)]
        total = len(flt)
        page = flt[offset:offset+limit]

        return jsonify(ok=True, total=total, items_n=len(page), warning=(warn or None), file=(fp or None), items=page)
    except Exception as e:
        return jsonify(ok=False, total=None, items_n=None, warning=f"exception:{type(e).__name__}", file=None, items=None)
'''

# insert before main guard if exists, else append
m = re.search(r'(?m)^\s*if\s+__name__\s*==\s*[\'"]__main__[\'"]\s*:', t)
if m:
    t2 = t[:m.start()] + "\n" + block + "\n" + t[m.start():]
else:
    t2 = t + "\n" + block + "\n"

p.write_text(t2, encoding="utf-8")
print("[OK] inserted REAL findings_preview_v1 into vsp_demo_app.py")
PY

python3 -m py_compile vsp_demo_app.py
echo "[OK] py_compile vsp_demo_app.py"

# restart 8910
/home/test/Data/SECURITY_BUNDLE/ui/bin/restart_8910_gunicorn_commercial_v5.sh || true

# verify using RID from index
RID="$(curl -sS 'http://127.0.0.1:8910/api/vsp/runs_index_v3_fs_resolved?limit=1&hide_empty=0&filter=1' | jq -er '.items[0].run_id')"
RN="$(curl -sS "http://127.0.0.1:8910/api/vsp/run_status_v2/$RID" | jq -r '.rid_norm // empty')"
echo "RID=$RID"
echo "RID_NORM=$RN"

echo "== probe findings (RID) =="
curl -sS "http://127.0.0.1:8910/api/vsp/findings_preview_v1/${RID}?limit=3" | jq '{ok,total,items_n,warning,file}'
echo "== probe findings (RID_NORM) =="
curl -sS "http://127.0.0.1:8910/api/vsp/findings_preview_v1/${RN}?limit=3" | jq '{ok,total,items_n,warning,file}'
