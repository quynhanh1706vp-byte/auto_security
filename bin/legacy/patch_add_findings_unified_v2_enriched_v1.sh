#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="wsgi_vsp_ui_gateway.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_add_findings_v2_${TS}" && echo "[BACKUP] $F.bak_add_findings_v2_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("wsgi_vsp_ui_gateway.py")
s=p.read_text(encoding="utf-8", errors="ignore")

marker="VSP_FINDINGS_UNIFIED_V2_ENRICHED_V1"
if marker in s:
    print("[SKIP] marker exists:", marker)
    raise SystemExit(0)

m=re.search(r'^\s*([A-Za-z_]\w*)\s*=\s*Flask\s*\(', s, flags=re.M)
flask_var = m.group(1) if m else "app"

block = f'''
# === {marker} ===
# New endpoint (non-invasive): /api/vsp/findings_unified_v2/<rid>
# Goal: commercial-safe enrichment (CWE from item.raw) + stable counts/top_cwe.
import os, json, glob
from flask import request, jsonify

VSP_UIREQ_DIR = os.environ.get("VSP_UIREQ_DIR", "/home/test/Data/SECURITY_BUNDLE/ui/out_ci/uireq_v1")
VSP_CI_OUT_GLOB = os.environ.get("VSP_CI_OUT_GLOB", "/home/test/Data/**/out_ci/VSP_CI_*")

_SEV_W = {{"CRITICAL": 50, "HIGH": 40, "MEDIUM": 30, "LOW": 20, "INFO": 10, "TRACE": 0}}
def _sev_w(x): return _SEV_W.get((x or "").upper(), -1)

def _read_json(path):
  try:
    with open(path, "r", encoding="utf-8") as f:
      return json.load(f)
  except Exception:
    return None

def _resolve_run_dir_from_rid(rid: str):
  st = _read_json(os.path.join(VSP_UIREQ_DIR, f"{{rid}}.json")) or {{}}
  for k in ("ci_run_dir","ci_run_dir_resolved","run_dir","RUN_DIR"):
    v = st.get(k)
    if isinstance(v, str) and v.strip():
      return v.strip(), "uireq_state"
  cands=[]
  for d in glob.glob(VSP_CI_OUT_GLOB, recursive=True):
    if rid in (os.path.basename(d) or "") or rid in d:
      cands.append(d)
  cands = sorted(set(cands), key=lambda x: os.path.getmtime(x) if os.path.exists(x) else 0, reverse=True)
  if cands:
    return cands[0], "scan_out_ci"
  return None, "not_found"

def _norm_cwe(v):
  try:
    v = str(v or "").strip()
    if not v: return None
    u = v.upper()
    if u.startswith("CWE-"): return u
    if v.isdigit(): return "CWE-" + v
    return u
  except Exception:
    return None

def _extract_cwe_list(it):
  # Prefer item.cwe
  cw = it.get("cwe")
  out=[]
  if isinstance(cw, list):
    for x in cw:
      nx = _norm_cwe(x)
      if nx: out.append(nx)
  elif isinstance(cw, str):
    nx=_norm_cwe(cw)
    if nx: out.append(nx)
  if out:
    return list(dict.fromkeys(out))

  # Fallback: item.raw.* (GRYPE proven here)
  raw = it.get("raw") or {{}}
  vuln = (raw.get("vulnerability") or {{}})
  cwes = vuln.get("cwes") or []
  out=[]
  for c in cwes:
    v = c.get("cwe") if isinstance(c, dict) else c
    nx=_norm_cwe(v)
    if nx: out.append(nx)
  if out:
    return list(dict.fromkeys(out))

  rv = raw.get("relatedVulnerabilities") or []
  out=[]
  for vv in rv:
    for c in (vv.get("cwes") or []):
      v = c.get("cwe") if isinstance(c, dict) else c
      nx=_norm_cwe(v)
      if nx: out.append(nx)
  if out:
    return list(dict.fromkeys(out))

  # SARIF-ish (best-effort)
  for path in [
    ("rule","properties","cwe"),
    ("properties","cwe"),
    ("rule","cwe"),
    ("cwe",),
  ]:
    cur = raw
    ok=True
    for k in path:
      if isinstance(cur, dict) and k in cur:
        cur = cur[k]
      else:
        ok=False; break
    if ok and cur:
      if isinstance(cur, list) and cur:
        nx=_norm_cwe(cur[0])
        return [nx] if nx else None
      nx=_norm_cwe(cur)
      return [nx] if nx else None

  return None

def _apply_filters(items, q=None, sev=None, tool=None, cwe=None, fileq=None):
  q=(q or "").strip().lower()
  fileq=(fileq or "").strip().lower()
  sev=(sev or "").strip().upper()
  tool=(tool or "").strip().lower()
  cwe=(cwe or "").strip().upper()
  out=[]
  for it in items or []:
    t=(it.get("title") or "")
    f=(it.get("file") or "")
    sv=(it.get("severity") or "").upper()
    tl=(it.get("tool") or "").lower()
    cws = _extract_cwe_list(it) or []
    c0 = (str(cws[0]).upper() if cws else "UNKNOWN")

    if sev and sv != sev: 
      continue
    if tool and tool != tl:
      continue
    if cwe and cwe != c0:
      continue
    if fileq and fileq not in f.lower():
      continue
    if q:
      hay=(t+" "+f+" "+(it.get("id") or "")).lower()
      if q not in hay:
        continue

    # ensure item.cwe filled for UI
    if cws and not it.get("cwe"):
      it["cwe"] = cws
    out.append(it)
  return out

@{flask_var}.route("/api/vsp/findings_unified_v2/<rid>", methods=["GET"])
def api_vsp_findings_unified_v2(rid):
  page = int(request.args.get("page","1") or "1")
  limit = int(request.args.get("limit","50") or "50")
  page = 1 if page < 1 else page
  limit = 50 if limit < 1 else (500 if limit > 500 else limit)

  q = request.args.get("q")
  sev = request.args.get("sev")
  tool = request.args.get("tool")
  cwe = request.args.get("cwe")
  fileq = request.args.get("file")

  run_dir, src = _resolve_run_dir_from_rid(rid)
  if not run_dir:
    return jsonify({{
      "ok": False,
      "warning": "run_dir_not_found",
      "rid": rid,
      "resolve_source": src,
      "total": 0,
      "items": [],
    }}), 200

  fp = os.path.join(run_dir, "findings_unified.json")
  data = _read_json(fp)
  if not data or not isinstance(data, dict):
    return jsonify({{
      "ok": True,
      "warning": "findings_unified_not_found_or_bad",
      "rid": rid,
      "resolve_source": src,
      "run_dir": run_dir,
      "file": fp,
      "total": 0,
      "items": [],
    }}), 200

  items = data.get("items") or []
  items = _apply_filters(items, q=q, sev=sev, tool=tool, cwe=cwe, fileq=fileq)

  items.sort(key=lambda it: (-_sev_w(it.get("severity")), (it.get("tool") or ""), (it.get("file") or ""), int(it.get("line") or 0)))
  total = len(items)
  start = (page-1)*limit
  end = start + limit
  page_items = items[start:end]

  by_sev={{}}; by_tool={{}}; by_cwe={{}}
  for it in items:
    sv=(it.get("severity") or "UNKNOWN").upper()
    tl=(it.get("tool") or "UNKNOWN")
    cws = _extract_cwe_list(it) or []
    c0 = (str(cws[0]).upper() if cws else "UNKNOWN")
    by_sev[sv]=by_sev.get(sv,0)+1
    by_tool[tl]=by_tool.get(tl,0)+1
    by_cwe[c0]=by_cwe.get(c0,0)+1

  unknown_count = by_cwe.get("UNKNOWN", 0)
  top_cwe = sorted([(k,v) for (k,v) in by_cwe.items() if k!="UNKNOWN"], key=lambda kv: kv[1], reverse=True)[:10]

  return jsonify({{
    "ok": True,
    "rid": rid,
    "run_dir": run_dir,
    "resolve_source": src,
    "file": fp,
    "page": page,
    "limit": limit,
    "total": total,
    "counts": {{
      "by_sev": by_sev,
      "by_tool": by_tool,
      "top_cwe": top_cwe,
      "unknown_count": unknown_count
    }},
    "items": page_items,
    "filters": {{"q": q, "sev": sev, "tool": tool, "cwe": cwe, "file": fileq}},
    "debug": ({{"marker":"{marker}","flask_var":"{flask_var}"}} if request.args.get("debug")=="1" else None)
  }}), 200
# === /{marker} ===
'''

p.write_text(s.rstrip()+"\n\n"+block+"\n", encoding="utf-8")
print("[OK] appended findings_unified_v2 route on", flask_var)
PY

python3 -m py_compile wsgi_vsp_ui_gateway.py
echo "[OK] py_compile OK => $F"
