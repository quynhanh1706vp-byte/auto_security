#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="wsgi_vsp_ui_gateway.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_findings_wsgi_${TS}" && echo "[BACKUP] $F.bak_findings_wsgi_${TS}"

python3 - <<'PY'
from pathlib import Path
import re
p=Path("wsgi_vsp_ui_gateway.py")
s=p.read_text(encoding="utf-8", errors="ignore")
marker="VSP_WSGI_FINDINGS_UNIFIED_API_P1_V1"
if marker in s:
    print("[SKIP] marker exists:", marker); raise SystemExit(0)

block=r'''
# === VSP_WSGI_FINDINGS_UNIFIED_API_P1_V1 (commercial) ===
# Ensure /api/vsp/findings_unified_v1/<rid> is registered on the ACTUAL gunicorn "application"
import os, json, glob
from flask import request, jsonify

VSP_UIREQ_DIR = os.environ.get("VSP_UIREQ_DIR", "/home/test/Data/SECURITY_BUNDLE/ui/out_ci/uireq_v1")
VSP_CI_OUT_GLOB = os.environ.get("VSP_CI_OUT_GLOB", "/home/test/Data/**/out_ci/VSP_CI_*")

_SEV_W = {"CRITICAL": 50, "HIGH": 40, "MEDIUM": 30, "LOW": 20, "INFO": 10, "TRACE": 0}
def _sev_w(x): return _SEV_W.get((x or "").upper(), -1)

def _read_json(path):
  try:
    with open(path, "r", encoding="utf-8") as f:
      return json.load(f)
  except Exception:
    return None

def _resolve_run_dir_from_rid(rid: str):
  st = _read_json(os.path.join(VSP_UIREQ_DIR, f"{rid}.json")) or {}
  for k in ("ci_run_dir","ci_run_dir_resolved","run_dir","RUN_DIR"):
    v = st.get(k)
    if isinstance(v,str) and v.strip():
      return v.strip(), "uireq_state"
  cands=[]
  for d in glob.glob(VSP_CI_OUT_GLOB, recursive=True):
    if rid in (os.path.basename(d) or "") or rid in d:
      cands.append(d)
  cands = sorted(set(cands), key=lambda x: os.path.getmtime(x) if os.path.exists(x) else 0, reverse=True)
  if cands: return cands[0], "scan_out_ci"
  return None, "not_found"

def _apply_filters(items, q=None, sev=None, tool=None, cwe=None, fileq=None):
  q=(q or "").strip().lower(); fileq=(fileq or "").strip().lower()
  sev=(sev or "").strip().upper(); tool=(tool or "").strip().lower(); cwe=(cwe or "").strip().upper()
  out=[]
  for it in items or []:
    t=(it.get("title") or "")
    f=(it.get("file") or "")
    sv=(it.get("severity") or "").upper()
    tl=(it.get("tool") or "").lower()
    cw=it.get("cwe")
    c=""
    if isinstance(cw,list) and cw: c=str(cw[0] or "").upper()
    elif isinstance(cw,str): c=cw.upper()
    if sev and sv!=sev: continue
    if tool and tool!=tl: continue
    if cwe and cwe!=c: continue
    if fileq and fileq not in f.lower(): continue
    if q:
      hay=(t+" "+f+" "+(it.get("id") or "")).lower()
      if q not in hay: continue
    out.append(it)
  return out

# avoid double-register if hot reload
try:
  _has = any(getattr(r, "rule", "")=="/api/vsp/findings_unified_v1/<rid>" for r in application.url_map.iter_rules())
except Exception:
  _has = False

if not _has:
  @application.get("/api/vsp/findings_unified_v1/<rid>")
  def api_vsp_findings_unified_v1(rid):
    page=int(request.args.get("page","1") or "1")
    limit=int(request.args.get("limit","50") or "50")
    page=1 if page<1 else page
    limit=50 if limit<1 else (500 if limit>500 else limit)

    q=request.args.get("q"); sev=request.args.get("sev"); tool=request.args.get("tool")
    cwe=request.args.get("cwe"); fileq=request.args.get("file")

    run_dir, src = _resolve_run_dir_from_rid(rid)
    if not run_dir:
      return jsonify({"ok":False,"warning":"run_dir_not_found","rid":rid,"resolve_source":src,"total":0,"items":[]}), 200

    fp=os.path.join(run_dir,"findings_unified.json")
    data=_read_json(fp)
    if not data or not isinstance(data,dict):
      return jsonify({"ok":True,"warning":"findings_unified_not_found_or_bad","rid":rid,"resolve_source":src,"run_dir":run_dir,"file":fp,"total":0,"items":[]}), 200

    items=data.get("items") or []
    items=_apply_filters(items,q=q,sev=sev,tool=tool,cwe=cwe,fileq=fileq)
    items.sort(key=lambda it: (-_sev_w(it.get("severity")), (it.get("tool") or ""), (it.get("file") or ""), int(it.get("line") or 0)))
    total=len(items)
    start=(page-1)*limit; end=start+limit
    page_items=items[start:end]

    by_sev={}; by_tool={}; by_cwe={}
    for it in items:
      sv=(it.get("severity") or "UNKNOWN").upper()
      tl=(it.get("tool") or "UNKNOWN")
      cw=it.get("cwe"); c="UNKNOWN"
      if isinstance(cw,list) and cw: c=str(cw[0] or "UNKNOWN").upper()
      elif isinstance(cw,str) and cw.strip(): c=cw.strip().upper()
      by_sev[sv]=by_sev.get(sv,0)+1
      by_tool[tl]=by_tool.get(tl,0)+1
      by_cwe[c]=by_cwe.get(c,0)+1
    top_cwe=sorted(by_cwe.items(), key=lambda kv: kv[1], reverse=True)[:10]

    return jsonify({
      "ok":True,"rid":rid,"run_dir":run_dir,"resolve_source":src,"file":fp,
      "page":page,"limit":limit,"total":total,
      "counts":{"by_sev":by_sev,"by_tool":by_tool,"top_cwe":top_cwe},
      "items":page_items,
      "filters":{"q":q,"sev":sev,"tool":tool,"cwe":cwe,"file":fileq},
    }), 200
# === /VSP_WSGI_FINDINGS_UNIFIED_API_P1_V1 ===
'''

p.write_text(s.rstrip()+"\n\n"+block+"\n", encoding="utf-8")
print("[OK] patched wsgi marker:", marker)
PY

python3 -m py_compile wsgi_vsp_ui_gateway.py
echo "[OK] py_compile OK => $F"
