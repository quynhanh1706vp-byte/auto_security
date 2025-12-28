#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need systemctl

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
FILES=(vsp_demo_app.py wsgi_vsp_ui_gateway.py)
MARK="VSP_P0_AUTOGEN_MANIFEST_EVIDENCEINDEX_V1"

python3 - <<'PY'
from pathlib import Path
import re, time

MARK="VSP_P0_AUTOGEN_MANIFEST_EVIDENCEINDEX_V1"
TARGETS=["vsp_demo_app.py","wsgi_vsp_ui_gateway.py"]

HELPERS = r'''
# ===================== VSP_P0_AUTOGEN_MANIFEST_EVIDENCEINDEX_V1 =====================
def _vsp_p0__scan_run_dir(run_dir: str):
  import os, time, hashlib
  out=[]
  for root, dirs, files in os.walk(run_dir):
    # skip heavy/irrelevant dirs if any
    bn = os.path.basename(root)
    if bn in ("node_modules",".git","__pycache__"):
      continue
    for fn in files:
      fp = os.path.join(root, fn)
      rel = os.path.relpath(fp, run_dir)
      try:
        st=os.stat(fp)
        out.append({
          "path": rel.replace("\\","/"),
          "size": int(st.st_size),
          "mtime": int(st.st_mtime),
        })
      except Exception:
        out.append({"path": rel.replace("\\","/")})
  out.sort(key=lambda x: x.get("path",""))
  return out

def _vsp_p0__write_json_if_possible(fp: str, obj):
  import os, json
  try:
    os.makedirs(os.path.dirname(fp), exist_ok=True)
    with open(fp, "w", encoding="utf-8") as f:
      json.dump(obj, f, ensure_ascii=False, indent=2)
    return True
  except Exception:
    return False

def _vsp_p0_make_run_manifest(run_dir: str, rid: str):
  import time, os
  files = _vsp_p0__scan_run_dir(run_dir)
  return {
    "rid": rid,
    "generated_at": int(time.time()),
    "run_dir": run_dir,
    "files_total": len(files),
    "files": files,
    "note": "auto-generated (P0) because run_manifest.json was missing",
  }

def _vsp_p0_make_run_evidence_index(run_dir: str, rid: str):
  import time, os
  required = [
    "run_gate.json",
    "run_gate_summary.json",
    "findings_unified.json",
    "run_manifest.json",
    "run_evidence_index.json",
    "reports/findings_unified.csv",
    "reports/findings_unified.sarif",
    "reports/findings_unified.html",
  ]
  present=[]
  missing=[]
  for p in required:
    if os.path.exists(os.path.join(run_dir, p)):
      present.append(p)
    else:
      missing.append(p)
  return {
    "rid": rid,
    "generated_at": int(time.time()),
    "run_dir": run_dir,
    "required": required,
    "present": present,
    "missing": missing,
    "audit_ready": (len(missing)==0),
    "note": "auto-generated (P0) because run_evidence_index.json was missing",
  }
# ===================== /VSP_P0_AUTOGEN_MANIFEST_EVIDENCEINDEX_V1 =====================
'''

