#!/usr/bin/env bash
set -euo pipefail

UI_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
JS="$UI_ROOT/static/js/vsp_console_patch_v1.js"
BACKUP="$JS.bak_extra_load_$(date +%Y%m%d_%H%M%S)"

if [ ! -f "$JS" ]; then
  echo "[ERR] Không tìm thấy $JS"
  exit 1
fi

cp "$JS" "$BACKUP"
echo "[BACKUP] $JS -> $BACKUP"

cd "$UI_ROOT"

python - << 'PY'
from pathlib import Path

p = Path("static/js/vsp_console_patch_v1.js")
src = p.read_text(encoding="utf-8")

marker = "[VSP_CONSOLE_EXTRA]"
if marker in src:
    print("[INFO] Extra loader đã tồn tại, bỏ qua.")
else:
    block = r"""
;(function () {
  const LOG_PREFIX = "[VSP_CONSOLE_EXTRA]";
  const extraScripts = [
    "vsp_runs_tab_kpi_inject_v1.js",
    "vsp_datasource_ext_columns_v1.js",
    "vsp_datasource_export_v1.js",
    "vsp_datasource_charts_v1.js",
    "vsp_settings_tab_v1.js",
    "vsp_rules_tab_v1.js",
    "vsp_runs_fullscan_panel_v1.js"
  ];

  function loadExtra(name) {
    try {
      var url = "/static/js/" + name;
      var s = document.createElement("script");
      s.src = url;
      s.defer = true;
      s.onload = function () {
        try {
          console.log(LOG_PREFIX, "loaded", name);
        } catch (e) {}
      };
      s.onerror = function () {
        try {
          console.warn(LOG_PREFIX, "failed", name);
        } catch (e) {}
      };
      document.head.appendChild(s);
    } catch (e) {
      try {
        console.error(LOG_PREFIX, "error injecting", name, e);
      } catch (e2) {}
    }
  }

  if (typeof window !== "undefined" && document && document.head) {
    extraScripts.forEach(loadExtra);
  } else {
    try {
      console.warn(LOG_PREFIX, "document/head chưa sẵn sàng – skip extra scripts.");
    } catch (e) {}
  }
})();
"""
    src = src.rstrip() + "\n\n" + block + "\n"
    p.write_text(src, encoding="utf-8")
    print("[PATCH] Đã chèn extra loader vào vsp_console_patch_v1.js")
PY

echo "[DONE] patch_vsp_console_load_extra_js_v1 completed."
