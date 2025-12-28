#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
TS="$(date +%Y%m%d_%H%M%S)"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need node; need date
command -v systemctl >/dev/null 2>&1 || true

FILES=(
  static/js/vsp_tabs4_autorid_v1.js
  static/js/vsp_dashboard_gate_story_v1.js
)

python3 - <<'PY'
from pathlib import Path
import time

MARK="VSP_P3K19_EARLY_GUARD_SWALLOW_TIMEOUT_V1"
inject = f"""/* === {MARK} ===
   Run EARLY (before tabs5) to suppress "Uncaught (in promise) timeout" in Firefox.
=== */
(function(){{
  function _isTimeoutMsg(m){{
    try {{
      m = (m && (m.message || (''+m))) || '';
      return (m === 'timeout') || (/\\btimeout\\b/i.test(m));
    }} catch(_){{ return false; }}
  }}
  try {{
    if (!window.__VSP_TIMEOUT_GUARD__) {{
      window.__VSP_TIMEOUT_GUARD__ = true;
      window.addEventListener('unhandledrejection', function(e){{
        try {{ if (_isTimeoutMsg(e && e.reason)) e.preventDefault(); }} catch(_){{}}
      }});
      window.addEventListener('error', function(e){{
        try {{
          var msg = (e && (e.message || (''+e.error))) || '';
          if (_isTimeoutMsg(msg)) e.preventDefault();
        }} catch(_){{}}
      }}, true);
    }}
  }} catch(_){{}}
}})();
"""

targets = [
  Path("static/js/vsp_tabs4_autorid_v1.js"),
  Path("static/js/vsp_dashboard_gate_story_v1.js"),
]

patched=0
for p in targets:
    if not p.exists():
        print("[WARN] missing:", p)
        continue
    s = p.read_text(encoding="utf-8", errors="replace")
    if MARK in s:
        print("[OK] already:", p)
        continue
    bak = Path(str(p) + f".bak_p3k19_{time.strftime('%Y%m%d_%H%M%S')}")
    bak.write_text(s, encoding="utf-8")
    p.write_text(inject + "\n" + s, encoding="utf-8")
    print("[OK] patched:", p, "backup=", bak.name)
    patched += 1

print("[DONE] patched_files=", patched)
PY

# syntax check only if file exists
for f in "${FILES[@]}"; do
  [ -f "$f" ] && node -c "$f" >/dev/null && echo "[OK] node -c: $f"
done

sudo systemctl restart "$SVC"
sudo systemctl is-active --quiet "$SVC" && echo "[OK] service active" || { echo "[ERR] service not active"; exit 3; }

echo "== markers =="
for f in "${FILES[@]}"; do
  [ -f "$f" ] && head -n 2 "$f" | sed -n '1,2p'
done

echo "[DONE] p3k19_early_guard_swallow_timeout_v1"
