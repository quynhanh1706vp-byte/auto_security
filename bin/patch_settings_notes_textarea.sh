#!/usr/bin/env bash
set -euo pipefail

ROOT="/home/test/Data/SECURITY_BUNDLE/ui"
BASE="$ROOT/templates/base.html"

echo "[i] ROOT = $ROOT"
echo "[i] BASE = $BASE"

if [ ! -f "$BASE" ]; then
  echo "[ERR] Không tìm thấy templates/base.html"
  exit 1
fi

python3 - "$BASE" <<'PY'
import sys, pathlib

path = pathlib.Path(sys.argv[1])
html = path.read_text()

marker = "<!-- PATCH_TOOL_NOTES_DISPLAY -->"
if marker in html:
    print("[OK] base.html đã có PATCH_TOOL_NOTES_DISPLAY, bỏ qua.")
else:
    js = r"""<!-- PATCH_TOOL_NOTES_DISPLAY -->
<script>
(function () {
  function upgradeNotesInputsOnce() {
    // tìm table có header GHI CHÚ
    var tables = Array.from(document.querySelectorAll('table'));
    var target = null;
    tables.forEach(function(t){
      var headers = Array.from(t.querySelectorAll('th')).map(function(th){
        return (th.textContent || '').trim().toUpperCase();
      });
      if (headers.includes('GHI CHÚ') || headers.includes('GHI CHU')) {
        target = t;
      }
    });
    if (!target) return false;

    var rows = Array.from(target.querySelectorAll('tr'));
    rows.forEach(function(row){
      if (row.querySelector('th')) return;
      var cells = row.children;
      if (!cells || cells.length === 0) return;
      var noteCell = cells[cells.length - 1];
      if (!noteCell) return;
      if (noteCell.dataset.upgraded === '1') return;

      var input = noteCell.querySelector('input,textarea');
      if (!input) return;

      // Nếu đã là textarea thì chỉ style lại
      var ta;
      if (input.tagName.toLowerCase() === 'textarea') {
        ta = input;
      } else {
        ta = document.createElement('textarea');
        ta.value = input.value;
        ta.className = input.className;
        ta.readOnly = input.readOnly;
        noteCell.replaceChild(ta, input);
      }

      ta.rows = 3;
      ta.style.width = '100%';
      ta.style.resize = 'vertical';
      ta.style.whiteSpace = 'normal';
      ta.style.overflowY = 'auto';
      ta.title = ta.value;  // hover thấy full text
      noteCell.dataset.upgraded = '1';
    });

    return true;
  }

  function schedule() {
    var tries = 0, maxTries = 40;
    function tick() {
      var ok = upgradeNotesInputsOnce();
      tries++;
      if (ok || tries >= maxTries) {
        clearInterval(timer);
      }
    }
    var timer = setInterval(tick, 500);
    tick();
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', schedule);
  } else {
    schedule();
  }
})();
</script>
"""
    if "</body>" not in html:
        print("[ERR] Không tìm thấy </body> trong base.html")
    else:
        html = html.replace("</body>", marker + "\n" + js + "\n</body>")
        path.write_text(html)
        print("[OK] Đã chèn PATCH_TOOL_NOTES_DISPLAY vào base.html")
PY

echo "[DONE] patch_settings_notes_textarea.sh hoàn thành."
