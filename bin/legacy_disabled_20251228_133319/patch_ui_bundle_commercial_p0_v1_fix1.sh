#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

TS="$(date +%Y%m%d_%H%M%S)"
echo "== VSP BUNDLE COMMERCIAL P0 (v1 fix1) =="
echo "[TS] $TS"
echo "[PWD] $(pwd)"

BUNDLE="static/js/vsp_bundle_commercial_v1.js"
[ -f "$BUNDLE" ] || { echo "[ERR] missing bundle: $BUNDLE (run build step first)"; exit 2; }

# --- (2) Patch templates: only load the bundle (no more per-route loader) ---
python3 - <<'PY'
from pathlib import Path
import re, datetime

TS = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
bundle_tag = '<script defer src="/static/js/vsp_bundle_commercial_v1.js?v={{ asset_v }}"></script>'

tpl_dir = Path("templates")
if not tpl_dir.exists():
  print("[WARN] templates/ not found -> skip template patch")
  raise SystemExit(0)

script_re = re.compile(r'(?is)<script\b[^>]*\bsrc\s*=\s*["\']([^"\']+)["\'][^>]*>\s*</script\s*>')

def is_remove_candidate(src: str) -> bool:
  # remove our modular vsp scripts (including route loader), keep bundle, keep vendor libs
  if "vsp_bundle_commercial_v1.js" in src:
    return False
  return "/static/js/vsp_" in src

targets = []
for p in sorted(tpl_dir.rglob("*.html")):
  try:
    txt = p.read_text(encoding="utf-8", errors="replace")
  except Exception:
    continue
  if "/static/js/vsp_" in txt:
    targets.append(p)

if not targets:
  print("[WARN] no templates contain /static/js/vsp_ -> nothing to patch")
  raise SystemExit(0)

for tpl in targets:
  txt = tpl.read_text(encoding="utf-8", errors="replace")
  bak = tpl.with_suffix(tpl.suffix + f".bak_bundle_fix1_{TS}")
  bak.write_text(txt, encoding="utf-8")

  removed = [0]  # mutable counter

  def repl(m):
    src = (m.group(1) or "").strip()
    if is_remove_candidate(src):
      removed[0] += 1
      return "\n"
    return m.group(0)

  new = script_re.sub(repl, txt)

  if "vsp_bundle_commercial_v1.js" not in new:
    if re.search(r"(?is)</body\s*>", new):
      new = re.sub(r"(?is)</body\s*>", "\n" + bundle_tag + "\n</body>", new, count=1)
    else:
      new = new + "\n" + bundle_tag + "\n"

  tpl.write_text(new, encoding="utf-8")
  print(f"[OK] patched {tpl.as_posix()} removed_vsp_scripts={removed[0]}")

PY

# --- (3) Patch server: provide asset_v from server (mtime of bundle OR env) ---
APP="vsp_demo_app.py"
if [ -f "$APP" ]; then
  python3 - <<'PY'
from pathlib import Path
import re, datetime

p = Path("vsp_demo_app.py")
txt = p.read_text(encoding="utf-8", errors="replace")

if "def inject_vsp_asset_v" in txt and "asset_v" in txt:
  print("[OK] vsp_demo_app.py already has inject_vsp_asset_v (skip)")
  raise SystemExit(0)

TS = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
bak = p.with_suffix(p.suffix + f".bak_assetv_fix1_{TS}")
bak.write_text(txt, encoding="utf-8")

m = re.search(r"(?m)^\s*app\s*=\s*Flask\(", txt)
if not m:
  print("[WARN] cannot find 'app = Flask(' -> skip inject asset_v")
  raise SystemExit(0)

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

lines = txt.splitlines(True)
out = []
done = False
for line in lines:
  out.append(line)
  if (not done) and re.search(r"^\s*app\s*=\s*Flask\(", line):
    out.append(insert)
    done = True

p.write_text("".join(out), encoding="utf-8")
print("[OK] injected asset_v context_processor into vsp_demo_app.py")
PY
else
  echo "[WARN] missing $APP (skip asset_v injection)"
fi

# --- (4) Sanity checks ---
echo "== node --check bundle =="
node --check "static/js/vsp_bundle_commercial_v1.js" && echo "[OK] bundle JS syntax OK"

if [ -f vsp_demo_app.py ]; then
  echo "== py_compile vsp_demo_app.py =="
  python3 -m py_compile vsp_demo_app.py && echo "[OK] py_compile OK"
fi

echo "== DONE (fix1) =="
echo "[NEXT] restart UI 8910 + hard refresh (Ctrl+Shift+R), then rerun selfcheck."
