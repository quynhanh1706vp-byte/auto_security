#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
TS="$(date +%Y%m%d_%H%M%S)"

targets=(
  static/js/vsp_dashboard_comm_enhance_v1.js
  static/js/vsp_dashboard_live_v2.V1_baseline.js
  static/js/vsp_dashboard_luxe_v1.js
)

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need node
command -v systemctl >/dev/null 2>&1 || true

echo "== [0] backup existing files if present =="
for f in "${targets[@]}"; do
  if [ -f "$f" ]; then
    cp -f "$f" "${f}.bak_p3k6_${TS}"
    echo "[BACKUP] ${f}.bak_p3k6_${TS}"
  fi
done

python3 - <<'PY'
from pathlib import Path

MARK="VSP_P3K6_DISABLE_DASH_WATCHDOG_V1"

SNIP_TOP = f"""// {MARK}
(function(){{
  try {{
    const u = new URL(location.href);
    if (u.searchParams.get("watchdog") === "1") return; // debug only
  }} catch (e) {{}}
  window.__VSP_DISABLE_DASH_WATCHDOG = 1;
  const noop = function(){{}};
  // common watchdog / degraded hooks (safe no-op)
  window.__vspDashWatchdog = noop;
  window.__vspDashboardWatchdog = noop;
  window.__vspWatchdogArm = noop;
  window.__vspWatchdogStart = noop;
  window.__vspWatchdogTrip = noop;
  window.__vspSetDegraded = noop;
  window.__vspMarkDegraded = noop;
  window.__vspCheckDegraded = function(){{ return; }};
  // best-effort hide banners if any
  try {{
    const st=document.createElement("style");
    st.textContent = `
      .vsp-watchdog, .vsp-degraded, .degraded, .degraded-banner,
      [data-vsp-watchdog], [data-vsp-degraded] {{ display:none !important; }}
    `;
    document.head.appendChild(st);
  }} catch(e) {{}}
}})();
"""

SNIP_BOTTOM = """
// VSP_P3K6_DISABLE_DASH_WATCHDOG_V1 (tail)
try {
  if (window.__VSP_DISABLE_DASH_WATCHDOG) {
    const noop = function(){};
    window.__vspDashWatchdog = noop;
    window.__vspDashboardWatchdog = noop;
    window.__vspWatchdogArm = noop;
    window.__vspWatchdogStart = noop;
    window.__vspWatchdogTrip = noop;
    window.__vspSetDegraded = noop;
    window.__vspMarkDegraded = noop;
    window.__vspCheckDegraded = function(){ return; };
  }
} catch(e) {}
"""

targets = [
  "static/js/vsp_dashboard_comm_enhance_v1.js",
  "static/js/vsp_dashboard_live_v2.V1_baseline.js",
  "static/js/vsp_dashboard_luxe_v1.js",
]

for t in targets:
  p=Path(t)
  if not p.exists():
    continue
  s=p.read_text(encoding="utf-8", errors="replace")
  if MARK in s:
    print("[OK] already patched:", t)
    continue
  # add top + tail, minimal invasive
  p.write_text(SNIP_TOP + "\n" + s + "\n" + SNIP_BOTTOM + "\n", encoding="utf-8")
  print("[OK] patched:", t)
PY

echo "== [1] syntax check (node -c) on patched files =="
for f in "${targets[@]}"; do
  if [ -f "$f" ]; then
    node -c "$f" >/dev/null
    echo "[OK] node -c: $f"
  fi
done

echo "== [2] restart service =="
sudo systemctl restart "$SVC"
sleep 0.7
sudo systemctl is-active --quiet "$SVC" && echo "[OK] service active" || {
  echo "[ERR] service not active"
  sudo systemctl status "$SVC" --no-pager | sed -n '1,220p' || true
  sudo journalctl -u "$SVC" -n 220 --no-pager || true
  exit 3
}

echo "[DONE] p3k6_disable_dashboard_watchdog_default_v1"
