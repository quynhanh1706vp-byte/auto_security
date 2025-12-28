#!/usr/bin/env bash
set -euo pipefail

ROOT="/home/test/Data/SECURITY_BUNDLE/ui"
echo "[PATCH] Inject VSP_TABS_V2 vào index.html + vsp_5tabs_full.html"

python - << 'PY'
import pathlib, time

ROOT = pathlib.Path("/home/test/Data/SECURITY_BUNDLE/ui")
targets = [
    ROOT / "templates" / "index.html",
    ROOT / "my_flask_app" / "templates" / "vsp_5tabs_full.html",
]

snippet = """
<script>
  // VSP_TABS_V2: simple tab switcher, chạy sau khi DOM ready
  document.addEventListener('DOMContentLoaded', function () {
    console.log('[VSP_TABS] binding tab buttons');

    var buttons = document.querySelectorAll('.vsp-tab-btn');
    var panes   = document.querySelectorAll('.tab-pane');

    if (!buttons.length || !panes.length) {
      console.warn('[VSP_TABS] Không tìm thấy tabs để bind.');
      return;
    }

    function activateTab(targetId) {
      panes.forEach(function (p) {
        if (p.id === targetId) {
          p.classList.add('active');
        } else {
          p.classList.remove('active');
        }
      });
      buttons.forEach(function (b) {
        if (b.dataset.tab === targetId) {
          b.classList.add('active');
        } else {
          b.classList.remove('active');
        }
      });
    }

    buttons.forEach(function (btn) {
      btn.addEventListener('click', function (e) {
        e.preventDefault();
        var targetId = btn.dataset.tab;
        if (!targetId) return;
        console.log('[VSP_TABS] switch to', targetId);
        activateTab(targetId);
      });
    });

    var activeBtn = document.querySelector('.vsp-tab-btn.active') || buttons[0];
    if (activeBtn && activeBtn.dataset.tab) {
      activateTab(activeBtn.dataset.tab);
    }
  });
</script>
""".strip()

for path in targets:
    if not path.is_file():
        print(f"[SKIP] {path} (không tồn tại)")
        continue

    txt = path.read_text(encoding="utf-8")
    if "[VSP_TABS] binding tab buttons" in txt:
        print(f"[SKIP] {path} đã có VSP_TABS_V2")
        continue

    if "</body>" in txt:
        backup = path.with_suffix(path.suffix + f".bak_tabs_inject_{time.strftime('%Y%m%d_%H%M%S')}")
        backup.write_text(txt, encoding="utf-8")
        new_txt = txt.replace("</body>", snippet + "\n\n</body>")
        path.write_text(new_txt, encoding="utf-8")
        print(f"[OK] Injected VSP_TABS_V2 vào {path} (backup -> {backup.name})")
    else:
        print(f"[WARN] {path} không chứa </body>, bỏ qua.")
PY

echo "[PATCH] Done."
