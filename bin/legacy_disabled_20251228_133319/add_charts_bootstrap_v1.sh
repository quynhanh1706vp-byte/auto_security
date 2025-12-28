#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

JSF="static/js/vsp_dashboard_charts_bootstrap_v1.js"
TPL="templates/vsp_dashboard_2025.html"

mkdir -p static/js

# 1) Write bootstrap
cat > "$JSF" <<'JS'
(function () {
  "use strict";
  if (window.__VSP_CHARTS_BOOTSTRAP_V1) return;
  window.__VSP_CHARTS_BOOTSTRAP_V1 = true;

  console.log("[VSP_CHARTS_BOOT] bootstrap loaded (v1)");

  async function fetchDash() {
    try {
      var r = await fetch("/api/vsp/dashboard_v3_latest", { cache: "no-store" });
      if (!r.ok) return null;
      var j = await r.json();
      return j;
    } catch (e) {
      return null;
    }
  }

  function getEngine() {
    return window.VSP_CHARTS_ENGINE_V3 || window.VSP_CHARTS_ENGINE_V2 || null;
  }

  async function tryInit(tag) {
    try {
      var eng = getEngine();
      if (!eng || !eng.initAll) return false;

      var data = window.__VSP_DASH_LAST_DATA_V3 || null;
      if (!data) {
        data = await fetchDash();
        if (data) window.__VSP_DASH_LAST_DATA_V3 = data;
      }
      if (!data) return false;

      var ok = eng.initAll(data);
      console.log("[VSP_CHARTS_BOOT] initAll via", tag, "=>", ok);
      return !!ok;
    } catch (e) {
      console.warn("[VSP_CHARTS_BOOT] init failed", e);
      return false;
    }
  }

  // retry loop (avoid race/missed event)
  function scheduleRetries() {
    var tries = 0, maxTries = 20, delay = 400;
    (function tick() {
      tries++;
      tryInit("retry#" + tries).then(function (ok) {
        if (ok) return;
        if (tries < maxTries) setTimeout(tick, delay);
      });
    })();
  }

  // on charts-ready event
  window.addEventListener("vsp:charts-ready", function (ev) {
    console.log("[VSP_CHARTS_BOOT] got vsp:charts-ready", ev && ev.detail ? ev.detail : "");
    scheduleRetries();
  });

  // also run after load
  setTimeout(function () { scheduleRetries(); }, 800);
})();
JS

node --check "$JSF"

# 2) Patch template to include bootstrap (once)
[ -f "$TPL" ] || { echo "[ERR] missing $TPL"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$TPL" "$TPL.bak_bootstrap_${TS}"
echo "[BACKUP] $TPL.bak_bootstrap_${TS}"

python3 - <<'PY'
import re
from pathlib import Path

tpl = Path("templates/vsp_dashboard_2025.html")
t = tpl.read_text(encoding="utf-8", errors="ignore")

tag = '<script src="/static/js/vsp_dashboard_charts_bootstrap_v1.js" defer></script>'
if tag in t:
    print("[OK] bootstrap tag already present")
    raise SystemExit(0)

# insert right AFTER pretty_v3 include (best), else append near bottom
m = re.search(r'<script\s+src="/static/js/vsp_dashboard_charts_pretty_v3\.js"\s+defer></script>', t, flags=re.I)
if m:
    insert_pos = m.end()
    t2 = t[:insert_pos] + "\n  " + tag + t[insert_pos:]
    tpl.write_text(t2, encoding="utf-8")
    print("[OK] inserted bootstrap right after pretty_v3")
else:
    tpl.write_text(t.rstrip() + "\n  " + tag + "\n", encoding="utf-8")
    print("[WARN] pretty_v3 tag not found; appended bootstrap at EOF")
PY

echo "[OK] done"
