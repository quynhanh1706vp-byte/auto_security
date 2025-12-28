#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need systemctl

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"

python3 - <<'PY'
from pathlib import Path
import py_compile, re, time, sys

FILES=[Path("vsp_demo_app.py"), Path("wsgi_vsp_ui_gateway.py")]

MARK_ALLOW="VSP_P0_ALLOW_EXTRAS_V4C"
MARK_RUNDIR="VSP_P0_RUN_DIR_GUARD_V4C"
MARK_MISSING="VSP_P0_MISSING_FILE_GUARD_V4C"

EXTRAS=["run_manifest.json","run_evidence_index.json","reports/findings_unified.sarif"]
REQ=[
  "run_gate.json","run_gate_summary.json","findings_unified.json",
  "run_manifest.json","run_evidence_index.json",
  "reports/findings_unified.csv","reports/findings_unified.sarif","reports/findings_unified.html"
]

def compile_ok(p: Path) -> bool:
    try:
        py_compile.compile(str(p), doraise=True)
        return True
    except Exception:
        return False

def restore_if_broken(p: Path):
    if not p.exists():
        print("[SKIP] missing:", p); return
    if compile_ok(p):
        print("[OK] compiles:", p); return
    baks = sorted(p.parent.glob(p.name + ".bak_*"), key=lambda x: x.stat().st_mtime, reverse=True)
    for b in baks:
        if compile_ok(b):
            snap = p.with_name(p.name + f".broken_{time.strftime('%Y%m%d_%H%M%S')}")
            snap.write_text(p.read_text(encoding="utf-8", errors="replace"), encoding="utf-8")
            p.write_text(b.read_text(encoding="utf-8", errors="replace"), encoding="utf-8")
            print("[RESTORE]", p, "<=", b, "(snapshot:", snap, ")")
            return
    raise SystemExit(f"[ERR] {p} does not compile and no compiling backup found")

def find_func_block(lines, funcname):
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

