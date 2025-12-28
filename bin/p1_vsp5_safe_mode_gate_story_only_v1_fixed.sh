#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need ss; need curl; need sed; need grep

F="wsgi_vsp_ui_gateway.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_vsp5_safe_fixed_${TS}"
echo "[BACKUP] ${F}.bak_vsp5_safe_fixed_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")

MARK = "VSP_P1_VSP5_SAFE_MODE_GATE_STORY_ONLY_V1"
# detect flask app var name
m = re.search(r'(?m)^\s*([A-Za-z_]\w*)\s*=\s*Flask\s*\(', s)
appv = m.group(1) if m else "app"
print("[INFO] flask app var:", appv)

# ensure request import exists
if not re.search(r'(?m)^\s*from\s+flask\s+import\b.*\brequest\b', s):
    m2 = re.search(r'(?m)^(from\s+flask\s+import\s+)([^\n]+)$', s)
    if m2:
        line = m2.group(0)
        if "request" not in line:
            s = s.replace(line, line.rstrip() + ", request", 1)
            print("[OK] extended flask import: request")
    else:
        s = "from flask import request\n" + s
        print("[OK] prepended import: request")

# remove old block if exists (idempotent)
pat = re.compile(rf"\n?# --- {MARK} ---.*?# --- /{MARK} ---\n?", re.S)
s, n = pat.subn("\n", s)
if n:
    print("[OK] removed old block:", n)

block_tpl = r"""
# --- __MARK__ ---
@__APPV__.after_request
def _vsp_p1_vsp5_safe_mode_gate_story_only_v1(resp):
    try:
        from flask import request
        if request.path != "/vsp5":
            return resp
        import time
        asset_v = int(time.time())

        html = """<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8"/>
  <meta name="viewport" content="width=device-width, initial-scale=1"/>
  <meta http-equiv="Cache-Control" content="no-cache, no-store, must-revalidate"/>
  <meta http-equiv="Pragma" content="no-cache"/>
  <meta http-equiv="Expires" content="0"/>
  <title>VSP5</title>
  <style>
    body{ margin:0; background:#0b1220; color:rgba(226,232,240,.96);
          font-family: ui-sans-serif, system-ui, -apple-system, Segoe UI, Roboto, Helvetica, Arial; }
    .vsp5nav{ display:flex; gap:10px; padding:10px 14px; border-bottom:1px solid rgba(255,255,255,.10);
              background: rgba(0,0,0,.22); position:sticky; top:0; z-index:9999; }
    .vsp5nav a{ color:rgba(226,232,240,.92); text-decoration:none; font-size:12px;
                padding:8px 10px; border:1px solid rgba(255,255,255,.14); border-radius:12px; }
    .vsp5nav a:hover{ background: rgba(255,255,255,.06); }
    #vsp5_root{ min-height: 60vh; }
  </style>
</head>
<body>
  <div class="vsp5nav">
    <a href="/vsp5">Dashboard</a>
    <a href="/runs">Runs &amp; Reports</a>
    <a href="/data_source">Data Source</a>
    <a href="/settings">Settings</a>
    <a href="/rule_overrides">Rule Overrides</a>
  </div>
  <div id="vsp5_root"></div>

  <!-- SAFE MODE: only Gate Story script -->
  <script src="/static/js/vsp_dashboard_gate_story_v1.js?v=__ASSETV__"></script>
</body>
</html>"""

        html = html.replace("__ASSETV__", str(asset_v))

        resp.set_data(html)
        resp.headers["Content-Type"] = "text/html; charset=utf-8"
        resp.headers["Cache-Control"] = "no-cache, no-store, must-revalidate"
        resp.headers["Pragma"] = "no-cache"
        resp.headers["Expires"] = "0"
        resp.headers["Content-Length"] = str(len(html.encode("utf-8", errors="ignore")))
        return resp
    except Exception:
        return resp
# --- /__MARK__ ---
"""

block = block_tpl.replace("__MARK__", MARK).replace("__APPV__", appv)

# insert before __main__ if present, else append
m3 = re.search(r'(?m)^\s*if\s+__name__\s*==\s*[\'"]__main__[\'"]\s*:\s*$', s)
if m3:
    s2 = s[:m3.start()] + "\n" + block + "\n" + s[m3.start():]
    print("[OK] injected safe-mode block before __main__")
else:
    s2 = s.rstrip() + "\n\n" + block + "\n"
    print("[OK] appended safe-mode block at EOF")

p.write_text(s2, encoding="utf-8")
print("[OK] patched:", p)
PY

python3 -m py_compile wsgi_vsp_ui_gateway.py && echo "[OK] py_compile OK"

echo "== restart clean :8910 =="
rm -f /tmp/vsp_ui_8910.lock /tmp/vsp_ui_8910.lock.* 2>/dev/null || true
PIDS="$(ss -ltnp 2>/dev/null | sed -n 's/.*:8910.*pid=\([0-9]\+\).*/\1/p' | sort -u | tr '\n' ' ')"
[ -n "${PIDS// }" ] && kill -9 $PIDS || true
bin/p1_ui_8910_single_owner_start_v2.sh || true

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
echo "== PROBE /vsp5 scripts (must ONLY be gate_story) =="
curl -fsS "$BASE/vsp5" | grep -n "<script src=" | head -n 20 || true
echo "== PROBE legacy dash must be absent (no vsp_topbar/vsp_dashboard_kpi) =="
curl -fsS "$BASE/vsp5" | grep -n "vsp_topbar\|vsp_dashboard_kpi\|vsp_bundle" | head -n 5 || true
echo "[DONE] VSP5 SAFE MODE (fixed) applied."
