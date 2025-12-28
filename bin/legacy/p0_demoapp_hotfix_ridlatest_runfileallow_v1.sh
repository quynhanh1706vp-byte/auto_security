#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need systemctl; need curl; need grep

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
APP="vsp_demo_app.py"
[ -f "$APP" ] || { echo "[ERR] missing $APP"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$APP" "${APP}.bak_hotfix_${TS}"
echo "[BACKUP] ${APP}.bak_hotfix_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("vsp_demo_app.py")
s = p.read_text(encoding="utf-8", errors="replace")

MARK = "VSP_P0_RIDLATEST_RUNFILEALLOW_HOTFIX_V1"
if MARK in s:
    print("[SKIP] already patched")
    raise SystemExit(0)

# detect flask app variable name
appvar = None
m = re.search(r'^\s*(app|application)\s*=\s*Flask\s*\(', s, flags=re.M)
if m:
    appvar = m.group(1)

if not appvar:
    # fallback: common create_app pattern - try to locate "app =" in function scope
    m2 = re.search(r'^\s*(app|application)\s*=\s*Flask\s*\(', s, flags=re.M)
    if m2:
        appvar = m2.group(1)

if not appvar:
    print("[ERR] cannot detect Flask app variable (app/application = Flask(...)) in vsp_demo_app.py")
    raise SystemExit(2)

# insert hotfix block right after first "app = Flask(" line
lines = s.splitlines(True)
idx = None
for i, ln in enumerate(lines):
    if re.match(r'^\s*' + re.escape(appvar) + r'\s*=\s*Flask\s*\(', ln):
        idx = i + 1
        break
if idx is None:
    print("[ERR] cannot find insertion point")
    raise SystemExit(2)

block = f'''
# ===================== {MARK} =====================
# Hotfix goals:
# - /api/vsp/rid_latest must return KPI payload (overall/ts/counts_total) and never ok:false rid:null stub.
# - /api/vsp/run_file_allow must resolve RID->run_dir and serve allowed files fast (with cache) to unblock UI.
import os, json, time, mimetypes
from flask import request, jsonify, Response

_VSP_P0_CACHE = {{
  "rid_latest": {{"ts": 0.0, "payload": None}},
  "run_dir": {{}},   # rid -> (ts, path)
}}

def _vsp_p0_http_json(url: str, timeout: float = 0.6):
  try:
    import urllib.request
    with urllib.request.urlopen(url, timeout=timeout) as r:
      data = r.read()
    return json.loads(data.decode("utf-8", "replace"))
  except Exception:
    return None

def _vsp_p0_candidate_bases():
  # You can override via env: VSP_RUN_BASES="/path1:/path2"
  env = os.environ.get("VSP_RUN_BASES", "").strip()
  bases = []
  if env:
    for x in env.split(":"):
      x = x.strip()
      if x and os.path.isdir(x):
        bases.append(x)

  # sensible defaults for your workspace
  defaults = [
    "/home/test/Data/SECURITY_BUNDLE/out_ci",
    "/home/test/Data/SECURITY_BUNDLE/out",
    "/home/test/Data/SECURITY_BUNDLE/ui/out_ci",
    "/home/test/Data/SECURITY-10-10-v4/out_ci",
    "/home/test/Data/SECURITY-10-10-v4/out",
  ]
  for d in defaults:
    if os.path.isdir(d) and d not in bases:
      bases.append(d)
  return bases

def _vsp_p0_is_run_dir(d: str):
  # accept if it looks like a run folder
  if not os.path.isdir(d):
    return False
  must_any = [
    "run_gate_summary.json",
    "run_gate.json",
    "findings_unified.json",
    os.path.join("reports","findings_unified.csv"),
  ]
  for x in must_any:
    if os.path.exists(os.path.join(d, x)):
      return True
  return False

def _vsp_p0_resolve_run_dir(rid: str, ttl: float = 10.0):
  rid = (rid or "").strip()
  if not rid:
    return None
  now = time.time()
  hit = _VSP_P0_CACHE["run_dir"].get(rid)
  if hit and (now - hit[0]) < ttl and hit[1] and os.path.isdir(hit[1]):
    return hit[1]

  bases = _vsp_p0_candidate_bases()
  # 1) direct match base/rid
  for b in bases:
    cand = os.path.join(b, rid)
    if _vsp_p0_is_run_dir(cand):
      _VSP_P0_CACHE["run_dir"][rid] = (now, cand)
      return cand

  # 2) scan within bases for folder name containing rid (bounded)
  for b in bases:
    try:
      names = os.listdir(b)
    except Exception:
      continue
    # quick filter
    cands = []
    for nm in names[:5000]:
      if rid in nm:
        d = os.path.join(b, nm)
        if _vsp_p0_is_run_dir(d):
          cands.append(d)
    if cands:
      # choose latest mtime
      cands.sort(key=lambda x: os.path.getmtime(x), reverse=True)
      _VSP_P0_CACHE["run_dir"][rid] = (now, cands[0])
      return cands[0]

  _VSP_P0_CACHE["run_dir"][rid] = (now, None)
  return None

def _vsp_p0_safe_rel(path: str):
  # normalize and prevent traversal
  path = (path or "").replace("\\\\", "/").lstrip("/")
  if not path or ".." in path or path.startswith(("/", "\\")):
    return None
  return path

def _vsp_p0_allowed(rel: str):
  # strict allowlist (extend safely if needed)
  allow = {{
    "run_gate.json",
    "run_gate_summary.json",
    "findings_unified.json",
    "run_manifest.json",
    "run_evidence_index.json",
    "reports/findings_unified.csv",
    "reports/findings_unified.sarif",
    "reports/findings_unified.html",
    "reports/findings_unified.pdf",
    "evidence/ui_engine.log",
    "evidence/trace.zip",
    "evidence/last_page.html",
    "evidence/storage_state.json",
    "evidence/net_summary.json",
  }}
  return rel in allow

def _vsp_p0_read_json(fp: str):
  try:
    with open(fp, "rb") as f:
      return json.loads(f.read().decode("utf-8", "replace"))
  except Exception:
    return None

def _vsp_p0_build_rid_latest_payload():
  # cache very short to avoid “chậm” on UI live polling
  now = time.time()
  c = _VSP_P0_CACHE["rid_latest"]
  if c["payload"] is not None and (now - c["ts"]) < 1.0:
    return c["payload"]

  base = os.environ.get("VSP_UI_BASE", "http://127.0.0.1:8910").rstrip("/")
  j = _vsp_p0_http_json(base + "/api/vsp/rid_latest_gate_root", timeout=0.6) or {{}}
  rid = (j.get("rid") or j.get("run_id") or "").strip()
  gate_root = (j.get("gate_root") or "").strip()

  payload = {{
    "overall": "UNKNOWN",
    "ts": None,
    "counts_total": {{"CRITICAL":0,"HIGH":0,"MEDIUM":0,"LOW":0,"INFO":0,"TRACE":0}},
    "rid": rid or None,
    "gate_root": gate_root or None,
    "degraded": True,
    "served_by": __file__,
  }}

  if rid:
    rd = _vsp_p0_resolve_run_dir(rid)
    if rd:
      # prefer run_gate_summary.json
      rgs = _vsp_p0_read_json(os.path.join(rd, "run_gate_summary.json"))
      if isinstance(rgs, dict) and ("counts_total" in rgs or "overall" in rgs):
        payload["overall"] = rgs.get("overall", payload["overall"])
        payload["ts"] = rgs.get("ts") or rgs.get("timestamp") or payload["ts"]
        ct = rgs.get("counts_total") or rgs.get("counts_by_severity") or {{}}
        if isinstance(ct, dict):
          for k in payload["counts_total"].keys():
            if k in ct and isinstance(ct[k], int):
              payload["counts_total"][k] = ct[k]
        payload["degraded"] = False
      else:
        # fallback from findings_unified.json meta
        fu = _vsp_p0_read_json(os.path.join(rd, "findings_unified.json"))
        meta = (fu or {{}}).get("meta") if isinstance(fu, dict) else None
        cbs = (meta or {{}}).get("counts_by_severity") if isinstance(meta, dict) else None
        if isinstance(cbs, dict):
          for k in payload["counts_total"].keys():
            if k in cbs and isinstance(cbs[k], int):
              payload["counts_total"][k] = cbs[k]
          payload["degraded"] = False

  _VSP_P0_CACHE["rid_latest"] = {{"ts": now, "payload": payload}}
  return payload

@{appvar}.before_request
def _vsp_p0_before_request_hotfix_v1():
  pth = request.path

  # 1) Fix rid_latest contract (KPI JSON) so bundle can render and stop skeleton
  if pth == "/api/vsp/rid_latest":
    return jsonify(_vsp_p0_build_rid_latest_payload())

  # 2) Provide stable run_file_allow that can actually serve files for UI panels
  if pth == "/api/vsp/run_file_allow":
    rid = (request.args.get("rid") or "").strip()
    rel = _vsp_p0_safe_rel(request.args.get("path") or "")
    if not rid or not rel or (not _vsp_p0_allowed(rel)):
      return jsonify({{"ok": False, "rid": rid or None, "err": "not_allowed", "path": request.args.get("path")}}), 200

    rd = _vsp_p0_resolve_run_dir(rid)
    if not rd:
      return jsonify({{"ok": False, "rid": rid, "err": "run_dir_not_found", "degraded": True}}), 200

    fp = os.path.join(rd, rel)
    if not os.path.exists(fp):
      return jsonify({{"ok": False, "rid": rid, "err": "file_not_found", "path": rel, "run_dir": rd}}), 404

    # serve content
    ctype = mimetypes.guess_type(fp)[0] or "application/octet-stream"
    try:
      data = open(fp, "rb").read()
    except Exception as e:
      return jsonify({{"ok": False, "rid": rid, "err": "read_failed", "path": rel, "detail": str(e)}}), 500

    # force JSON mime for json files
    if fp.endswith(".json"):
      ctype = "application/json; charset=utf-8"
    elif fp.endswith(".csv"):
      ctype = "text/csv; charset=utf-8"
    elif fp.endswith(".html"):
      ctype = "text/html; charset=utf-8"
    return Response(data, mimetype=ctype)

  return None
# ===================== /{MARK} =====================
'''

lines.insert(idx, block)
p.write_text("".join(lines), encoding="utf-8")
print(f"[OK] injected hotfix block into {p} using appvar={appvar}")
PY

echo "== py_compile =="
python3 -m py_compile "$APP"
echo "[OK] py_compile OK"

echo "== restart =="
systemctl restart "$SVC" 2>/dev/null || true

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"

echo "== smoke: rid_latest should be KPI payload (NOT ok:false rid:null stub) =="
curl -fsS "$BASE/api/vsp/rid_latest" | head -c 220; echo

echo "== smoke: rid_latest_gate_root should have rid =="
curl -fsS "$BASE/api/vsp/rid_latest_gate_root" | head -c 180; echo

echo "== smoke: run_file_allow should return JSON (run_gate_summary) =="
RID="$(curl -fsS "$BASE/api/vsp/rid_latest_gate_root" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("rid",""))')"
echo "RID=$RID"
curl -fsS "$BASE/api/vsp/run_file_allow?rid=$RID&path=run_gate_summary.json" | head -c 160; echo

echo "[DONE] Ctrl+Shift+R /vsp5"
