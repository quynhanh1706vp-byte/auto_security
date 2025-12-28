#!/usr/bin/env bash
set -euo pipefail

UI_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TPL="$UI_ROOT/templates/vsp_dashboard_2025.html"
JS_FILE="$UI_ROOT/static/js/vsp_tabs_simple_v1.js"

if [ ! -f "$TPL" ]; then
  echo "[ERR] Không tìm thấy $TPL"
  exit 1
fi

# 1) Ghi (hoặc overwrite) file JS switch tab
cat > "$JS_FILE" << 'JS_EOF'
(function () {
  "use strict";

  const LOG_PREFIX = "[VSP_TABS]";

  function log() {
    // eslint-disable-next-line no-console
    console.log.apply(console, [LOG_PREFIX].concat(Array.from(arguments)));
  }

  function initTabs() {
    const buttons = document.querySelectorAll("[data-vsp-tab-target]");
    const panes = document.querySelectorAll(".vsp-tab-pane");

    if (!buttons.length || !panes.length) {
      log("No tab buttons or panes found – skip.");
      return;
    }

    function showTab(targetSelector) {
      if (!targetSelector) return;
      let found = false;

      panes.forEach((pane) => {
        if (pane.matches(targetSelector)) {
          pane.classList.add("vsp-tab-pane-active");
          pane.style.display = "";
          found = true;
        } else {
          pane.classList.remove("vsp-tab-pane-active");
          pane.style.display = "none";
        }
      });

      buttons.forEach((btn) => {
        const sel = btn.getAttribute("data-vsp-tab-target");
        if (sel === targetSelector) {
          btn.classList.add("vsp-tab-link-active");
        } else {
          btn.classList.remove("vsp-tab-link-active");
        }
      });

      if (!found) {
        log("No pane matched selector:", targetSelector);
      } else {
        log("Switched to tab:", targetSelector);
      }
    }

    buttons.forEach((btn) => {
      btn.addEventListener("click", function (e) {
        e.preventDefault();
        const sel = btn.getAttribute("data-vsp-tab-target");
        if (!sel) return;
        showTab(sel);
      });
    });

    let defaultSelector = null;

    if (window.location.hash && document.querySelector(window.location.hash)) {
      defaultSelector = window.location.hash;
    }
    if (!defaultSelector) {
      const defBtn = document.querySelector(
        "[data-vsp-tab-default='true'][data-vsp-tab-target]"
      );
      if (defBtn) {
        defaultSelector = defBtn.getAttribute("data-vsp-tab-target");
      }
    }
    if (!defaultSelector && buttons[0]) {
      defaultSelector = buttons[0].getAttribute("data-vsp-tab-target");
    }

    if (defaultSelector) {
      showTab(defaultSelector);
      log("Initialized, default tab =", defaultSelector);
    } else {
      log("Initialized without default tab.");
    }

    window.vspTabsShow = showTab;
  }

  document.addEventListener("DOMContentLoaded", initTabs);
})();
JS_EOF

echo "[OK] Đã viết $JS_FILE"

# 2) Backup template
TS="$(date +%Y%m%d_%H%M%S)"
BACKUP="${TPL}.bak_tabs_nav_${TS}"
cp "$TPL" "$BACKUP"
echo "[BACKUP] $TPL -> $BACKUP"

python3 - << 'PY'
from pathlib import Path

tpl = Path("templates/vsp_dashboard_2025.html")
text = tpl.read_text(encoding="utf-8")

# 2a) Chèn <script src="...vsp_tabs_simple_v1.js"> trước </body> nếu chưa có
if "vsp_tabs_simple_v1.js" not in text:
    if "</body>" in text:
        inject = '  <script src="/static/js/vsp_tabs_simple_v1.js"></script>\\n'
        inject += '  <script>console.log("[VSP_TABS_PATCH] tabs js loaded");</script>\\n'
        text = text.replace("</body>", inject + "</body>")
        print("[OK] Đã chèn vsp_tabs_simple_v1.js vào template.")
    else:
        print("[WARN] Không tìm thấy </body>, KHÔNG chèn script.")
else:
    print("[INFO] Template đã có vsp_tabs_simple_v1.js – giữ nguyên.")

# 2b) Chèn NAV 5 tab trước cụm 'TAB 1 – DASHBOARD' nếu chưa có data-vsp-tab-target
if 'data-vsp-tab-target="#vsp-tab-dashboard"' in text:
    print("[INFO] NAV 5 tab đã tồn tại – không chèn lại.")
else:
    marker = "TAB 1 – DASHBOARD"
    idx = text.find(marker)
    if idx == -1:
        print("[WARN] Không tìm thấy marker 'TAB 1 – DASHBOARD' – không chèn NAV.")
    else:
        nav_html = '''
<div class="vsp-tabs-nav">
  <button
    class="vsp-tab-link"
    data-vsp-tab-target="#vsp-tab-dashboard"
    data-vsp-tab-default="true">
    Dashboard
  </button>

  <button
    class="vsp-tab-link"
    data-vsp-tab-target="#vsp-tab-runs">
    Runs &amp; Reports
  </button>

  <button
    class="vsp-tab-link"
    data-vsp-tab-target="#vsp-tab-datasource">
    Data Source
  </button>

  <button
    class="vsp-tab-link"
    data-vsp-tab-target="#vsp-tab-settings">
    Settings
  </button>

  <button
    class="vsp-tab-link"
    data-vsp-tab-target="#vsp-tab-rules">
    Rule Overrides
  </button>
</div>

'''
        text = text[:idx] + nav_html + text[idx:]
        print("[OK] Đã chèn NAV 5 tab trước 'TAB 1 – DASHBOARD'.")
tpl.write_text(text, encoding="utf-8")
PY

echo "[DONE] patch_vsp_tabs_nav_and_js_v1 hoàn tất."
