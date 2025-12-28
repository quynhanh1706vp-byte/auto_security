#!/usr/bin/env bash
set -euo pipefail
F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_runapi_regclean_v3_${TS}"
echo "[BACKUP] $F.bak_runapi_regclean_v3_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("vsp_demo_app.py")
txt=p.read_text(encoding="utf-8", errors="ignore")

# 1) Remove/disable duplicate OK-registered print lines everywhere except the FIRST occurrence.
needle = 'print("[VSP_RUN_API] OK registered: /api/vsp/run_v1 + /api/vsp/run_status_v1/<REQ_ID>")'
idxs = [m.start() for m in re.finditer(re.escape(needle), txt)]
if not idxs:
    raise SystemExit("[ERR] cannot find OK registered print needle")
first = idxs[0]

def comment_out_at(pos: int, s: str) -> str:
    ls = s.rfind("\n", 0, pos) + 1
    le = s.find("\n", pos)
    if le == -1: le = len(s)
    line = s[ls:le]
    if line.lstrip().startswith("#"):
        return s
    return s[:ls] + "# [VSP_REGCLEAN_V3_DISABLED] " + line + s[le:]

# disable all later occurrences
for pos in reversed(idxs[1:]):
    txt = comment_out_at(pos, txt)

# 2) Wrap the PRIMARY registration try/except (the one near the first print) with a top-level guard.
# Find the try: block that contains the first print
try_start = txt.rfind("\ntry:", 0, first)
if try_start == -1:
    raise SystemExit("[ERR] cannot locate try: before first OK-registered print")

# find the corresponding "# === END VSP_RUN_API_FORCE_REGISTER" marker if present, else end at next blank line after print
end_marker = txt.find("# === END VSP_RUN_API_FORCE_REGISTER", first)
if end_marker != -1:
    # end at end of line containing marker
    end_block = txt.find("\n", end_marker)
    if end_block == -1: end_block = len(txt)
else:
    end_block = txt.find("\n\n", first)
    if end_block == -1: end_block = first + 300

block = txt[try_start:end_block]

# If already wrapped, skip
if "VSP_REGISTER_RUNAPI_GUARD_V3" not in block:
    guard = r'''
# === VSP_REGISTER_RUNAPI_GUARD_V3 ===
if globals().get("VSP_RUN_API_REGISTERED_ONCE"):
  pass
else:
  globals()["VSP_RUN_API_REGISTERED_ONCE"] = True
  # === END VSP_REGISTER_RUNAPI_GUARD_V3 ===
'''.lstrip("\n")

    # indent the whole original block by two spaces so it becomes the body of else:
    indented = "\n".join(("  "+ln if ln.strip() else ln) for ln in block.splitlines())
    new_block = guard + indented + "\n"
    txt = txt[:try_start] + "\n" + new_block + txt[end_block:]

# 3) Drop extra legacy blocks that still print OK registered near EOF by disabling the marker blocks if present
# (We already commented prints; this just makes intent clear.)
txt = txt.replace("skip blueprint already registered: vsp_run_api_v1",
                  "skip blueprint already registered: vsp_run_api_v1")  # no-op; placeholder

p.write_text(txt, encoding="utf-8")
print("[OK] regclean_v3 applied: later OK-registered prints commented, primary try/except guarded")
PY

python3 -m py_compile "$F"
echo "[OK] py_compile OK"

pkill -f vsp_demo_app.py || true
nohup python3 vsp_demo_app.py > out_ci/ui_8910.log 2>&1 &
sleep 1

echo "== grep VSP_RUN_API (must show OK registered once) =="
grep -n "VSP_RUN_API" out_ci/ui_8910.log | head -n 30 || true

echo "== count OK registered lines =="
grep -n "OK registered: /api/vsp/run_v1" out_ci/ui_8910.log | wc -l
