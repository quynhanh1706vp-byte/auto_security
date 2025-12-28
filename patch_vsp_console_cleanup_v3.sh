#!/usr/bin/env bash
set -euo pipefail

ROOT="/home/test/Data/SECURITY_BUNDLE/ui"
JS_DIR="$ROOT/static/js"

echo "[PATCH] VSP – cleanup console: fetch shim + tabs runtime sạch"

############################################
# 1) Ghi đè vsp_tabs_runtime_v2.js
############################################
cat > "$JS_DIR/vsp_tabs_runtime_v2.js" << 'JS'
// VSP_TABS_RUNTIME_V2_CLEAN – quản lý 5 tab chính, không gọi API
(function () {
  const LOG = "[VSP_TABS]";

  function activateTab(targetId) {
    const panes = document.querySelectorAll(".tab-pane");
    panes.forEach(p => {
      if (p.id === targetId) {
        p.classList.add("active");
      } else {
        p.classList.remove("active");
      }
    });

    const buttons = document.querySelectorAll("[data-tab-target]");
    buttons.forEach(b => {
      if (b.getAttribute("data-tab-target") === targetId) {
        b.classList.add("active");
      } else {
        b.classList.remove("active");
      }
    });

    console.log(LOG, "switch to", targetId);
  }

  document.addEventListener("DOMContentLoaded", function () {
    const buttons = document.querySelectorAll("[data-tab-target]");
    if (!buttons.length) {
      console.warn(LOG, "Không tìm thấy nút tab nào.");
      return;
    }

    buttons.forEach(btn => {
      btn.addEventListener("click", function (e) {
        e.preventDefault();
        const targetId = btn.getAttribute("data-tab-target");
        if (!targetId) return;
        activateTab(targetId);

        // Hook: khi chuyển tab, gọi loader nếu có
        if (targetId === "tab-runs" && window.vspLoadRunsTab) {
          window.vspLoadRunsTab();
        }
        if (targetId === "tab-data" && window.vspLoadDataSourceTab) {
          window.vspLoadDataSourceTab();
        }
      });
    });

    // đảm bảo có 1 tab active ban đầu
    const activePane = document.querySelector(".tab-pane.active");
    if (!activePane && buttons[0]) {
      const firstTarget = buttons[0].getAttribute("data-tab-target");
      if (firstTarget) {
        activateTab(firstTarget);
      }
    }

    console.log(LOG, "init done");
  });
})();
JS

echo "[PATCH] Đã ghi đè $JS_DIR/vsp_tabs_runtime_v2.js"

############################################
# 2) Tạo fetch shim: redirect API cũ + stub
############################################
cat > "$JS_DIR/vsp_fetch_shim_v1.js" << 'JS'
// VSP_FETCH_SHIM_V1 – chặn các API legacy gây 404, mapping sang API mới
(function () {
  if (!window.fetch) return;
  const ORIG_FETCH = window.fetch.bind(window);
  const LOG = "[VSP_FETCH_SHIM]";

  window.fetch = function (input, init) {
    let url = "";
    if (typeof input === "string") {
      url = input;
    } else if (input && input.url) {
      url = input.url;
    }

    try {
      if (url.includes("/api/vsp/runs_index_v3_v3")) {
        const fixed = url.replace("runs_index_v3_v3", "runs_index_v3");
        console.warn(LOG, "Redirect runs_index_v3_v3 ->", fixed);
        return ORIG_FETCH(fixed, init);
      }

      if (url.includes("/api/vsp/runs_v2")) {
        const fixed = url.replace("/api/vsp/runs_v2", "/api/vsp/runs_index_v3");
        console.warn(LOG, "Redirect runs_v2 ->", fixed);
        return ORIG_FETCH(fixed, init);
      }

      if (url.includes("/api/vsp/top_cwe_v1")) {
        console.warn(LOG, "Stub /api/vsp/top_cwe_v1 – trả dummy rỗng");
        const body = JSON.stringify({
          ok: true,
          items: []
        });
        return Promise.resolve(new Response(body, {
          status: 200,
          headers: { "Content-Type": "application/json" }
        }));
      }

      if (url.includes("/api/vsp/settings/get")) {
        console.warn(LOG, "Stub /api/vsp/settings/get – trả cấu hình rỗng");
        const body = JSON.stringify({
          ok: true,
          profiles: [],
          tool_overrides: []
        });
        return Promise.resolve(new Response(body, {
          status: 200,
          headers: { "Content-Type": "application/json" }
        }));
      }
    } catch (e) {
      console.error(LOG, "shim error", e);
    }

    return ORIG_FETCH(input, init);
  };

  console.log(LOG, "installed");
})();
JS

echo "[PATCH] Đã ghi $JS_DIR/vsp_fetch_shim_v1.js"

############################################
# 3) Đảm bảo template load fetch shim trước các JS khác
############################################
from pathlib import Path

tpl_paths = [
    Path(ROOT) / "templates" / "index.html",
    Path(ROOT) / "my_flask_app" / "templates" / "vsp_5tabs_full.html",
]

snippet = '<script src="/static/js/vsp_fetch_shim_v1.js"></script>'

for tpl in tpl_paths:
    if not tpl.is_file():
        continue
    text = tpl.read_text(encoding="utf-8")
    if "vsp_fetch_shim_v1.js" in text:
        print(f"[PATCH] {tpl} đã có fetch shim – bỏ qua.")
        continue

    # chèn ngay trước vsp_tabs_runtime_v2.js hoặc trước block JS đầu tiên của VSP
    marker = '/static/js/vsp_tabs_runtime_v2.js'
    if marker in text:
        new_text = text.replace(marker, f'/static/js/vsp_fetch_shim_v1.js"></script>\n    <script src="{marker}')
    else:
        # fallback: chèn trước vsp_console_patch_v1.js nếu không có marker trên
        marker2 = '/static/js/vsp_console_patch_v1.js'
        if marker2 in text:
            new_text = text.replace(marker2, f'/static/js/vsp_fetch_shim_v1.js"></script>\n    <script src="{marker2}')
        else:
            # cuối file trước </body>
            new_text = text.replace("</body>",
                                    f'    {snippet}\n  </body>')

    tpl.write_text(new_text, encoding="utf-8")
    print(f"[PATCH] Đã chèn fetch shim vào {tpl}")

print("[PATCH] Done.")