def patch_file(fp: Path):
  if not fp.exists():
    print("[SKIP] missing:", fp)
    return False
  s = fp.read_text(encoding="utf-8", errors="replace")
  if MARK in s:
    print("[OK] already patched:", fp)
    return False

  # inject helpers near top (after imports)
  if "_vsp_p0_make_run_manifest" not in s:
    m = re.search(r"^(import\s.+|from\s.+import\s.+)\n(?:import\s.+\n|from\s.+import\s.+\n)*", s, flags=re.M)
    if m:
      s = s[:m.end()] + "\n" + HELPERS + "\n" + s[m.end():]
    else:
      s = HELPERS + "\n" + s

  # locate vsp_run_file_allow_v5() block
  lines = s.splitlines(True)
  def_i=None
  for i,l in enumerate(lines):
    if re.match(r"^\s*def\s+vsp_run_file_allow_v5\s*\(\s*\)\s*:", l):
      def_i=i; break
  if def_i is None:
    print("[WARN] no vsp_run_file_allow_v5 in", fp)
    fp.write_text(s, encoding="utf-8")
    return False

  indent = re.match(r"^(\s*)def\s", lines[def_i]).group(1)
  ind_len = len(indent)

  # end of function
  end_i=len(lines)
  for j in range(def_i+1, len(lines)):
    lj=lines[j]
    if lj.strip()=="":
      continue
    ind2=len(re.match(r"^(\s*)", lj).group(1))
    if ind2<=ind_len and (re.match(r"^\s*def\s+\w+\s*\(", lj) or re.match(r"^\s*@", lj)):
      end_i=j; break

  seg = lines[def_i:end_i]
  seg_txt="".join(seg)

  # detect rid var + path var
  rid_var="rid"
  m = re.search(r"^\s*([a-zA-Z_]\w*)\s*=\s*request\.args\.get\(\s*['\"]rid['\"]", seg_txt, flags=re.M)
  if m: rid_var=m.group(1)
  path_var="path"
  m = re.search(r"^\s*([a-zA-Z_]\w*)\s*=\s*request\.args\.get\(\s*['\"]path['\"]", seg_txt, flags=re.M)
  if m: path_var=m.group(1)

  # find first "os.path.join(X, path)" assignment to infer file var + run_dir var
  file_var=None
  run_dir_var=None
  rx = re.compile(r"^\s*([a-zA-Z_]\w*)\s*=\s*os\.path\.join\(\s*([a-zA-Z_]\w*)\s*,\s*"+re.escape(path_var)+r"\s*\)\s*$", re.M)
  m = rx.search(seg_txt)
  if m:
    file_var=m.group(1); run_dir_var=m.group(2)

  # fallback: pathlib join: p = run_dir / path
  if not file_var:
    rx2 = re.compile(r"^\s*([a-zA-Z_]\w*)\s*=\s*([a-zA-Z_]\w*)\s*/\s*"+re.escape(path_var)+r"\s*$", re.M)
    m2 = rx2.search(seg_txt)
    if m2:
      file_var=m2.group(1); run_dir_var=m2.group(2)

  if not run_dir_var:
    # common names
    for cand in ("run_dir","run_root","gate_root_dir","gate_root"):
      if re.search(rf"\b{cand}\b", seg_txt):
        run_dir_var=cand
        break

  # choose insertion point:
  # ideally right after file_var assignment; else after path assignment; else after def line
  insert_k=None
  if file_var:
    for k,l in enumerate(seg):
      if re.search(rf"^\s*{re.escape(file_var)}\s*=\s*.*\b{re.escape(path_var)}\b", l):
        insert_k=k+1; break
  if insert_k is None:
    for k,l in enumerate(seg):
      if re.search(rf"^\s*{re.escape(path_var)}\s*=\s*request\.args\.get\(\s*['\"]path['\"]", l):
        insert_k=k+1; break
  if insert_k is None:
    insert_k=1

  inj = (
    f"{indent}    # {MARK}: autogen core audit files if missing (P0)\n"
    f"{indent}    try:\n"
    f"{indent}        if {path_var} in ('run_manifest.json','run_evidence_index.json'):\n"
    f"{indent}            import os\n"
    f"{indent}            _run_dir = str({run_dir_var}) if '{run_dir_var}' in locals() else None\n"
    f"{indent}            if _run_dir and os.path.isdir(_run_dir):\n"
    f"{indent}                _fp = os.path.join(_run_dir, {path_var})\n"
    f"{indent}                if not os.path.exists(_fp):\n"
    f"{indent}                    _obj = _vsp_p0_make_run_manifest(_run_dir, str({rid_var})) if {path_var}=='run_manifest.json' else _vsp_p0_make_run_evidence_index(_run_dir, str({rid_var}))\n"
    f"{indent}                    _vsp_p0__write_json_if_possible(_fp, _obj)\n"
    f"{indent}                    # return 200 even if write failed\n"
    f"{indent}                    from flask import jsonify\n"
    f"{indent}                    return jsonify(_obj)\n"
    f"{indent}    except Exception:\n"
    f"{indent}        pass\n"
  )

  # insert once
  seg.insert(insert_k, inj)
  seg_txt2="".join(seg)
  if MARK in seg_txt2:
    lines[def_i:end_i]=seg
    s2="".join(lines)

    ts=time.strftime("%Y%m%d_%H%M%S")
    bak=fp.with_name(fp.name+f".bak_autogen_{ts}")
    bak.write_text(fp.read_text(encoding="utf-8", errors="replace"), encoding="utf-8")
    fp.write_text(s2, encoding="utf-8")
    print("[BACKUP]", bak)
    print("[OK] patched:", fp, "rid_var=", rid_var, "path_var=", path_var, "run_dir_var=", run_dir_var)
    return True

  print("[WARN] injection failed for", fp)
  return False

changed=False
for name in TARGETS:
  changed = patch_file(Path(name)) or changed

if not changed:
  print("[INFO] no changes made")
PY

echo "== py_compile =="
python3 -m py_compile vsp_demo_app.py
python3 -m py_compile wsgi_vsp_ui_gateway.py

echo "== restart =="
systemctl restart "$SVC"

echo "== smoke =="
bash bin/p0_dashboard_smoke_contract_v1.sh
