#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need systemctl

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
MARK="VSP_P0_RUNFILEALLOW_MISSING_GUARD_AUTOGEN_CORE_V3"

restore_latest_compiling(){
  local f="$1"
  python3 - <<PY
from pathlib import Path
import py_compile, sys
f=Path("$f")
# if current compiles, keep it
try:
  py_compile.compile(str(f), doraise=True)
  print("[OK] current compiles:", f)
  sys.exit(0)
except Exception:
  pass

baks = sorted(f.parent.glob(f.name + ".bak_*"), key=lambda p: p.stat().st_mtime, reverse=True)
for p in baks:
  try:
    py_compile.compile(str(p), doraise=True)
    print(str(p))
    sys.exit(0)
  except Exception:
    continue
print("")
sys.exit(1)
PY
}

apply_patch(){
  local f="$1"
  python3 - <<'PY'
from pathlib import Path
import re, time, sys

MARK="VSP_P0_RUNFILEALLOW_MISSING_GUARD_AUTOGEN_CORE_V3"
fp = Path(sys.argv[1])
s = fp.read_text(encoding="utf-8", errors="replace")
if MARK in s:
    print("[OK] marker exists:", fp)
    sys.exit(0)

lines = s.splitlines(True)

# find vsp_run_file_allow_v5()
def_i=None
for i,l in enumerate(lines):
    if re.match(r"^\s*def\s+vsp_run_file_allow_v5\s*\(\s*\)\s*:", l):
        def_i=i; break
if def_i is None:
    print("[ERR] no vsp_run_file_allow_v5 in", fp)
    sys.exit(2)

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

# locate _fp assignment line and its indent (THIS is the key fix)
fp_line_k=None
fp_var="_fp"
run_dir_var="_run_dir"
path_var="path"
rid_var="rid"

# detect vars in this function
seg_txt="".join(seg)
m=re.search(r"^\s*([a-zA-Z_]\w*)\s*=\s*request\.args\.get\(\s*['\"]rid['\"]", seg_txt, re.M)
if m: rid_var=m.group(1)
m=re.search(r"^\s*([a-zA-Z_]\w*)\s*=\s*request\.args\.get\(\s*['\"]path['\"]", seg_txt, re.M)
if m: path_var=m.group(1)

# find _fp = os.path.join(_run_dir, path) and infer names
rx=re.compile(r"^(\s*)([a-zA-Z_]\w*)\s*=\s*os\.path\.join\(\s*([a-zA-Z_]\w*)\s*,\s*([a-zA-Z_]\w*)\s*\)\s*$")
for k,l in enumerate(seg):
    mm=rx.match(l)
    if mm:
        fp_line_k=k
        indent_fp=mm.group(1)
        fp_var=mm.group(2)
        run_dir_var=mm.group(3)
        path_var=mm.group(4)
        break

if fp_line_k is None:
    print("[ERR] cannot find _fp=os.path.join(...) line in", fp)
    sys.exit(2)

inj = (
f"{indent_fp}# {MARK}\n"
f"{indent_fp}try:\n"
f"{indent_fp}  import os, time, json\n"
f"{indent_fp}  from flask import jsonify\n"
f"{indent_fp}  if not os.path.exists({fp_var}):\n"
f"{indent_fp}    # core audit files: autogen + persist + 200\n"
f"{indent_fp}    if {path_var} in ('run_manifest.json','run_evidence_index.json'):\n"
f"{indent_fp}      files=[]\n"
f"{indent_fp}      try:\n"
f"{indent_fp}        for root, dirs, fns in os.walk({run_dir_var}):\n"
f"{indent_fp}          bn=os.path.basename(root)\n"
f"{indent_fp}          if bn in ('node_modules','.git','__pycache__'): continue\n"
f"{indent_fp}          for fn in fns:\n"
f"{indent_fp}            fp2=os.path.join(root, fn)\n"
f"{indent_fp}            rel=os.path.relpath(fp2, {run_dir_var}).replace('\\\\','/')\n"
f"{indent_fp}            try:\n"
f"{indent_fp}              st=os.stat(fp2)\n"
f"{indent_fp}              files.append({{'path':rel,'size':int(st.st_size),'mtime':int(st.st_mtime)}})\n"
f"{indent_fp}            except Exception:\n"
f"{indent_fp}              files.append({{'path':rel}})\n"
f"{indent_fp}        files.sort(key=lambda x: x.get('path',''))\n"
f"{indent_fp}      except Exception:\n"
f"{indent_fp}        files=[]\n"
f"{indent_fp}      obj={{'rid':str({rid_var}), 'generated_at':int(time.time()), 'run_dir':str({run_dir_var}), 'files_total':len(files), 'files':files}}\n"
f"{indent_fp}      if {path_var}=='run_evidence_index.json':\n"
f"{indent_fp}        # minimal evidence contract\n"
f"{indent_fp}        required=['run_gate.json','run_gate_summary.json','findings_unified.json','run_manifest.json','run_evidence_index.json','reports/findings_unified.csv','reports/findings_unified.sarif','reports/findings_unified.html']\n"
f"{indent_fp}        present=[]; missing=[]\n"
f"{indent_fp}        for r in required:\n"
f"{indent_fp}          (present if os.path.exists(os.path.join({run_dir_var}, r)) else missing).append(r)\n"
f"{indent_fp}        obj.update({{'required':required,'present':present,'missing':missing,'audit_ready':(len(missing)==0)}})\n"
f"{indent_fp}      obj['note']='auto-generated (P0)'\n"
f"{indent_fp}      try:\n"
f"{indent_fp}        os.makedirs(os.path.dirname({fp_var}), exist_ok=True)\n"
f"{indent_fp}        with open({fp_var}, 'w', encoding='utf-8') as f:\n"
f"{indent_fp}          json.dump(obj, f, ensure_ascii=False, indent=2)\n"
f"{indent_fp}      except Exception:\n"
f"{indent_fp}        pass\n"
f"{indent_fp}      return jsonify(obj), 200\n"
f"{indent_fp}    # optional files missing => 404 (never 500)\n"
f"{indent_fp}    return jsonify({{'ok':False,'err':'not found','rid':str({rid_var}),'path':str({path_var})}}), 404\n"
f"{indent_fp}except Exception:\n"
f"{indent_fp}  # fallback: never raise 500 here\n"
f"{indent_fp}  try:\n"
f"{indent_fp}    from flask import jsonify\n"
f"{indent_fp}    return jsonify({{'ok':False,'err':'internal error','rid':str({rid_var}),'path':str({path_var})}}), 500\n"
f"{indent_fp}  except Exception:\n"
f"{indent_fp}    return ('internal error', 500)\n"
)

# insert right after _fp line
seg.insert(fp_line_k+1, inj)
lines[def_i:end_i]=seg
s2="".join(lines)

bak = fp.with_name(fp.name + f".bak_fixv3_{time.strftime('%Y%m%d_%H%M%S')}")
bak.write_text(s, encoding="utf-8")
fp.write_text(s2, encoding="utf-8")
print("[BACKUP]", bak)
print("[OK] patched", fp, "indent_len=", len(indent_fp), "fp_var=", fp_var)
PY "$f"
}

for f in vsp_demo_app.py wsgi_vsp_ui_gateway.py; do
  echo "== restore check: $f =="
  GOOD="$(restore_latest_compiling "$f" || true)"
  if [[ "$GOOD" == *.bak_* ]]; then
    echo "[RESTORE] $f <= $GOOD"
    cp -f "$GOOD" "$f"
  else
    echo "$GOOD"
  fi
done

echo "== apply patch v3 =="
apply_patch vsp_demo_app.py
apply_patch wsgi_vsp_ui_gateway.py

echo "== py_compile =="
python3 -m py_compile vsp_demo_app.py
python3 -m py_compile wsgi_vsp_ui_gateway.py

echo "== restart =="
systemctl restart "$SVC"

echo "== smoke =="
bash bin/p0_dashboard_smoke_contract_v1.sh
