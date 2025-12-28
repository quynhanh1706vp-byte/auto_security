#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need systemctl

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
MARK="VSP_P0_RUNFILEALLOW_GUARD_BEFORE_JOIN_V4"
FILES=(vsp_demo_app.py wsgi_vsp_ui_gateway.py)

python3 - <<'PY'
from pathlib import Path
import re, time, sys

MARK="VSP_P0_RUNFILEALLOW_GUARD_BEFORE_JOIN_V4"
FILES=[Path("vsp_demo_app.py"), Path("wsgi_vsp_ui_gateway.py")]

REQ = [
  "run_gate.json","run_gate_summary.json","findings_unified.json",
  "run_manifest.json","run_evidence_index.json",
  "reports/findings_unified.csv","reports/findings_unified.sarif","reports/findings_unified.html"
]

def patch(fp: Path):
    if not fp.exists():
        print("[SKIP] missing:", fp); return False
    s = fp.read_text(encoding="utf-8", errors="replace")
    if MARK in s:
        print("[OK] already patched:", fp); return False

    lines = s.splitlines(True)

    # find vsp_run_file_allow_v5
    def_i=None
    for i,l in enumerate(lines):
        if re.match(r"^\s*def\s+vsp_run_file_allow_v5\s*\(\s*\)\s*:", l):
            def_i=i; break
    if def_i is None:
        print("[WARN] no vsp_run_file_allow_v5 in", fp); return False

    def_indent = re.match(r"^(\s*)def\s", lines[def_i]).group(1)
    def_indent_len = len(def_indent)

    # find end of function
    end_i=len(lines)
    for j in range(def_i+1, len(lines)):
        lj=lines[j]
        if lj.strip()=="":
            continue
        ind2=len(re.match(r"^(\s*)", lj).group(1))
        if ind2<=def_indent_len and (re.match(r"^\s*def\s+\w+\s*\(", lj) or re.match(r"^\s*@", lj)):
            end_i=j; break

    seg = lines[def_i:end_i]
    seg_txt = "".join(seg)

    # detect rid/path vars
    rid_var="rid"
    m=re.search(r"^\s*([a-zA-Z_]\w*)\s*=\s*request\.args\.get\(\s*['\"]rid['\"]", seg_txt, re.M)
    if m: rid_var=m.group(1)
    path_var="path"
    m=re.search(r"^\s*([a-zA-Z_]\w*)\s*=\s*request\.args\.get\(\s*['\"]path['\"]", seg_txt, re.M)
    if m: path_var=m.group(1)

    # find _run_dir assignment line and _fp join line
    run_dir_var="_run_dir"
    run_k=None
    run_indent=None
    # prefer exact _run_dir =
    for k,l in enumerate(seg):
        mm=re.match(r"^(\s*)(_run_dir)\s*=\s*", l)
        if mm:
            run_k=k; run_indent=mm.group(1); run_dir_var=mm.group(2); break
    # fallback: any var = ...run_dir...
    if run_k is None:
        for k,l in enumerate(seg):
            if "run_dir" in l and "=" in l and "request" not in l:
                mm=re.match(r"^(\s*)([a-zA-Z_]\w*)\s*=\s*.*run_dir", l)
                if mm:
                    run_k=k; run_indent=mm.group(1); run_dir_var=mm.group(2); break

    if run_k is None:
        print("[ERR] cannot find _run_dir assignment in", fp); return False

    # find join line AFTER run_k: _fp = os.path.join(_run_dir, path)
    fp_k=None
    fp_var="_fp"
    join_rx=re.compile(r"^(\s*)([a-zA-Z_]\w*)\s*=\s*os\.path\.join\(\s*"+re.escape(run_dir_var)+r"\s*,\s*"+re.escape(path_var)+r"\s*\)\s*$")
    for k in range(run_k, len(seg)):
        mm=join_rx.match(seg[k])
        if mm:
            fp_k=k; fp_var=mm.group(2); break

    if fp_k is None:
        # maybe path var differs; looser match
        join_rx2=re.compile(r"^(\s*)([a-zA-Z_]\w*)\s*=\s*os\.path\.join\(\s*"+re.escape(run_dir_var)+r"\s*,\s*([a-zA-Z_]\w*)\s*\)\s*$")
        for k in range(run_k, len(seg)):
            mm=join_rx2.match(seg[k])
            if mm:
                fp_k=k; fp_var=mm.group(2); path_var=mm.group(3); break

    if fp_k is None:
        print("[ERR] cannot find os.path.join(_run_dir, path) in", fp); return False

    indent = run_indent or re.match(r"^(\s*)", seg[run_k]).group(1)

    req_list = "[" + ",".join([repr(x) for x in REQ]) + "]"

    inj = (
f"{indent}# {MARK}\n"
f"{indent}try:\n"
f"{indent}  import os, time\n"
f"{indent}  from flask import jsonify\n"
f"{indent}  _rd = {run_dir_var}\n"
f"{indent}  if (not _rd) or (not os.path.isdir(str(_rd))):\n"
f"{indent}    if {path_var} in ('run_manifest.json','run_evidence_index.json'):\n"
f"{indent}      obj={{'rid':str({rid_var}),'generated_at':int(time.time()),'run_dir':str(_rd),'note':'run_dir missing (P0)','required':{req_list},'present':[],'missing':{req_list},'audit_ready':False}}\n"
f"{indent}      return jsonify(obj), 200\n"
f"{indent}    return jsonify({{'ok':False,'err':'run_dir not found','rid':str({rid_var}),'path':str({path_var}),'run_dir':str(_rd)}}), 404\n"
f"{indent}except Exception:\n"
f"{indent}  pass\n"
    )

    # insert guard between run_dir assignment and join
    seg.insert(fp_k, inj)
    lines[def_i:end_i] = seg
    s2="".join(lines)

    bak = fp.with_name(fp.name + f".bak_guardv4_{time.strftime('%Y%m%d_%H%M%S')}")
    bak.write_text(s, encoding="utf-8")
    fp.write_text(s2, encoding="utf-8")
    print("[BACKUP]", bak)
    print("[OK] patched:", fp, "run_dir_var=", run_dir_var, "fp_var=", fp_var, "path_var=", path_var)
    return True

changed=False
for f in FILES:
    changed = patch(f) or changed
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
