#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need systemctl

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"

FILES=(vsp_demo_app.py wsgi_vsp_ui_gateway.py)
MARK="VSP_P0_RUNFILEALLOW_CONTRACT_ALLOW_UPDATE_V5"
EXTRA_JSON='{"run_manifest.json","run_evidence_index.json","reports/findings_unified.sarif"}'

python3 - <<'PY'
from pathlib import Path
import re, time, sys

MARK = "VSP_P0_RUNFILEALLOW_CONTRACT_ALLOW_UPDATE_V5"
EXTRAS = ["run_manifest.json","run_evidence_index.json","reports/findings_unified.sarif"]

def patch_file(fp: Path) -> bool:
    if not fp.exists():
        print("[SKIP] missing:", fp)
        return False
    s = fp.read_text(encoding="utf-8", errors="replace")
    if MARK in s:
        print("[OK] already patched:", fp)
        return False

    # locate vsp_run_file_allow_v5 definition
    lines = s.splitlines(True)
    def_i = None
    for i,l in enumerate(lines):
        if re.match(r"^\s*def\s+vsp_run_file_allow_v5\s*\(\s*\)\s*:", l):
            def_i = i
            break
    if def_i is None:
        print("[WARN] no vsp_run_file_allow_v5() in", fp)
        return False

    indent = re.match(r"^(\s*)def\s", lines[def_i]).group(1)
    ind_len = len(indent)

    # find end of function block
    end_i = len(lines)
    for j in range(def_i+1, len(lines)):
        lj = lines[j]
        if lj.strip()=="":
            continue
        ind2 = len(re.match(r"^(\s*)", lj).group(1))
        if ind2 <= ind_len and (re.match(r"^\s*def\s+\w+\s*\(", lj) or re.match(r"^\s*@", lj)):
            end_i = j
            break

    seg = lines[def_i:end_i]
    seg_txt = "".join(seg)

    # identify path variable (usually: path = request.args.get("path",...))
    pathvar = "path"
    m = re.search(r"^\s*([a-zA-Z_]\w*)\s*=\s*request\.args\.get\(\s*['\"]path['\"]", seg_txt, flags=re.M)
    if m:
        pathvar = m.group(1)

    # find where ALLOW is defined; inject right after first "ALLOW" assignment if possible,
    # else inject right after path assignment line.
    inj = (
        f"{indent}    # {MARK}: dashboard contract whitelist\n"
        f"{indent}    try:\n"
        f"{indent}        ALLOW.update({{{', '.join([repr(x) for x in EXTRAS])}}})\n"
        f"{indent}    except Exception:\n"
        f"{indent}        pass\n"
    )

    # locate insertion point
    insert_at = None
    for k,l in enumerate(seg):
        if re.match(r"^\s*ALLOW\s*=\s*", l):
            insert_at = k+1
            break
    if insert_at is None:
        # after path assignment
        rx = re.compile(r"^\s*"+re.escape(pathvar)+r"\s*=\s*request\.args\.get\(\s*['\"]path['\"]")
        for k,l in enumerate(seg):
            if rx.search(l):
                insert_at = k+1
                break
    if insert_at is None:
        # fallback: after def line
        insert_at = 1

    # ensure we don't inject twice if already contains one of extras in ALLOW literal
    if any(x in seg_txt for x in EXTRAS):
        # still inject (idempotent) would be okay, but avoid changing behavior unexpectedly
        # If already present, do nothing
        print("[OK] extras already present (skip inject):", fp)
        return False

    seg.insert(insert_at, inj)
    lines[def_i:end_i] = seg
    s2 = "".join(lines)

    # backup & write
    ts = time.strftime("%Y%m%d_%H%M%S")
    bak = fp.with_name(fp.name + f".bak_allowv5_{ts}")
    bak.write_text(s, encoding="utf-8")
    fp.write_text(s2, encoding="utf-8")
    print("[BACKUP]", bak)
    print("[OK] patched:", fp, "pathvar=", pathvar)
    return True

changed = False
for name in ["vsp_demo_app.py","wsgi_vsp_ui_gateway.py"]:
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