def patch_file(p: Path):
    s = p.read_text(encoding="utf-8", errors="replace")
    lines = s.splitlines(True)
    blk = find_func_block(lines, "vsp_run_file_allow_v5")
    if not blk:
        print("[WARN] no vsp_run_file_allow_v5 in", p); return False
    def_i, end_i = blk
    seg = lines[def_i:end_i]
    seg_txt = "".join(seg)

    # detect rid/path vars
    rid_var="rid"
    m=re.search(r"^\s*([a-zA-Z_]\w*)\s*=\s*request\.args\.get\(\s*['\"]rid['\"]", seg_txt, re.M)
    if m: rid_var=m.group(1)
    path_var="path"
    m=re.search(r"^\s*([a-zA-Z_]\w*)\s*=\s*request\.args\.get\(\s*['\"]path['\"]", seg_txt, re.M)
    if m: path_var=m.group(1)

    changed=False

    # 1) ensure allow extras (avoid 403 regression after restore)
    if MARK_ALLOW not in seg_txt:
        # insert after first ALLOW assignment if exists
        allow_k=None
        allow_indent=None
        for k,l in enumerate(seg):
            mm=re.match(r"^(\s*)ALLOW\s*=", l)
            if mm:
                allow_k=k+1
                allow_indent=mm.group(1)
                break
        if allow_k is not None:
            inj = (
                f"{allow_indent}# {MARK_ALLOW}\n"
                f"{allow_indent}try:\n"
                f"{allow_indent}  ALLOW.update({{{', '.join([repr(x) for x in EXTRAS])}}})\n"
                f"{allow_indent}except Exception:\n"
                f"{allow_indent}  pass\n"
            )
            seg.insert(allow_k, inj)
            changed=True

    # re-evaluate seg_txt after potential insert
    seg_txt="".join(seg)

    # 2) find _run_dir assignment line; insert guard AFTER it (safe, không chen giữa if và body)
    if MARK_RUNDIR not in seg_txt:
        run_k=None
        run_indent=None
        run_dir_var="_run_dir"
        for k,l in enumerate(seg):
            mm=re.match(r"^(\s*)(_run_dir)\s*=\s*", l)
            if mm:
                run_k=k+1
                run_indent=mm.group(1)
                run_dir_var=mm.group(2)
                break
        if run_k is not None:
            req_list = "[" + ",".join([repr(x) for x in REQ]) + "]"
            inj = (
                f"{run_indent}# {MARK_RUNDIR}\n"
                f"{run_indent}try:\n"
                f"{run_indent}  import os, time\n"
                f"{run_indent}  from flask import jsonify\n"
                f"{run_indent}  _rd = {run_dir_var}\n"
                f"{run_indent}  if (not _rd) or (not os.path.isdir(str(_rd))):\n"
                f"{run_indent}    if {path_var} in ('run_manifest.json','run_evidence_index.json'):\n"
                f"{run_indent}      obj={{'rid':str({rid_var}),'generated_at':int(time.time()),'run_dir':str(_rd),'note':'run_dir missing (P0)','required':{req_list},'present':[],'missing':{req_list},'audit_ready':False}}\n"
                f"{run_indent}      return jsonify(obj), 200\n"
                f"{run_indent}    return jsonify({{'ok':False,'err':'run_dir not found','rid':str({rid_var}),'path':str({path_var}),'run_dir':str(_rd)}}), 404\n"
                f"{run_indent}except Exception:\n"
                f"{run_indent}  pass\n"
            )
            seg.insert(run_k, inj)
            changed=True

    # re-evaluate seg_txt again
    seg_txt="".join(seg)

    # 3) find _fp join line; insert missing-file guard AFTER it
    if MARK_MISSING not in seg_txt:
        fp_k=None
        fp_indent=None
        fp_var="_fp"
        run_dir_var="_run_dir"
        # detect join line and var names
        rx = re.compile(r"^(\s*)([a-zA-Z_]\w*)\s*=\s*os\.path\.join\(\s*([a-zA-Z_]\w*)\s*,\s*([a-zA-Z_]\w*)\s*\)\s*$")
        for k,l in enumerate(seg):
            mm=rx.match(l)
            if mm:
                fp_k=k+1
                fp_indent=mm.group(1)
                fp_var=mm.group(2)
                run_dir_var=mm.group(3)
                path_var=mm.group(4)
                break
        if fp_k is not None:
            inj = (
                f"{fp_indent}# {MARK_MISSING}\n"
                f"{fp_indent}try:\n"
                f"{fp_indent}  import os, time, json\n"
                f"{fp_indent}  from flask import jsonify\n"
                f"{fp_indent}  if not os.path.exists({fp_var}):\n"
                f"{fp_indent}    if {path_var} in ('run_manifest.json','run_evidence_index.json'):\n"
                f"{fp_indent}      files=[]\n"
                f"{fp_indent}      try:\n"
                f"{fp_indent}        for root, dirs, fns in os.walk({run_dir_var}):\n"
                f"{fp_indent}          bn=os.path.basename(root)\n"
                f"{fp_indent}          if bn in ('node_modules','.git','__pycache__'): continue\n"
                f"{fp_indent}          for fn in fns:\n"
                f"{fp_indent}            fp2=os.path.join(root, fn)\n"
                f"{fp_indent}            rel=os.path.relpath(fp2, {run_dir_var}).replace('\\\\','/')\n"
                f"{fp_indent}            try:\n"
                f"{fp_indent}              st=os.stat(fp2)\n"
                f"{fp_indent}              files.append({{'path':rel,'size':int(st.st_size),'mtime':int(st.st_mtime)}})\n"
                f"{fp_indent}            except Exception:\n"
                f"{fp_indent}              files.append({{'path':rel}})\n"
                f"{fp_indent}        files.sort(key=lambda x: x.get('path',''))\n"
                f"{fp_indent}      except Exception:\n"
                f"{fp_indent}        files=[]\n"
                f"{fp_indent}      obj={{'rid':str({rid_var}), 'generated_at':int(time.time()), 'run_dir':str({run_dir_var}), 'files_total':len(files), 'files':files, 'note':'auto-generated (P0)'}}\n"
                f"{fp_indent}      if {path_var}=='run_evidence_index.json':\n"
                f"{fp_indent}        required={ '[' + ','.join([repr(x) for x in REQ]) + ']' }\n"
                f"{fp_indent}        present=[]; missing=[]\n"
                f"{fp_indent}        for r in required:\n"
                f"{fp_indent}          (present if os.path.exists(os.path.join({run_dir_var}, r)) else missing).append(r)\n"
                f"{fp_indent}        obj.update({{'required':required,'present':present,'missing':missing,'audit_ready':(len(missing)==0)}})\n"
                f"{fp_indent}      try:\n"
                f"{fp_indent}        os.makedirs(os.path.dirname({fp_var}), exist_ok=True)\n"
                f"{fp_indent}        with open({fp_var}, 'w', encoding='utf-8') as f:\n"
                f"{fp_indent}          json.dump(obj, f, ensure_ascii=False, indent=2)\n"
                f"{fp_indent}      except Exception:\n"
                f"{fp_indent}        pass\n"
                f"{fp_indent}      return jsonify(obj), 200\n"
                f"{fp_indent}    return jsonify({{'ok':False,'err':'not found','rid':str({rid_var}),'path':str({path_var})}}), 404\n"
                f"{fp_indent}except Exception:\n"
                f"{fp_indent}  pass\n"
            )
            seg.insert(fp_k, inj)
            changed=True

    if not changed:
        print("[INFO] no patch needed:", p)
        return False

    # write back with backup
    s2 = "".join(lines[:def_i] + seg + lines[end_i:])
    bak = p.with_name(p.name + f".bak_v4c_{time.strftime('%Y%m%d_%H%M%S')}")
    bak.write_text(s, encoding="utf-8")
    p.write_text(s2, encoding="utf-8")
    print("[BACKUP]", bak)
    print("[OK] patched:", p)
    return True

for f in FILES:
    restore_if_broken(f)

any_change=False
for f in FILES:
    any_change = patch_file(f) or any_change

PY
PY

echo "== py_compile =="
python3 -m py_compile vsp_demo_app.py
python3 -m py_compile wsgi_vsp_ui_gateway.py

echo "== restart =="
systemctl restart "$SVC"

echo "== smoke =="
bash bin/p0_dashboard_smoke_contract_v1.sh
