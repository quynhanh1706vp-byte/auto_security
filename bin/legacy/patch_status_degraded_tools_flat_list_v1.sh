#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_degraded_flat_${TS}"
echo "[BACKUP] $F.bak_degraded_flat_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("vsp_demo_app.py")
txt = p.read_text(encoding="utf-8", errors="ignore")

# 1) Force helper _vsp__read_degraded_tools_from_ci to ALWAYS return list (items)
txt2 = re.sub(
    r"def _vsp__read_degraded_tools_from_ci\(_ci_run_dir\):[\s\S]*?return _d",
    """def _vsp__read_degraded_tools_from_ci(_ci_run_dir):
    if not _ci_run_dir:
        return []
    _f = _Path(_ci_run_dir) / "degraded_tools.json"
    if not _f.exists():
        return []
    _d = _vsp__safe_read_json_file(_f)
    # normalize to list
    if isinstance(_d, dict):
        items = _d.get("items")
        return items if isinstance(items, list) else []
    if isinstance(_d, list):
        return _d
    return []""",
    txt,
    count=1
)

if txt2 == txt:
    print("[WARN] could not rewrite helper by regex; will patch wrapper normalization only")
    txt2 = txt

# 2) In wrapper: if degraded_tools is dict(ok/items) -> replace with items list
if "VSP_STATUS_READ_DEGRADED_TOOLS_V1" not in txt2:
    raise SystemExit("[ERR] missing VSP_STATUS_READ_DEGRADED_TOOLS_V1 block (your file differs)")

# inject a small normalization right after degraded_tools assignment (best effort)
needle = "data['degraded_tools'] = _vsp__read_degraded_tools_from_ci(_ci)"
if needle in txt2 and "VSP_DEGRADED_TOOLS_FLATTEN_V1" not in txt2:
    txt2 = txt2.replace(
        needle,
        needle + "\n" +
        "    # VSP_DEGRADED_TOOLS_FLATTEN_V1\n"
        "    try:\n"
        "      if isinstance(data.get('degraded_tools'), dict) and isinstance(data['degraded_tools'].get('items'), list):\n"
        "        data['degraded_tools'] = data['degraded_tools']['items']\n"
        "    except Exception:\n"
        "      pass\n"
    )

p.write_text(txt2, encoding="utf-8")
print("[OK] patched degraded_tools normalization to flat list")
PY

python3 -m py_compile "$F" >/dev/null
echo "[OK] py_compile OK"
echo "[NEXT] restart: ./bin/start_8910_clean_v2.sh"
