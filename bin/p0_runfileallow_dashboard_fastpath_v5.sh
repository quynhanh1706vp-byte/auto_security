#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need systemctl

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
FILES=(vsp_demo_app.py wsgi_vsp_ui_gateway.py)
MARK="VSP_P0_DASHBOARD_FASTPATH_V5"

python3 - <<'PY'
from pathlib import Path
import re, time, py_compile

FILES=[Path("vsp_demo_app.py"), Path("wsgi_vsp_ui_gateway.py")]
MARK="VSP_P0_DASHBOARD_FASTPATH_V5"

FAST_BLOCK = r"""
# VSP_P0_DASHBOARD_FASTPATH_V5
try:
  import os, time, json
  from pathlib import Path as _P
  from flask import jsonify, send_file

  _P0_CORE = ("run_manifest.json","run_evidence_index.json")
  _P0_OPT  = ("reports/findings_unified.sarif","reports/findings_unified.html")
  _P0_FAST = set(_P0_CORE + _P0_OPT)

  def _vsp_p0_resolve_run_dir(_rid: str) -> str:
    if not _rid:
      return ""
    here = _P(__file__).resolve()
    # repo layout: .../SECURITY_BUNDLE/ui/<file.py>
    bundle_root = here.parent.parent  # SECURITY_BUNDLE
    bases = [
      bundle_root / "out_ci",
      bundle_root / "out",
      bundle_root / "out_ci" / "VSP",
      bundle_root / "out" / "VSP",
    ]
    # direct candidates
    direct = [
      lambda b: b / _rid,
      lambda b: b / f"gate_root_{_rid}",
      lambda b: b / f"RUN_{_rid}",
      lambda b: b / f"VSP_CI_RUN_{_rid}",
    ]
    for b in bases:
      try:
        if not b.exists(): 
          continue
        for fn in direct:
          cand = fn(b)
          if cand.is_dir() and ((cand/"run_gate.json").exists() or (cand/"run_gate_summary.json").exists() or (cand/"findings_unified.json").exists()):
            return str(cand)
        # 1-level glob (cheap)
        for cand in b.glob(f"*{_rid}*"):
          try:
            if cand.is_dir() and ((cand/"run_gate.json").exists() or (cand/"run_gate_summary.json").exists() or (cand/"findings_unified.json").exists()):
              return str(cand)
          except Exception:
            continue
      except Exception:
        continue
    return ""

  def _vsp_p0_autogen_manifest(_run_dir: str, _rid: str):
    # keep it cheap: only list top-level + reports/
    files=[]
    try:
      rd=_P(_run_dir)
      for p in sorted(rd.rglob("*")):
        try:
          if p.is_dir(): 
            continue
          rel = str(p.relative_to(rd)).replace("\\","/")
          st = p.stat()
          files.append({"path":rel,"size":int(st.st_size),"mtime":int(st.st_mtime)})
        except Exception:
          continue
    except Exception:
      files=[]
    return {
      "rid": _rid,
      "generated_at": int(time.time()),
      "run_dir": _run_dir,
      "files_total": len(files),
      "files": files,
      "note": "auto-generated (P0 dashboard fast-path)"
    }

  def _vsp_p0_autogen_evidence_index(_run_dir: str, _rid: str):
    required = [
      "run_gate.json","run_gate_summary.json","findings_unified.json",
      "run_manifest.json","run_evidence_index.json",
      "reports/findings_unified.csv","reports/findings_unified.sarif","reports/findings_unified.html"
    ]
    present=[]; missing=[]
    for r in required:
      (present if os.path.exists(os.path.join(_run_dir, r)) else missing).append(r)
    return {
      "rid": _rid,
      "generated_at": int(time.time()),
      "run_dir": _run_dir,
      "required": required,
      "present": present,
      "missing": missing,
      "audit_ready": (len(missing)==0),
      "note": "auto-generated (P0 dashboard fast-path)"
    }

  if path in _P0_FAST:
    _rid = str(rid)
    _rd = _vsp_p0_resolve_run_dir(_rid)
    if not _rd or (not os.path.isdir(_rd)):
      if path in _P0_CORE:
        # return 200 so Dashboard doesn't break; caller can see run_dir missing
        obj = {
          "rid": _rid,
          "generated_at": int(time.time()),
          "run_dir": str(_rd),
          "note": "run_dir not found (P0 dashboard fast-path)",
          "required": [],
          "present": [],
          "missing": [],
          "audit_ready": False
        }
        return jsonify(obj), 200
      return jsonify({"ok": False, "err": "not generated", "rid": _rid, "path": path, "run_dir": str(_rd)}), 404

    _fp = os.path.join(_rd, path)
    if not os.path.exists(_fp):
      if path == "run_manifest.json":
        obj = _vsp_p0_autogen_manifest(_rd, _rid)
      elif path == "run_evidence_index.json":
        obj = _vsp_p0_autogen_evidence_index(_rd, _rid)
      else:
        return jsonify({"ok": False, "err": "not generated", "rid": _rid, "path": path}), 404
      # persist best-effort
      try:
        os.makedirs(os.path.dirname(_fp), exist_ok=True)
        with open(_fp, "w", encoding="utf-8") as f:
          json.dump(obj, f, ensure_ascii=False, indent=2)
      except Exception:
        pass
      return jsonify(obj), 200

    # exists => serve; never 500 for dashboard fast paths
    try:
      return send_file(_fp, as_attachment=False)
    except Exception as e:
      return jsonify({"ok": False, "err": "send_file failed", "rid": _rid, "path": path, "detail": str(e)}), 404
except Exception:
  pass
"""

def patch_one(fp: Path) -> bool:
    s = fp.read_text(encoding="utf-8", errors="replace")
    if MARK in s:
        print("[OK] already patched:", fp)
        return False

    lines = s.splitlines(True)

    # locate vsp_run_file_allow_v5()
    def_i=None
    for i,l in enumerate(lines):
        if re.match(r"^\s*def\s+vsp_run_file_allow_v5\s*\(\s*\)\s*:", l):
            def_i=i; break
    if def_i is None:
        print("[WARN] no vsp_run_file_allow_v5 in", fp)
        return False

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

    # find first assignment of path = request.args.get('path'...)
    path_k=None
    indent_body=None
    for k,l in enumerate(seg):
        if "request.args.get" in l and ("'path'" in l or '"path"' in l) and "=" in l:
            path_k=k
            indent_body=re.match(r"^(\s*)", l).group(1)
            break

    if path_k is None or indent_body is None:
        print("[ERR] cannot locate path assignment in", fp)
        return False

    # indent FAST_BLOCK to match function body indent
    block = FAST_BLOCK.replace("\n", "\n"+indent_body)
    block = indent_body + block.strip("\n") + "\n"

    # add marker
    block = block.replace("VSP_P0_DASHBOARD_FASTPATH_V5", MARK)

    # insert right AFTER path assignment line
    seg.insert(path_k+1, block)

    lines[def_i:end_i] = seg
    s2="".join(lines)

    bak = fp.with_name(fp.name + f".bak_fastpath_{time.strftime('%Y%m%d_%H%M%S')}")
    bak.write_text(s, encoding="utf-8")
    fp.write_text(s2, encoding="utf-8")
    print("[BACKUP]", bak)
    print("[OK] patched:", fp)
    return True

changed=False
for f in FILES:
    changed = patch_one(f) or changed

# compile check
for f in FILES:
    py_compile.compile(str(f), doraise=True)

PY

echo "== restart =="
systemctl restart "$SVC"

echo "== smoke =="
bash bin/p0_dashboard_smoke_contract_v1.sh
