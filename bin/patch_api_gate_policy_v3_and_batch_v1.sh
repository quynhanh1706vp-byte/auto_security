#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_gatev3_${TS}"
echo "[BACKUP] $F.bak_gatev3_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("vsp_demo_app.py")
s=p.read_text(encoding="utf-8", errors="ignore")

if "VSP_GATE_POLICY_V3_BATCH_V1" in s:
    print("[OK] gate v3/batch already patched, skip")
    raise SystemExit(0)

inject = r'''
# === VSP_GATE_POLICY_V3_BATCH_V1 ===
import os, json, glob
from flask import request as _gp_req, jsonify as _gp_jsonify

def _gp_norm_verdict(v):
    if not v: return "UNKNOWN"
    v=str(v).upper()
    if v in ("GREEN","PASS","OK"): return "GREEN"
    if v in ("AMBER","WARN","WARNING"): return "AMBER"
    if v in ("RED","FAIL","FAILED","ERROR"): return "RED"
    return v

def _gp_load_json(path):
    try:
        with open(path,"r",encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return None

def _gp_degraded(run_dir):
    dd=os.path.join(run_dir,"degraded")
    items=[]
    if os.path.isdir(dd):
        for fn in sorted(glob.glob(os.path.join(dd,"*.txt"))):
            items.append(os.path.basename(fn))
    return items

def _gp_pick_run_dir(rid, ci_run_dir=None):
    # deterministic if ci_run_dir provided
    if ci_run_dir and os.path.isdir(ci_run_dir):
        return ci_run_dir
    rid2 = rid[4:] if rid.startswith("RUN_") else rid
    # best-effort fallback (common roots)
    roots = [
        "/home/test/Data/SECURITY-10-10-v4/out_ci",
        "/home/test/Data/SECURITY_BUNDLE/ui/out_ci",
        "/home/test/Data/SECURITY_BUNDLE/out",
    ]
    for root in roots:
        cand=os.path.join(root, rid2)
        if os.path.isdir(cand):
            return cand
    return None

def _gp_build(rid, ci_run_dir=None):
    run_dir=_gp_pick_run_dir(rid, ci_run_dir)
    resp={
        "ok": False,
        "run_id": rid,
        "ci_run_dir": run_dir,
        "verdict": "UNKNOWN",
        "reasons": [],
        "degraded_items": [],
        "degraded_n": 0,
        "source": None,
    }
    if not run_dir:
        resp["error"]="run_dir_not_found"
        return resp

    deg=_gp_degraded(run_dir)
    resp["degraded_items"]=deg
    resp["degraded_n"]=len(deg)

    gp_path=os.path.join(run_dir,"gate_policy.json")
    if os.path.isfile(gp_path):
        gp=_gp_load_json(gp_path) or {}
        resp["verdict"]=_gp_norm_verdict(gp.get("verdict") or gp.get("overall_verdict") or gp.get("overall") or "UNKNOWN")
        rs=gp.get("reasons") or []
        if isinstance(rs,str): rs=[rs]
        resp["reasons"]=rs if isinstance(rs,list) else []
        resp["ok"]=True
        resp["source"]="gate_policy.json"
        return resp

    # fallback: run_gate_summary.json (autogate) so UI still shows a badge
    rg_path=os.path.join(run_dir,"run_gate_summary.json")
    if os.path.isfile(rg_path):
        rg=_gp_load_json(rg_path) or {}
        resp["verdict"]=_gp_norm_verdict(rg.get("overall") or rg.get("overall_status") or rg.get("overall_verdict") or "UNKNOWN")
        resp["reasons"]=[f"fallback:run_gate_summary ({resp['verdict']})", "gate_policy.json missing"]
        resp["ok"]=True
        resp["source"]="run_gate_summary.json"
        return resp

    resp["reasons"]=["gate_policy.json missing", "run_gate_summary.json missing"]
    resp["ok"]=True
    resp["source"]="none"
    return resp

@app.get("/api/vsp/gate_policy_v3/<rid>")
def api_vsp_gate_policy_v3(rid):
    ci_run_dir=_gp_req.args.get("ci_run_dir")
    out=_gp_build(rid, ci_run_dir=ci_run_dir)
    return _gp_jsonify(out)

@app.post("/api/vsp/gate_policy_batch_v1")
def api_vsp_gate_policy_batch_v1():
    data=_gp_req.get_json(silent=True) or {}
    items=data.get("items") or []
    out=[]
    for it in items:
        rid=(it.get("rid") or it.get("run_id") or "").strip()
        if not rid:
            continue
        ci=it.get("ci_run_dir")
        out.append(_gp_build(rid, ci_run_dir=ci))
    return _gp_jsonify({"ok": True, "items_n": len(out), "items": out})
# === /VSP_GATE_POLICY_V3_BATCH_V1 ===
'''
p.write_text(s.rstrip()+"\n\n"+inject+"\n", encoding="utf-8")
print("[OK] appended gate_policy_v3 + batch")
PY

python3 -m py_compile vsp_demo_app.py
echo "[OK] py_compile OK"
echo "[NEXT] restart 8910 gunicorn"
