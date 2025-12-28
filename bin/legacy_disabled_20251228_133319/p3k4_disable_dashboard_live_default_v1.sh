#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
JS="static/js/vsp_dashboard_live_v2.V1_baseline.js"
TS="$(date +%Y%m%d_%H%M%S)"

[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

cp -f "$JS" "${JS}.bak_p3k4_${TS}"
echo "[BACKUP] ${JS}.bak_p3k4_${TS}"

python3 - <<'PY'
from pathlib import Path
p=Path("static/js/vsp_dashboard_live_v2.V1_baseline.js")
s=p.read_text(encoding="utf-8", errors="replace")

MARK="VSP_P3K4_DISABLE_LIVE_DEFAULT_V1"
if MARK in s:
    print("[OK] already patched")
    raise SystemExit(0)

# Wrap the whole file in IIFE and gate by ?live=1
wrapped = f"""// {MARK}
(function(){{
  try {{
    const u = new URL(location.href);
    const live = u.searchParams.get("live");
    if (live !== "1") {{
      // LIVE polling disabled by default (commercial-safe).
      // Add ?live=1 to enable live mode.
      return;
    }}
  }} catch (e) {{}}

{s}
}})();
"""

p.write_text(wrapped, encoding="utf-8")
print("[OK] patched: gated by ?live=1")
PY

echo "== restart =="
sudo systemctl restart "$SVC"
sleep 0.7
sudo systemctl is-active --quiet "$SVC" && echo "[OK] service active" || {
  echo "[ERR] service not active"
  sudo systemctl status "$SVC" --no-pager | sed -n '1,220p' || true
  sudo journalctl -u "$SVC" -n 220 --no-pager || true
  exit 3
}

echo "[DONE] p3k4_disable_dashboard_live_default_v1"
