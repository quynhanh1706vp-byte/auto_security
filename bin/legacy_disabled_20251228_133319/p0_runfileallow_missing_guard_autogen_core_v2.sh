#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need systemctl

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
MARK="VSP_P0_RUNFILEALLOW_MISSING_GUARD_AUTOGEN_CORE_V2"

python3 - <<'PY'
from pathlib import Path
import re, time, sys

MARK="VSP_P0_RUNFILEALLOW_MISSING_GUARD_AUTOGEN_CORE_V2"
FILES=[Path("vsp_demo_app.py"), Path("wsgi_vsp_ui_gateway.py")]

def patch(fp: Path):
    if not fp.exists():
        print("[SKIP] missing:", fp)
        return False
    s = fp.read_text(encoding="utf-8", errors="replace")
    if MARK in s:
        print("[OK] already patched:", fp)
        return False

    lines = s.splitlines(True)

    # find vsp_run_file_allow_v5
    def_i=None
    for i,l in enumerate(lines):
        if re.match(r"^\s*def\s+vsp_run_file_allow_v5\s*\(\s*\)\s*:", l):
            def_i=i; break
    if def_i is None:
        print("[WARN] no vsp_run_file_allow_v5 in", fp)
        return False

    def_indent = re.match(r"^(\s*)def\s", lines[def_i]).group(1)
    def_indent_len = len(def_indent)

    # end of function
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

    # detect rid/path/run_dir vars
    rid_var="rid"
    m = re.search(r"^\s*([a-zA-Z_]\w*)\s*=\s*request\.args\.get\(\s*['\"]rid['\"]", seg_txt, flags=re.M)
    if m: rid_var=m.group(1)
    path_var="path"
    m = re.search(r"^\s*([a-zA-Z_]\w*)\s*=\s*request\.args\.get\(\s*['\"]path['\"]", seg_txt, flags=re.M)
    if m: path_var=m.group(1)

    run_dir_var="run_dir"
    # prefer explicit assignment
    m = re.search(r"^\s*([a-zA-Z_]\w*)\s*=\s*.*\bget_run_dir\b", seg_txt, flags=re.M)
    if m: run_dir_var=m.group(1)
    elif re.search(r"\brun_dir\b", seg_txt): run_dir_var="run_dir"

    # find filepath assignment: fp = os.path.join(run_dir, path)
    fp_var=None
    join_rx = re.compile(r"^\s*([a-zA-Z_]\w*)\s*=\s*os\.path\.join\(\s*"+re.escape(run_dir_var)+r"\s*,\s*"+re.escape(path_var)+r"\s*\)\s*$", re.M)
    m = join_rx.search(seg_txt)
    if m:
        fp_var = m.group(1)

    # fallback: any os.path.join( run_dir , path ) assignment
    if not fp_var:
        join_rx2 = re.compile(r"^\s*([a-zA-Z_]\w*)\s*=\s*os\.path\.join\(\s*([a-zA-Z_]\w*)\s*,\s*([a-zA-Z_]\w*)\s*\)\s*$", re.M)
        m2 = join_rx2.search(seg_txt)
        if m2:
            fp_var = m2.group(1)
            run_dir_var = m2.group(2)
            path_var = m2.group(3)

    if not fp_var:
        print("[ERR] cannot locate filepath assignment os.path.join(run_dir, path) in", fp)
        return False

    # insertion point: right after that assignment line (within seg)
    ins_k=None
    for k,l in enumerate(seg):
        if re.search(rf"^\s*{re.escape(fp_var)}\s*=\s*os\.path\.join\(", l):
            ins_k=k+1; break
    if ins_k is None:
        print("[ERR] cannot find insertion point line in seg for", fp)
        return False

    indent_in = def_indent + "  "  # function body indentation (2 spaces used in some files; ok even if 4? We'll derive from next line)
    # better: infer indent from first non-empty line after def
    for t in range(1, min(25, len(seg))):
        if seg[t].strip():
            indent_in = re.match(r"^(\s*)", seg[t]).group(1)
            break

    inj = (
f"{indent_in}# {MARK}\n"
f"{indent_in}from flask import jsonify\n"
f"{indent_in}import os, time\n"
f"{indent_in}# P0: never 500 on missing file; autogen core audit files\n"
f"{indent_in}if not os.path.exists({fp_var}):\n"
f"{indent_in}  if {path_var} in ('run_manifest.json','run_evidence_index.json'):\n"
f"{indent_in}    files=[]\n"
f"{indent_in}    try:\n"
f"{indent_in}      for root, dirs, fns in os.walk({run_dir_var}):\n"
f"{indent_in}        bn=os.path.basename(root)\n"
f"{indent_in}        if bn in ('node_modules','.git','__pycache__'): continue\n"
f"{indent_in}        for fn in fns:\n"
f"{indent_in}          fp2=os.path.join(root, fn)\n"
f"{indent_in}          rel=os.path.relpath(fp2, {run_dir_var}).replace('\\\\','/')\n"
f"{indent_in}          try:\n"
f"{indent_in}            st=os.stat(fp2)\n"
f"{indent_in}            files.append({{'path':rel,'size':int(st.st_size),'mtime':int(st.st_mtime)}})\n"
f"{indent_in}          except Exception:\n"
f"{indent_in}            files.append({{'path':rel}})\n"
f"{indent_in}      files.sort(key=lambda x: x.get('path',''))\n"
f"{indent_in}    except Exception:\n"
f"{indent_in}      files=[]\n"
f"{indent_in}    obj={{\n"
f"{indent_in}      'rid': str({rid_var}),\n"
f"{indent_in}      'generated_at': int(time.time()),\n"
f"{indent_in}      'run_dir': str({run_dir_var}),\n"
f"{indent_in}      'files_total': len(files),\n"
f"{indent_in}      'files': files,\n"
f"{indent_in}      'note': 'auto-generated (P0) because file was missing'\n"
f"{indent_in}    }}\n"
f"{indent_in}    # persist best-effort\n"
f"{indent_in}    try:\n"
f"{indent_in}      os.makedirs(os.path.dirname({fp_var}), exist_ok=True)\n"
f"{indent_in}      import json\n"
f"{indent_in}      with open({fp_var}, 'w', encoding='utf-8') as f:\n"
f"{indent_in}        json.dump(obj, f, ensure_ascii=False, indent=2)\n"
f"{indent_in}    except Exception:\n"
f"{indent_in}      pass\n"
f"{indent_in}    return jsonify(obj), 200\n"
f"{indent_in}  # optional reports missing => 404 (NOT 500)\n"
f"{indent_in}  return jsonify({{'ok': False, 'err': 'not found', 'rid': str({rid_var}), 'path': str({path_var})}}), 404\n"
    )

    # insert
    seg.insert(ins_k, inj)
    lines[def_i:end_i] = seg

    s2="".join(lines)

    # backup & write
    ts=time.strftime("%Y%m%d_%H%M%S")
    bak=fp.with_name(fp.name+f".bak_missguard_{ts}")
    bak.write_text(s, encoding="utf-8")
    fp.write_text(s2, encoding="utf-8")
    print("[BACKUP]", bak)
    print("[OK] patched:", fp, "fp_var=", fp_var, "run_dir_var=", run_dir_var, "path_var=", path_var, "rid_var=", rid_var)
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
