#!/usr/bin/env bash
set -euo pipefail

# Overwrite toàn bộ vsp_runs_fullscan_panel_v1.js
# - Cho phép run:
#   + chỉ Source root (EXT_ONLY)
#   + chỉ Target URL (URL_ONLY)
#   + hoặc cả 2 (FULL_EXT)
# - Check: nếu cả hai đều rỗng thì báo lỗi.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UI_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
FILE="$UI_ROOT/static/js/vsp_runs_fullscan_panel_v1.js"

if [ ! -f "$FILE" ]; then
  echo "[ERR] Không tìm thấy file JS panel: $FILE" >&2
  exit 1
fi

TS="$(date +%Y%m%d_%H%M%S)"
BACKUP="${FILE}.bak_overwrite_${TS}"
cp "$FILE" "$BACKUP"
echo "[BACKUP] Đã backup file gốc thành: $BACKUP"

cat > "$FILE" << 'JS'
// vsp_runs_fullscan_panel_v1.js – OVERWRITE V1
// Hỗ trợ EXT_ONLY / URL_ONLY / FULL_EXT.

(function() {
  console.log("[VSP_RUN_FULLSCAN_PANEL] loaded overwrite v1");

  function $(sel) {
    return document.querySelector(sel);
  }

  function vspInitRunFullscanPanel() {
    const btn        = $("#vsp-run-fullscan-btn");
    const inputRoot  = $("#vsp-source-root");
    const inputUrl   = $("#vsp-target-url");
    const selProfile = $("#vsp-profile");

    if (!btn) {
      console.log("[VSP_RUN_FULLSCAN_PANEL] Không tìm thấy nút #vsp-run-fullscan-btn");
      return;
    }

    btn.addEventListener("click", () => {
      const sourceRoot = (inputRoot && inputRoot.value || "").trim();
      const targetUrl  = (inputUrl  && inputUrl.value  || "").trim();
      const profile    = (selProfile && selProfile.value || "").trim() || "FULL_EXT";

      // Ít nhất phải có 1 trong 2
      if (!sourceRoot && !targetUrl) {
        alert("Vui lòng nhập ít nhất Source root hoặc Target URL.");
        return;
      }

      let mode;
      if (sourceRoot && targetUrl) {
        mode = "FULL_EXT";
      } else if (sourceRoot && !targetUrl) {
        mode = "EXT_ONLY";
      } else {
        mode = "URL_ONLY";
      }

      const payload = {
        source_root: sourceRoot || null,
        target_url:  targetUrl  || null,
        mode: mode,
        profile: profile
      };

      console.log("[VSP_RUN_FULLSCAN] payload", payload);

      fetch("/api/vsp/run_fullscan_v1", {
        method: "POST",
        headers: {
          "Content-Type": "application/json"
        },
        body: JSON.stringify(payload)
      })
      .then(r => r.json())
      .then(data => {
        console.log("[VSP_RUN_FULLSCAN] resp", data);
        if (!data.ok) {
          alert("Run full scan failed: " + (data.error || "unknown error"));
        } else {
          // Có thể sau này trigger reload tab Runs, v.v.
        }
      })
      .catch(err => {
        console.error("[VSP_RUN_FULLSCAN] error", err);
        alert("Có lỗi khi gửi yêu cầu run full scan.");
      });
    });

    console.log("[VSP_RUN_FULLSCAN_PANEL] bind xong nút Run full scan");
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", vspInitRunFullscanPanel);
  } else {
    vspInitRunFullscanPanel();
  }
})();
JS

echo "[OK] Đã overwrite vsp_runs_fullscan_panel_v1.js với logic EXT_ONLY/URL_ONLY/FULL_EXT."
