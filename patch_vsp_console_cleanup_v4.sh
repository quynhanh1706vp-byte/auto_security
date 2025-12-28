#!/usr/bin/env bash
set -euo pipefail

ROOT="/home/test/Data/SECURITY_BUNDLE/ui"
JS_DIR="$ROOT/static/js"
TPL_DIR="$ROOT/templates"
MY_TPL_DIR="$ROOT/my_flask_app/templates"

echo "[PATCH] VSP – console cleanup v4 (fetch shim + gắn đúng template)"

############################################
# 1) Ghi / cập nhật fetch shim
############################################
cat > "$JS_DIR/vsp_fetch_shim_v1.js" << 'JS'
(function () {
  const LOG = "[VSP_FETCH_SHIM]";
  const ORIG = (window.fetch && window.fetch.bind(window)) || fetch;

  function log(...args) {
    try {
      console.warn(LOG, ...args);
    } catch (e) {}
  }

  window.fetch = function (input, init) {
    let url = (typeof input === "string") ? input : (input && input.url) || "";

    // Chuẩn hóa: chỉ lấy path để so pattern nếu cần
    try {
      const u = new URL(url, window.location.origin);
      url = u.pathname + u.search;
    } catch (e) {
      // nếu không parse được thì dùng nguyên string
    }

    // 1) Legacy bug: /api/vsp/runs_index_v3_v3
    if (url.includes("/api/vsp/runs_index_v3_v3")) {
      const fixed = url.replace("runs_index_v3_v3", "runs_index_v3");
      log("redirect runs_index_v3_v3 ->", fixed);
      return ORIG(fixed, init);
    }

    // 2) Legacy API: /api/vsp/runs_v2 -> runs_index_v3
    if (url.includes("/api/vsp/runs_v2")) {
      const fixed = url.replace("runs_v2", "runs_index_v3");
      log("redirect runs_v2 ->", fixed);
      return ORIG(fixed, init);
    }

    // 3) Legacy top_cwe_v1 – stub rỗng, tránh 404
    if (url.includes("/api/vsp/top_cwe_v1")) {
      log("stub top_cwe_v1");
      const body = JSON.stringify({ ok: true, items: [] });
      return Promise.resolve(new Response(body, {
        status: 200,
        headers: { "Content-Type": "application/json" }
      }));
    }

    // 4) Legacy settings/get – stub rỗng, tránh 404
    if (url.includes("/api/vsp/settings/get")) {
      log("stub settings/get");
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

    return ORIG(input, init);
  };

  console.log(LOG, "installed");
})();
JS

echo "[PATCH] Đã ghi $JS_DIR/vsp_fetch_shim_v1.js"

############################################
# 2) Chèn shim vào các template HTML dùng thật
############################################
PYTHON=$(command -v python3 || command -v python)

$PYTHON << 'PY'
from pathlib import Path

ROOT = Path("/home/test/Data/SECURITY_BUNDLE/ui")
tpl_candidates = [
    ROOT / "templates" / "index.html",
    ROOT / "templates" / "vsp_dashboard_2025.html",
    ROOT / "templates" / "vsp_index.html",
    ROOT / "my_flask_app" / "templates" / "vsp_5tabs_full.html",
]

snippet = '  <script src="/static/js/vsp_fetch_shim_v1.js"></script>\n</body>'

for t in tpl_candidates:
    if not t.exists():
        print("[PATCH] (skip) không thấy", t)
        continue
    txt = t.read_text(encoding="utf-8")
    if "vsp_fetch_shim_v1.js" in txt:
        print("[PATCH] shim đã có trong", t)
        continue
    if "</body>" not in txt:
        print("[PATCH] (skip) không tìm thấy </body> trong", t)
        continue

    backup = t.with_suffix(t.suffix + ".bak_console_v4")
    backup.write_text(txt, encoding="utf-8")

    txt = txt.replace("</body>", snippet)
    t.write_text(txt, encoding="utf-8")
    print("[PATCH] chèn shim vào", t, "(backup ->", backup.name, ")")
PY

echo "[PATCH] Done."
