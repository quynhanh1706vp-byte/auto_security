#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
JS_DIR="$ROOT/static/js"
TPL1="$ROOT/templates/vsp_dashboard_2025.html"
TPL2="$ROOT/templates/vsp_5tabs_full.html"

mkdir -p "$JS_DIR"

TOP_JS="$JS_DIR/vsp_dashboard_top_module_dom_v1.js"

echo "[INFO] ROOT = $ROOT"
echo "[INFO] Viết DOM patch vào $TOP_JS"

cat > "$TOP_JS" << 'JS'
(function () {
  const LOG_PREFIX = "[VSP_TOP_MODULE_DOM]";

  function cleanupOnce() {
    try {
      const root = document.querySelector("#vsp-root") || document;
      if (!root) return;

      // Tìm phần tử có text "Top vulnerable module"
      const all = Array.from(root.querySelectorAll("*"));
      const labelEls = all.filter((el) => {
        if (!el || !el.textContent) return false;
        return el.textContent.trim() === "Top vulnerable module";
      });

      if (!labelEls.length) return;

      labelEls.forEach((labelEl) => {
        let valueEl = labelEl.nextElementSibling;
        if (!valueEl) {
          // thử tìm trong cùng block
          const parent = labelEl.parentElement;
          if (!parent) return;
          const candidates = Array.from(parent.children).filter((c) => c !== labelEl);
          valueEl = candidates[0] || null;
        }
        if (!valueEl) return;

        const raw = (valueEl.textContent || "").trim();
        if (!raw) return;

        let textOut = raw;

        // Nếu là JSON thì parse -> label/path/id
        try {
          const parsed = JSON.parse(raw);
          if (parsed && typeof parsed === "object") {
            textOut =
              parsed.label ||
              parsed.path ||
              parsed.id ||
              raw;
          }
        } catch (e) {
          // không phải JSON thì giữ nguyên
        }

        if (textOut && textOut.length > 80) {
          textOut = textOut.slice(0, 77) + "...";
        }

        if (textOut && textOut !== raw) {
          console.log(LOG_PREFIX, "Normalize top module:", raw, "=>", textOut);
          valueEl.textContent = textOut;
        }
      });
    } catch (err) {
      console.error(LOG_PREFIX, "cleanup error:", err);
    }
  }

  function startWatcher() {
    let tries = 0;
    const maxTries = 30; // ~15s nếu 500ms/lần

    const timer = setInterval(() => {
      tries += 1;
      cleanupOnce();
      if (tries >= maxTries) {
        clearInterval(timer);
      }
    }, 500);
  }

  // Chạy khi load xong
  if (document.readyState === "complete" || document.readyState === "interactive") {
    startWatcher();
  } else {
    window.addEventListener("DOMContentLoaded", startWatcher);
  }

  // Nếu dashboard có trigger event custom thì cũng bắt thêm
  window.addEventListener("vspDashboardV3Rendered", function () {
    console.log(LOG_PREFIX, "Received vspDashboardV3Rendered event");
    cleanupOnce();
  });
})();
JS

add_script_tag() {
  local TPL="$1"
  if [ ! -f "$TPL" ]; then
    return
  fi

  local BAK="${TPL}.bak_top_module_dom_$(date +%Y%m%d_%H%M%S)"
  cp "$TPL" "$BAK"
  echo "[BACKUP] $TPL -> $BAK"

  python - << PY
from pathlib import Path

path = Path(r"$TPL")
txt = path.read_text(encoding="utf-8")

tag = "{{ url_for('static', filename='js/vsp_dashboard_top_module_dom_v1.js') }}"
script_line = '    <script src="' + tag + '"></script>\\n'

if tag in txt:
    print("[INFO] Script DOM patch đã tồn tại trong", path.name)
else:
    # chèn trước </body>
    if "</body>" in txt:
        txt = txt.replace("</body>", script_line + "</body>")
        print("[PATCH] Chèn script DOM patch vào", path.name)
        path.write_text(txt, encoding="utf-8")
    else:
        print("[WARN] Không tìm thấy </body> trong", path.name)
PY
}

add_script_tag "$TPL1"
add_script_tag "$TPL2"

echo "[DONE] patch_vsp_dashboard_top_module_dom_v1.sh hoàn tất."
