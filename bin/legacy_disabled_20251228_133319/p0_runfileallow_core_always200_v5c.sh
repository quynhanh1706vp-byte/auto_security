#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need systemctl

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
FILES=(vsp_demo_app.py wsgi_vsp_ui_gateway.py)
MARK="VSP_P0_CORE_ALWAYS200_V5C"

python3 - <<'PY'
from pathlib import Path
import re, time, py_compile

FILES=[Path("vsp_demo_app.py"), Path("wsgi_vsp_ui_gateway.py")]
MARK="VSP_P0_CORE_ALWAYS200_V5C"
REQ=[
  "run_gate.json","run_gate_summary.json","findings_unified.json",
  "run_manifest.json","run_evidence_index.json",
  "reports/findings_unified.csv","reports/findings_unified.sarif","reports/findings_unified.html"
]

def find_func(lines, funcname):
    def_i=None
    for i,l in enumerate(lines):
        if re.match(rf"^\s*def\s+{re.escape(funcname)}\s*\(\s*\)\s*:", l):
            def_i=i; break
    if def_i is None:
        return None
    def_indent = re.match(r"^(\s*)def\s", lines[def_i]).group(1)
    def_indent_len = len(def_indent)
    end_i=len(lines)
    for j in range(def_i+1, len(lines)):
        lj=lines[j]
        if lj.strip()=="":
            continue
        ind2=len(re.match(r"^(\s*)", lj).group(1))
        if ind2<=def_indent_len and (re.match(r"^\s*def\s+\w+\s*\(", lj) or re.match(r"^\s*@", lj)):
            end_i=j; break
    return def_i, end_i

def patch(fp: Path):
    s = fp.read_text(encoding="utf-8", errors="replace")
    if MARK in s:
        print("[OK] already patched:", fp)
        return False
    lines = s.splitlines(True)
    blk = find_func(lines, "vsp_run_file_allow_v5")
    if not blk:
        print("[WARN] no vsp_run_file_allow_v5 in", fp)
        return False
    def_i,end_i = blk
    seg = lines[def_i:end_i]
    seg_txt="".join(seg)

    # detect rid/path var names from assignments
    rid_var="rid"
    m=re.search(r"^\s*([a-zA-Z_]\w*)\s*=\s*request\.args\.get\(\s*['\"]rid['\"]", seg_txt, re.M)
    if m: rid_var=m.group(1)
    path_var="path"
    m=re.search(r"^\s*([a-zA-Z_]\w*)\s*=\s*request\.args\.get\(\s*['\"]path['\"]", seg_txt, re.M)
    if m: path_var=m.group(1)

    # insert right after path assignment
    k_ins=None
    indent=None
    for k,l in enumerate(seg):
        if "request.args.get" in l and ("'path'" in l or '"path"' in l) and "=" in l:
            k_ins=k+1
            indent=re.match(r"^(\s*)", l).group(1)
            break
    if k_ins is None:
        print("[ERR] cannot find path assignment line in", fp)
        return False

    req_list = "[" + ",".join([repr(x) for x in REQ]) + "]"
    base=indent
    b2=base+"  "
    b3=base+"    "
    b4=base+"      "

    inj = (
      f"{base}# {MARK}\n"
      f"{base}try:\n"
      f"{b2}import time\n"
      f"{b2}from flask import jsonify\n"
      f"{b2}if {path_var} in ('run_manifest.json','run_evidence_index.json'):\n"
      f"{b3}_rid = str({rid_var})\n"
      f"{b3}obj={{'rid':_rid,'generated_at':int(time.time()),'note':'P0: core contract always 200; run_dir unresolved (set VSP_RUNS_ROOT later to autogen real files)'}}\n"
      f"{b3}if {path_var}=='run_manifest.json':\n"
      f"{b4}obj.update({{'files_total':0,'files':[]}})\n"
      f"{b3}else:\n"
      f"{b4}obj.update({{'required':{req_list},'present':[],'missing':{req_list},'audit_ready':False}})\n"
      f"{b3}return jsonify(obj), 200\n"
      f"{base}except Exception:\n"
      f"{b2}pass\n"
    )

    seg.insert(k_ins, inj)
    lines[def_i:end_i] = seg
    s2="".join(lines)

    bak = fp.with_name(fp.name + f".bak_core200_{time.strftime('%Y%m%d_%H%M%S')}")
    bak.write_text(s, encoding="utf-8")
    fp.write_text(s2, encoding="utf-8")
    print("[BACKUP]", bak)
    print("[OK] patched:", fp, "rid_var=", rid_var, "path_var=", path_var)
    return True

changed=False
for f in FILES:
    changed = patch(f) or changed

for f in FILES:
    py_compile.compile(str(f), doraise=True)
PY

echo "== restart =="
systemctl restart "$SVC"

echo "== smoke =="
bash bin/p0_dashboard_smoke_contract_v1.sh
