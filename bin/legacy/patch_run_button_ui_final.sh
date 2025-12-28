#!/usr/bin/env bash
set -euo pipefail

ROOT="/home/test/Data/SECURITY_BUNDLE/ui"
cd "$ROOT"

JS="static/js/run_scan_handler_v3.js"
TPL="templates/index.html"

echo "[i] ROOT = $ROOT"
echo "[i] JS   = $JS"
echo "[i] TPL  = $TPL"

########################################
# 1) Tạo JS handler mới cho nút Run scan
########################################
cat > "$JS" <<'JSSRC'
(function () {
  document.addEventListener('DOMContentLoaded', function () {
    const btn =
      document.getElementById('btn-run-scan') ||
      document.querySelector('[data-role="run-scan"]');

    if (!btn) {
      console.warn('[RUN] Không tìm thấy nút Run scan (#btn-run-scan).');
      return;
    }

    function getSrcFolder() {
      // Thử nhiều selector cho chắc
      const cand =
        document.querySelector('#src-folder') ||
        document.querySelector('#src_folder') ||
        document.querySelector('input[name="src_folder"]') ||
        document.querySelector('[data-role="src-folder"]');

      return cand ? cand.value.trim() : '';
    }

    btn.addEventListener('click', async function (e) {
      e.preventDefault();
      const src = getSrcFolder();

      if (!src) {
        alert('Vui lòng nhập SRC folder trước khi Run scan.');
        return;
      }

      btn.disabled = true;
      const oldText = btn.innerText;
      btn.innerText = 'Running...';

      try {
        const resp = await fetch('/api/run_scan_v2', {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json'
          },
          body: JSON.stringify({ src_folder: src })
        });

        const data = await resp.json().catch(() => ({}));

        if (!resp.ok || !data.ok) {
          console.error('[RUN] API lỗi:', data);
          alert('Run scan thất bại.\n' + (data.error || 'HTTP ' + resp.status));
        } else {
          console.log('[RUN] Scan OK:', data);
          alert('Run scan OK cho:\n' + src + '\n\nMở lại Dashboard để xem kết quả mới.');
          // refresh nhẹ để Dashboard đọc last_summary_unified.json mới
          window.location.href = '/';
        }
      } catch (err) {
        console.error('[RUN] Fetch error:', err);
        alert('Lỗi khi gọi /api/run_scan_v2. Xem console log.');
      } finally {
        btn.disabled = false;
        btn.innerText = oldText;
      }
    });
  });
})();
JSSRC

echo "[OK] Đã ghi $JS"

####################################################
# 2) Đảm bảo nút Run scan có id="btn-run-scan"
####################################################
python3 - "$TPL" <<'PY'
import sys, pathlib, re

path = pathlib.Path(sys.argv[1])
data = path.read_text(encoding="utf-8")

# Tìm button có text 'Run scan'
pattern = r"<button([^>]*)>(\s*Run scan\s*)</button>"
m = re.search(pattern, data, flags=re.IGNORECASE)
if not m:
    print("[WARN] Không tìm thấy button 'Run scan' trong template.", file=sys.stderr)
else:
    attrs = m.group(1)
    text = m.group(2)
    if 'id=' not in attrs:
        new_attrs = attrs + ' id="btn-run-scan"'
    else:
        # Thay id cũ thành btn-run-scan
        new_attrs = re.sub(r'id\s*=\s*"[^\"]*"', 'id="btn-run-scan"', attrs)
    repl = f"<button{new_attrs}>{text}</button>"
    data = data[:m.start()] + repl + data[m.end():]
    path.write_text(data, encoding="utf-8")
    print("[OK] Đã gắn id=\"btn-run-scan\" cho nút Run scan.")
PY

######################################################
# 3) Chèn <script src="static/js/run_scan_handler_v3.js">
######################################################
# Nếu đã có rồi thì bỏ qua
if ! grep -q "run_scan_handler_v3.js" "$TPL"; then
  python3 - "$TPL" <<'PY'
import sys, pathlib

path = pathlib.Path(sys.argv[1])
data = path.read_text(encoding="utf-8")

snippet = '\n  <script src="{{ url_for(\\'static\\', filename=\\'js/run_scan_handler_v3.js\\') }}"></script>\n'

if "js/run_scan_handler_v3.js" in data:
    print("[OK] Script đã có trong template, bỏ qua.")
else:
    idx = data.rfind("</body>")
    if idx == -1:
        print("[WARN] Không thấy </body> để chèn script.", file=sys.stderr)
    else:
        data = data[:idx] + snippet + data[idx:]
        path.write_text(data, encoding="utf-8")
        print("[OK] Đã chèn script run_scan_handler_v3.js vào index.html.")
PY
else
  echo "[OK] Template đã include run_scan_handler_v3.js trước đó."
fi

echo "[DONE] patch_run_button_ui_final.sh hoàn thành."
