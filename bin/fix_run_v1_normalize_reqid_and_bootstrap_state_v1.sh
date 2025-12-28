#!/usr/bin/env bash
set -euo pipefail
F="run_api/vsp_run_api_v1.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_norm_bootstrap_${TS}"
echo "[BACKUP] $F.bak_norm_bootstrap_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("run_api/vsp_run_api_v1.py")
txt = p.read_text(encoding="utf-8", errors="replace")

MARK = "VSP_RUNV1_NORMALIZE_REQID_AND_BOOTSTRAP_STATE_V1"
if MARK in txt:
    print("[OK] already patched:", MARK)
    raise SystemExit(0)

m = re.search(r"^(?P<dindent>[ \t]*)def\s+run_v1\s*\(", txt, flags=re.M)
if not m:
    raise SystemExit("[ERR] cannot find def run_v1(")

dindent = m.group("dindent")
start = m.start()

m2 = re.search(r"^" + re.escape(dindent) + r"def\s+\w+\s*\(", txt[m.end():], flags=re.M)
end = (m.end() + m2.start()) if m2 else len(txt)

fn = txt[start:end]

anchor = re.search(r"(?m)^(?P<indent>[ \t]*)env\[\s*['\"]VSP_UIREQ_ID['\"]\s*\]\s*=\s*req_id\s*$", fn)
if not anchor:
    raise SystemExit("[ERR] cannot find anchor: env['VSP_UIREQ_ID'] = req_id (inside run_v1)")

indent = anchor.group("indent")
i1 = indent
i2 = indent + "  "
i3 = indent + "    "

inject = (
    f"{i1}# {MARK}\n"
    f"{i1}try:\n"
    f"{i2}# normalize legacy UIREQ_* -> VSP_UIREQ_*\n"
    f"{i2}if isinstance(req_id, str) and req_id.startswith('UIREQ_') and not req_id.startswith('VSP_'):\n"
    f"{i3}req_id = 'VSP_' + req_id\n"
    f"{i1}except Exception:\n"
    f"{i2}pass\n\n"
    f"{i1}# bootstrap uireq state (single source of truth)\n"
    f"{i1}try:\n"
    f"{i2}udir = __import__('pathlib').Path(_VSP_UIREQ_DIR)\n"
    f"{i2}udir.mkdir(parents=True, exist_ok=True)\n"
    f"{i2}state0 = {{\n"
    f"{i3}'request_id': req_id,\n"
    f"{i3}'req_id': req_id,\n"
    f"{i3}'profile': locals().get('profile'),\n"
    f"{i3}'target': locals().get('target'),\n"
    f"{i3}'stage_sig': '0/0||0',\n"
    f"{i3}'final': False,\n"
    f"{i3}'killed': False,\n"
    f"{i2}}}\n"
    f"{i2}(udir / f\"{{req_id}}.json\").write_text(__import__('json').dumps(state0, ensure_ascii=False, indent=2), encoding='utf-8')\n"
    f"{i2}print('[{MARK}] wrote', str(udir / f\"{{req_id}}.json\"))\n"
    f"{i1}except Exception as _e:\n"
    f"{i2}print('[{MARK}] WARN', _e)\n\n"
)

ins_at = start + anchor.start()
txt2 = txt[:ins_at] + inject + txt[ins_at:]
p.write_text(txt2, encoding="utf-8")
print("[OK] patched:", MARK)
PY

python3 -m py_compile "$F"
echo "[OK] py_compile OK"
