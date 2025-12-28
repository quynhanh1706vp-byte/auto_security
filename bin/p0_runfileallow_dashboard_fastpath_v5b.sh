#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need systemctl

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
FILES=(vsp_demo_app.py wsgi_vsp_ui_gateway.py)
MARK="VSP_P0_DASHBOARD_FASTPATH_V5B"

python3 - <<'PY'
from pathlib import Path
import re, time, py_compile

FILES=[Path("vsp_demo_app.py"), Path("wsgi_vsp_ui_gateway.py")]
MARK="VSP_P0_DASHBOARD_FASTPATH_V5B"

def patch_one(fp: Path) -> bool:
    s = fp.read_text(encoding="utf-8", errors="replace")
    # replace old resolver block inside V5 marker if exists
    if "VSP_P0_DASHBOARD_FASTPATH_V5" not in s and MARK not in s:
        print("[WARN] fastpath v5 not found in", fp)
        return False

    # We patch by inserting a small override resolver function block right after the fastpath marker line.
    # This avoids risky regex surgery inside huge injected block.
    lines = s.splitlines(True)

    # find line containing fastpath marker (either V5 or V5B)
    idx=None
    for i,l in enumerate(lines):
        if "VSP_P0_DASHBOARD_FASTPATH_V5" in l or "VSP_P0_DASHBOARD_FASTPATH_V5B" in l:
            idx=i
            break
    if idx is None:
        print("[ERR] cannot locate fastpath marker line in", fp)
        return False

    # determine indent of that line
    indent = re.match(r"^(\s*)", lines[idx]).group(1)

    if any(MARK in l for l in lines):
        print("[OK] already patched v5b:", fp)
        return False

    override = f"""{indent}# {MARK}
{indent}try:
{indent}  # override resolver: prefer gate_root_{rid} and deep scan out_ci/out
{indent}  def _vsp_p0_resolve_run_dir(_rid: str) -> str:  # noqa: F811 (intentional override)
{indent}    if not _rid:
{indent}      return ""
{indent}    from pathlib import Path as _P
{indent}    import os
{indent}    here = _P(__file__).resolve()
{indent}    bundle_root = here.parent.parent  # SECURITY_BUNDLE
{indent}    targets = []
{indent}    # common roots
{indent}    targets += [bundle_root / "out_ci", bundle_root / "out"]
{indent}    # also try alongside UI folder (some deployments keep out_ci under ui/)
{indent}    targets += [here.parent / "out_ci", here.parent / "out"]
{indent}    # prefer exact gate_root naming (your smoke prints gate_root_* already)
{indent}    want_names = [f"gate_root_{{_rid}}", _rid]
{indent}    for base in targets:
{indent}      try:
{indent}        if not base.exists():
{indent}          continue
{indent}        # 1) direct children exact match
{indent}        for nm in want_names:
{indent}          cand = base / nm
{indent}          if cand.is_dir() and ((cand/"run_gate.json").exists() or (cand/"run_gate_summary.json").exists() or (cand/"findings_unified.json").exists()):
{indent}            return str(cand)
{indent}        # 2) deep scan 2 levels (out_ci/VSP/gate_root_*)
{indent}        for nm in want_names:
{indent}          for cand in base.glob(f"*/{{nm}}"):
{indent}            try:
{indent}              if cand.is_dir() and ((cand/"run_gate.json").exists() or (cand/"run_gate_summary.json").exists() or (cand/"findings_unified.json").exists()):
{indent}                return str(cand)
{indent}            except Exception:
{indent}              continue
{indent}        # 3) fallback: any dir contains rid and key files
{indent}        for cand in base.glob(f"**/*{{_rid}}*"):
{indent}          try:
{indent}            if cand.is_dir() and ((cand/"run_gate.json").exists() or (cand/"run_gate_summary.json").exists() or (cand/"findings_unified.json").exists()):
{indent}              return str(cand)
{indent}          except Exception:
{indent}            continue
{indent}      except Exception:
{indent}        continue
{indent}    return ""
{indent}except Exception:
{indent}  pass
"""

    # insert override right after marker line
    lines.insert(idx+1, override)

    # also adjust fastpath behavior: core should never 404 when run_dir not found
    # We do a small targeted replace if present:
    s2="".join(lines)
    s2 = s2.replace(
        "if path in _P0_CORE:\n        # return 200 so Dashboard doesn't break; caller can see run_dir missing\n        obj = {",
        "if path in _P0_CORE:\n        # P0 contract: core must be 200 even if run_dir unresolved\n        obj = {"
    )

    bak = fp.with_name(fp.name + f".bak_fastpath_v5b_{time.strftime('%Y%m%d_%H%M%S')}")
    bak.write_text(s, encoding="utf-8")
    fp.write_text(s2, encoding="utf-8")
    print("[BACKUP]", bak)
    print("[OK] patched v5b:", fp)
    return True

changed=False
for f in FILES:
    changed = patch_one(f) or changed

for f in FILES:
    py_compile.compile(str(f), doraise=True)
PY

echo "== restart =="
systemctl restart "$SVC"

echo "== smoke =="
bash bin/p0_dashboard_smoke_contract_v1.sh
