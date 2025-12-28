#!/usr/bin/env bash
set -euo pipefail
F="run_api/vsp_run_api_v1.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_statepath_v8_${TS}"
echo "[BACKUP] $F.bak_statepath_v8_${TS}"

python3 - <<'PY'
import re
from pathlib import Path

p = Path("run_api/vsp_run_api_v1.py")
txt = p.read_text(encoding="utf-8", errors="ignore")

MARK="VSP_RUNAPI_STATEPATH_UIREQDIR_V8"
if MARK in txt:
    print("[OK] already patched:", MARK)
    raise SystemExit(0)

# 1) Patch _state_path(req_id) body to always use _VSP_UIREQ_DIR
m = re.search(r"^\s*def\s+_state_path\s*\(\s*req_id\s*\)\s*:\s*$", txt, flags=re.M)
if not m:
    raise SystemExit("[ERR] cannot find def _state_path(req_id):")

# find end of function (next def at col 0/2)
m_next = re.search(r"^\s*def\s+\w+\s*\(", txt[m.end():], flags=re.M)
end = len(txt) if not m_next else (m.end() + m_next.start())

# detect indent
line_start = txt.rfind("\n", 0, m.start()) + 1
indent = re.match(r"\s*", txt[line_start:m.start()]).group(0)
body_indent = indent + "  "

new_fn = (
f"{indent}def _state_path(req_id):\n"
f"{body_indent}# {MARK}\n"
f"{body_indent}try:\n"
f"{body_indent}  d = _VSP_UIREQ_DIR\n"
f"{body_indent}except Exception:\n"
f"{body_indent}  d = Path.cwd() / 'out_ci' / 'uireq_v1'\n"
f"{body_indent}try:\n"
f"{body_indent}  d.mkdir(parents=True, exist_ok=True)\n"
f"{body_indent}except Exception:\n"
f"{body_indent}  pass\n"
f"{body_indent}return d / f\"{ '{' }req_id{ '}' }.json\"\n"
)

txt2 = txt[:m.start()] + new_fn + "\n" + txt[end:]

# 2) Patch _read_state(req_id) to try fallback path if JSON empty
m2 = re.search(r"^\s*def\s+_read_state\s*\(\s*req_id\s*\)\s*:\s*$", txt2, flags=re.M)
if not m2:
    # if function name differs, just finish after state_path patch
    p.write_text(txt2, encoding="utf-8")
    print("[OK] patched state_path only:", MARK)
    raise SystemExit(0)

m2_next = re.search(r"^\s*def\s+\w+\s*\(", txt2[m2.end():], flags=re.M)
end2 = len(txt2) if not m2_next else (m2.end() + m2_next.start())

fn2 = txt2[m2.start():end2]

# inject fallback after first attempt returns {}
# pattern: "return {}" first occurrence inside _read_state
if "FALLBACK_UIREQDIR_V8" not in fn2:
    fn2_new = re.sub(
        r"(\n\s*return\s*\{\}\s*\n)",
        r"\1"
        r"\n  # FALLBACK_UIREQDIR_V8: try uireqdir state file\n"
        r"  try:\n"
        r"    f2 = _state_path(req_id)\n"
        r"    if f2 and f2.is_file():\n"
        r"      return json.loads(f2.read_text(encoding='utf-8', errors='replace'))\n"
        r"  except Exception:\n"
        r"    pass\n",
        fn2,
        count=1
    )
    txt2 = txt2[:m2.start()] + fn2_new + txt2[end2:]

p.write_text(txt2, encoding="utf-8")
print("[OK] patched:", MARK)
PY

python3 -m py_compile "$F"
echo "[OK] py_compile OK"
