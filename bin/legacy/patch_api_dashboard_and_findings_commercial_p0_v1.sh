#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

PYF="vsp_demo_app.py"
TS="$(date +%Y%m%d_%H%M%S)"
[ -f "$PYF" ] || { echo "[ERR] missing $PYF"; exit 2; }

cp -f "$PYF" "$PYF.bak_dash_find_${TS}"
echo "[BACKUP] $PYF.bak_dash_find_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("vsp_demo_app.py")
s=p.read_text(encoding="utf-8", errors="replace")

MARK="VSP_API_DASH_FIND_COMMERCIAL_P0_V1"
if MARK in s:
    print("[OK] already patched:", MARK)
    raise SystemExit(0)

# append-safe: do not break existing routes
addon = r'''
# -------------------- {MARK} --------------------
# Commercial read-only APIs for UI:
#  - /api/vsp/findings_latest_v1  (returns top N findings from latest run report/findings.json)
#  - /api/vsp/dashboard_commercial_v1 (build KPI from findings + gate summaries)
try:
    from flask import jsonify, request
except Exception:
    pass

def _vsp_allowed_prefixes():
    return [
        "/home/test/Data/SECURITY-10-10-v4/out_ci",
        "/home/test/Data/SECURITY_BUNDLE/out",
        "/home/test/Data/SECURITY_BUNDLE/ui/out_ci",
    ]

def _vsp_pick_latest_run_dir():
    import os, glob
    cands=[]
    for base in _vsp_allowed_prefixes():
        if not os.path.isdir(base): 
            continue
        # prefer CI RID style, but accept RUN_ too
        for pat in ("VSP_CI_*", "*RUN_*"):
            for d in glob.glob(os.path.join(base, pat)):
                if os.path.isdir(d):
                    try:
                        cands.append((os.path.getmtime(d), d))
                    except Exception:
                        pass
    cands.sort(reverse=True)
    return cands[0][1] if cands else ""

def _vsp_safe_run_dir(rd: str) -> str:
    import os
    if not rd:
        return ""
    rd=os.path.realpath(rd)
    if not os.path.isdir(rd):
        return ""
    ok=False
    for pref in _vsp_allowed_prefixes():
        pref=os.path.realpath(pref)
        if rd.startswith(pref + os.sep) or rd == pref:
            ok=True
            break
    return rd if ok else ""

def _vsp_read_json(path: str):
    import json
    with open(path, "r", encoding="utf-8", errors="replace") as f:
        return json.load(f)

def _vsp_find_report_files(run_dir: str):
    import os
    rep=os.path.join(run_dir, "report")
    f_find=os.path.join(rep, "findings.json")
    f_gate=os.path.join(run_dir, "run_gate_summary.json")
    if not os.path.isfile(f_gate):
        f_gate=os.path.join(run_dir, "run_gate.json")
    return {"report_dir": rep, "findings_json": f_find, "gate_json": f_gate}

@app.get("/api/vsp/findings_latest_v1")
def vsp_findings_latest_v1():
    import os
    rd = request.args.get("run_dir", "").strip()
    rd = _vsp_safe_run_dir(rd) or _vsp_pick_latest_run_dir()
    rd = _vsp_safe_run_dir(rd)
    if not rd:
        return jsonify({"ok":False, "error":"NO_RUN_DIR"}), 404

    limit = int(request.args.get("limit", "200") or "200")
    limit = max(10, min(limit, 2000))

    files=_vsp_find_report_files(rd)
    fp=files["findings_json"]
    if not os.path.isfile(fp):
        # fallback to findings_unified.json if report not materialized
        alt=os.path.join(rd, "reports", "findings_unified.json")
        if os.path.isfile(alt):
            fp=alt
        else:
            return jsonify({"ok":False, "run_dir":rd, "error":"MISSING_FINDINGS_JSON"}), 404

    try:
        j=_vsp_read_json(fp)
    except Exception as e:
        return jsonify({"ok":False, "run_dir":rd, "error":"BAD_JSON", "detail":str(e)}), 500

    items = j.get("items") if isinstance(j, dict) else (j if isinstance(j, list) else [])
    if items is None: items=[]
    out_items = items[:limit]
    return jsonify({
        "ok": True,
        "run_dir": rd,
        "source": fp,
        "limit": limit,
        "total_items": len(items),
        "items": out_items,
    })

@app.get("/api/vsp/dashboard_commercial_v1")
def vsp_dashboard_commercial_v1():
    import os
    rd = request.args.get("run_dir", "").strip()
    rd = _vsp_safe_run_dir(rd) or _vsp_pick_latest_run_dir()
    rd = _vsp_safe_run_dir(rd)
    if not rd:
        return jsonify({"ok":False, "error":"NO_RUN_DIR"}), 404

    files=_vsp_find_report_files(rd)
    sev_counts={"CRITICAL":0,"HIGH":0,"MEDIUM":0,"LOW":0,"INFO":0,"TRACE":0,"total":0}
    tools=set()

    # findings -> severity counts
    fp=files["findings_json"]
    if not os.path.isfile(fp):
        alt=os.path.join(rd, "reports", "findings_unified.json")
        if os.path.isfile(alt): fp=alt

    degraded=[]
    if os.path.isfile(fp):
        try:
            j=_vsp_read_json(fp)
            items = j.get("items") if isinstance(j, dict) else (j if isinstance(j, list) else [])
            if items is None: items=[]
            for it in items:
                sev=str((it.get("severity") or it.get("sev") or "")).upper()
                if sev in sev_counts:
                    sev_counts[sev]+=1
                    sev_counts["total"]+=1
                t=it.get("tool") or it.get("engine")
                if t: tools.add(str(t))
        except Exception:
            degraded.append("findings_parse")
    else:
        degraded.append("findings_missing")

    # gate summary (best-effort)
    gate={}
    gp=files["gate_json"]
    if os.path.isfile(gp):
        try:
            gate=_vsp_read_json(gp) or {}
        except Exception:
            degraded.append("gate_parse")
    else:
        degraded.append("gate_missing")

    overall = {
        "rid": os.path.basename(rd),
        "run_dir": rd,
        "verdict": gate.get("overall_verdict") or gate.get("verdict") or gate.get("status") or "N/A",
        "severity": sev_counts,
        "degraded": degraded,
    }

    return jsonify({
        "ok": True,
        "overall": overall,
        "gate": gate,
        "tools": sorted(list(tools)),
        "source": {"findings": fp if os.path.isfile(fp) else "", "gate": gp if os.path.isfile(gp) else ""},
    })
# ------------------ end {MARK} ------------------
'''.replace("{MARK}", MARK)

# append near end, before `if __name__ == "__main__":` if exists
m=re.search(r"if\s+__name__\s*==\s*['\"]__main__['\"]\s*:", s)
if m:
    s2 = s[:m.start()] + addon + "\n\n" + s[m.start():]
else:
    s2 = s + "\n\n" + addon

p.write_text(s2, encoding="utf-8")
print("[OK] appended:", MARK)
PY

python3 -m py_compile "$PYF"
bash /home/test/Data/SECURITY_BUNDLE/ui/bin/restart_ui_8910_hardreset_p0_v1.sh

echo "== self-check new APIs =="
BASE="http://127.0.0.1:8910"
curl -sS "$BASE/api/vsp/dashboard_commercial_v1" | head -c 240; echo
curl -sS "$BASE/api/vsp/findings_latest_v1?limit=5" | head -c 240; echo

echo "[NEXT] Ctrl+Shift+R on /vsp4 → Dashboard KPI should be non-zero + Data Source table should fill."
