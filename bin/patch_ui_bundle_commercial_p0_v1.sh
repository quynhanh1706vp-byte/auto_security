#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

TS="$(date +%Y%m%d_%H%M%S)"
echo "== VSP BUNDLE COMMERCIAL P0 (v1) =="
echo "[TS] $TS"
echo "[PWD] $(pwd)"

BUNDLE="static/js/vsp_bundle_commercial_v1.js"
mkdir -p static/js

# --- (1) Build bundle (core + dashboard) ---
python3 - <<'PY'
from pathlib import Path
import datetime

root = Path(".")
bundle = root / "static/js/vsp_bundle_commercial_v1.js"

# NOTE: exclude vsp_ui_loader_route_v1.js (stop dynamic loader by design)
base = [
  "static/js/vsp_drilldown_stub_safe_v1.js",
  "static/js/vsp_drilldown_artifacts_impl_commercial_v1.js",
  "static/js/vsp_hash_normalize_v1.js",
  "static/js/vsp_ui_global_shims_commercial_p0_v1.js",
  "static/js/vsp_rid_state_v1.js",
  "static/js/vsp_tabs_hash_router_v1.js",
  "static/js/vsp_ui_features_v1.js",
  "static/js/vsp_nav_scroll_autofix_v1.js",
  "static/js/vsp_export_guard_v1.js",
  "static/js/vsp_runs_verdict_badges_v1.js",
  "static/js/vsp_runs_tab_resolved_v1.js",
  "static/js/vsp_datasource_tab_v1.js",
  "static/js/vsp_rule_overrides_tab_v1.js",
  # dashboard (was previously route-loaded)
  "static/js/vsp_dashboard_enhance_v1.js",
  "static/js/vsp_dashboard_charts_pretty_v3.js",
]

# add any extra dashboard modules if present (stable sort, not required)
dash_glob = sorted((root / "static/js").glob("vsp_dashboard_*.js"))
for p in dash_glob:
  rel = str(p).replace("\\", "/")
  if rel not in base:
    base.append(rel)

seen = set()
files = []
missing = []
for rel in base:
  if rel in seen:
    continue
  seen.add(rel)
  p = root / rel
  if p.exists() and p.is_file():
    files.append(p)
  else:
    missing.append(rel)

ts = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
hdr = []
hdr.append("/* VSP_BUNDLE_COMMERCIAL_V1 */")
hdr.append(f"/* built_at: {ts} */")
hdr.append("/* NOTE: do NOT load vsp_ui_loader_route_v1.js in commercial mode */")
hdr.append("")
hdr.append("(function(){")
hdr.append("  'use strict';")
hdr.append("  // Single public entrypoint (commercial contract)")
hdr.append("  if (!window.VSP_DRILLDOWN) {")
hdr.append("    window.VSP_DRILLDOWN = function(intent){")
hdr.append("      try{")
hdr.append("        // prefer explicit impl if provided")
hdr.append("        if (typeof window.VSP_DRILLDOWN_IMPL === 'function') return window.VSP_DRILLDOWN_IMPL(intent);")
hdr.append("        // common internal hooks (best-effort compat)")
hdr.append("        if (typeof window.__VSP_DD_ART_CALL__ === 'function') return window.__VSP_DD_ART_CALL__(intent);")
hdr.append("        if (typeof window.__VSP_DRILLDOWN__ === 'function') return window.__VSP_DRILLDOWN__(intent);")
hdr.append("        console.warn('[VSP][DRILLDOWN] no impl', intent);")
hdr.append("        return null;")
hdr.append("      }catch(e){ try{console.warn('[VSP][DRILLDOWN] err', e);}catch(_){ } return null; }")
hdr.append("    };")
hdr.append("  }")
hdr.append("  // Backward-compat shim (do NOT encourage direct P1_V2 usage)")
hdr.append("  if (!window.P1_V2) window.P1_V2 = {};")
hdr.append("  if (typeof window.P1_V2 === 'object' && !window.P1_V2.drilldown) {")
hdr.append("    window.P1_V2.drilldown = function(intent){ return window.VSP_DRILLDOWN(intent); };")
hdr.append("  }")
hdr.append("})();")
hdr.append("")

out = []
out.extend(hdr)

for p in files:
  rel = p.as_posix()
  out.append(f";\n/* ==== BEGIN {rel} ==== */\n")
  out.append(p.read_text(encoding="utf-8", errors="replace"))
  out.append(f"\n/* ==== END {rel} ==== */\n;")

bundle.write_text("\n".join(out), encoding="utf-8")

print("[OK] wrote bundle:", bundle.as_posix(), "bytes=", bundle.stat().st_size)
if missing:
  print("[WARN] missing (skipped):")
  for m in missing:
    print(" -", m)
PY

# --- (2) Patch templates: only load the bundle (no more per-route loader) ---
python3 - <<'PY'
from pathlib import Path
import re, datetime

TS = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
bundle_tag = r'<script defer src="/static/js/vsp_bundle_commercial_v1.js?v={{ asset_v }}"></script>'

tpl_dir = Path("templates")
candidates = [
  tpl_dir / "vsp_dashboard_2025.html",
  tpl_dir / "vsp_4tabs_commercial_v1.html",
]
targets = [p for p in candidates if p.exists()]

if not targets:
  print("[WARN] no target templates found under templates/. Skipping template patch.")
  raise SystemExit(0)

script_re = re.compile(r'''(?is)\s*<script\b[^>]*\bsrc\s*=\s*["']([^"']+)["'][^>]*>\s*</script>\s*''')
def is_vsp_js(src: str) -> bool:
  # remove only our modular scripts; keep vendor libs
  return "/static/js/vsp_" in src and "vsp_bundle_commercial_v1.js" not in src

for tpl in targets:
  txt = tpl.read_text(encoding="utf-8", errors="replace")
  bak = tpl.with_suffix(tpl.suffix + f".bak_bundle_{TS}")
  bak.write_text(txt, encoding="utf-8")
  removed = 0

  def repl(m):
    nonlocal removed
    src = m.group(1) or ""
    if is_vsp_js(src):
      removed += 1
      return "\n"
    return m.group(0)

  new = script_re.sub(repl, txt)

  if "vsp_bundle_commercial_v1.js" not in new:
    # insert before </body>, else append end
    if re.search(r"(?is)</body\s*>", new):
      new = re.sub(r"(?is)</body\s*>", "\n" + bundle_tag + "\n</body>", new, count=1)
    else:
      new = new + "\n" + bundle_tag + "\n"

  tpl.write_text(new, encoding="utf-8")
  print(f"[OK] patched {tpl} (removed_vsp_scripts={removed}) -> inserted bundle_tag")

PY

# --- (3) Patch server: provide asset_v from server (mtime of bundle OR env) ---
# best-effort: inject context_processor into vsp_demo_app.py if present
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
bak = p.with_suffix(p.suffix + f".bak_assetv_{TS}")
bak.write_text(txt, encoding="utf-8")

needle = re.search(r"(?m)^\s*app\s*=\s*Flask\(", txt)
if not needle:
  print("[WARN] cannot find 'app = Flask(' in vsp_demo_app.py. Skip injecting asset_v.")
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

# insert right after the line that contains app = Flask(...)
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

echo "== DONE =="
echo "[BUNDLE] $BUNDLE"
echo "[NEXT] restart UI 8910 + hard refresh (Ctrl+Shift+R), then rerun selfcheck."
