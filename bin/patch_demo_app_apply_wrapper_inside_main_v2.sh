#!/usr/bin/env bash
set -euo pipefail
F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_apply_main_v2_${TS}"
echo "[BACKUP] $F.bak_apply_main_v2_${TS}"

python3 - <<'PY'
import re
from pathlib import Path

p = Path("vsp_demo_app.py")
txt = p.read_text(encoding="utf-8", errors="ignore")

MARK = "VSP_DEMOAPP_APPLY_WRAPPER_IN_MAIN_V2"

# 1) remove any previous APPLY blocks we inserted (avoid breaking app.run)
txt = re.sub(r"\n# VSP_DEMOAPP_FORCE_UIREQ_BOOTSTRAP_V1 APPLY[\s\S]*?# END VSP_DEMOAPP_FORCE_UIREQ_BOOTSTRAP_V1 APPLY\n",
             "\n", txt, flags=re.M)

# 2) Ensure helper/installer block exists (from your previous patch). If not, abort safely.
if "_vsp_demoapp_install_uireq_wrappers_v1" not in txt:
    raise SystemExit("[ERR] helper _vsp_demoapp_install_uireq_wrappers_v1 not found. Re-apply helper patch first.")

# 3) Find __main__ block
m_main = re.search(r'^(?P<ind>\s*)if\s+__name__\s*==\s*["\']__main__["\']\s*:\s*$',
                   txt, flags=re.M)
if not m_main:
    raise SystemExit("[ERR] cannot find if __name__ == '__main__': block")

main_indent = m_main.group("ind")
call_indent = main_indent + "  "  # 2 spaces inside main

apply_block = f"""
{main_indent}# {MARK}
{call_indent}try:
{call_indent}  _vsp_demoapp_install_uireq_wrappers_v1(app)
{call_indent}except Exception as e:
{call_indent}  try:
{call_indent}    print("[{MARK}] APPLY FAILED:", e)
{call_indent}  except Exception:
{call_indent}    pass
{main_indent}# END {MARK}
"""

# 4) Insert right after __main__ line (only once)
insert_at = m_main.end()
txt = txt[:insert_at] + apply_block + txt[insert_at:]

p.write_text(txt, encoding="utf-8")
print("[OK] patched:", MARK)
PY

python3 -m py_compile "$F"
echo "[OK] py_compile OK"
