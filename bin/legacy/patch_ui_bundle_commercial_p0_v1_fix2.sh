#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

TS="$(date +%Y%m%d_%H%M%S)"
echo "== VSP BUNDLE COMMERCIAL P0 (fix2) =="
echo "[TS] $TS"
echo "[PWD] $(pwd)"

BUNDLE="static/js/vsp_bundle_commercial_v1.js"
[ -f "$BUNDLE" ] || { echo "[ERR] missing bundle: $BUNDLE"; exit 2; }

# (A) Fix bundle: remove stray literal "\n" tokens that are outside strings (mostly in comment lines)
python3 - <<'PY'
from pathlib import Path
import re

p = Path("static/js/vsp_bundle_commercial_v1.js")
s = p.read_text(encoding="utf-8", errors="replace")

lines = s.splitlines(True)
out = []
removed_lines = 0
fixed_lines = 0

for line in lines:
  st = line.strip()
  if st in (r"\n", r"\n\n", r"\n\n\n"):
    removed_lines += 1
    continue

  if r"\n" in line:
    # Only sanitize in comment-ish lines to avoid touching legitimate string escapes
    lstr = line.lstrip()
    if lstr.startswith("/*") or ("*/" in line):
      line2 = line.replace(r"\n", "")
      if line2 != line:
        fixed_lines += 1
      line = line2

  out.append(line)

fixed = "".join(out)

# Extra targeted fix: "*/\n\n" => "*/" + real newline
fixed2 = re.sub(r"(\*/)(\\n)+", r"\1\n", fixed)
p.write_text(fixed2, encoding="utf-8")
print("[OK] bundle sanitized:", p.as_posix(), "removed_lines=", removed_lines, "fixed_lines=", fixed_lines, "bytes=", p.stat().st_size)
PY

# (B) Fix vsp_demo_app.py: remove broken injected block and re-inject AFTER app = Flask(...) call ends
APP="vsp_demo_app.py"
if [ -f "$APP" ]; then
  python3 - <<'PY'
from pathlib import Path
import re, datetime

p = Path("vsp_demo_app.py")
txt = p.read_text(encoding="utf-8", errors="replace")

TS = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
bak = p.with_suffix(p.suffix + f".bak_assetv_fix2_{TS}")
bak.write_text(txt, encoding="utf-8")

start_m = "# --- VSP_ASSET_VERSION (commercial) ---"
end_m   = "# --- /VSP_ASSET_VERSION ---"

# remove any existing injected block (even if broken)
lines = txt.splitlines(True)
clean = []
skipping = False
removed = 0
for line in lines:
  if start_m in line:
    skipping = True
    removed += 1
    continue
  if skipping:
    removed += 1
    if end_m in line:
      skipping = False
    continue
  clean.append(line)

lines2 = clean

# find insertion point: AFTER the full app = Flask(...) statement closes
app_pat = re.compile(r"^\s*app\s*=\s*Flask\s*\(", re.M)
insert_at = None

for i, line in enumerate(lines2):
  if app_pat.search(line):
    depth = 0
    started = False
    for j in range(i, len(lines2)):
      seg = lines2[j]
      # naive paren balance is OK here
      depth += seg.count("(") - seg.count(")")
      if j == i:
        started = True
      if started and depth <= 0 and j > i:
        insert_at = j + 1
        break
    if insert_at is None:
      insert_at = i + 1
    break

if insert_at is None:
  # fallback: after last import line
  last_imp = 0
  for k, line in enumerate(lines2[:400]):
    if line.lstrip().startswith("import ") or line.lstrip().startswith("from "):
      last_imp = k + 1
  insert_at = last_imp

insert = r'''
# --- VSP_ASSET_VERSION (commercial) ---
import os as _os
import time as _time
from pathlib import Path as _Path

def _vsp_asset_v():
  v = _os.environ.get("VSP_ASSET_V", "").strip()
  if v:
    return v
  try:
    bp = (_Path(__file__).resolve().parent / "static/js/vsp_bundle_commercial_v1.js")
    return str(int(bp.stat().st_mtime))
  except Exception:
    return str(int(_time.time()))

@app.context_processor
def inject_vsp_asset_v():
  # Used by templates as: {{ asset_v }}
  return {"asset_v": _vsp_asset_v()}
# --- /VSP_ASSET_VERSION ---
'''

out = lines2[:insert_at] + [insert] + lines2[insert_at:]
p.write_text("".join(out), encoding="utf-8")

print("[OK] vsp_demo_app.py repaired asset_v injection; removed_lines=", removed, "insert_at_line=", insert_at+1)
PY
else
  echo "[WARN] missing $APP (skip asset_v repair)"
fi

# (C) Sanity checks
echo "== node --check bundle =="
node --check "static/js/vsp_bundle_commercial_v1.js" && echo "[OK] bundle JS syntax OK"

if [ -f vsp_demo_app.py ]; then
  echo "== py_compile vsp_demo_app.py =="
  python3 -m py_compile vsp_demo_app.py && echo "[OK] py_compile OK"
fi

echo "== DONE (fix2) =="
echo "[NEXT] restart UI 8910 + hard refresh (Ctrl+Shift+R), then rerun selfcheck."
