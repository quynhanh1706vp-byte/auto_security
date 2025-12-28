#!/usr/bin/env bash
set -euo pipefail

ROOT="/home/test/Data/SECURITY_BUNDLE/ui"
APP="$ROOT/run_ui_server.py"
TPL="$ROOT/templates/index.html"
JS="$ROOT/static/patch_dashboard_run_scan.js"

echo "[i] ROOT = $ROOT"
echo "[i] APP  = $APP"
echo "[i] TPL  = $TPL"
echo "[i] JS   = $JS"

if [ ! -f "$APP" ]; then
  echo "[ERR] Không tìm thấy $APP (nhớ đang dùng run_ui_server.py)"
  exit 1
fi

if [ ! -f "$TPL" ]; then
  echo "[ERR] Không tìm thấy $TPL"
  exit 1
fi

mkdir -p "$(dirname "$JS")"

########################################
# 1) Tạo JS: bắt nút Run scan trên Dashboard
########################################
cat > "$JS" <<'JS'
(function () {
  function log(msg) {
    console.log('[RUN-SCAN]', msg);
  }

  function findRunScanButton() {
    var candidates = document.querySelectorAll(
      'button, a, input[type="button"], input[type="submit"]'
    );
    for (var i = 0; i < candidates.length; i++) {
      var el = candidates[i];
      var text = ((el.textContent || el.innerText || el.value || '') + '').trim().toLowerCase();
      if (text === 'run scan' || text.indexOf('run scan') !== -1) {
        return el;
      }
    }
    return null;
  }

  function findSrcInput() {
    // Ưu tiên placeholder có chữ Khach hoặc SRC/FOLDER
    var inputs = document.querySelectorAll('input[type="text"], input[type="search"]');
    var best = null;
    for (var i = 0; i < inputs.length; i++) {
      var el = inputs[i];
      var ph = (el.placeholder || '').toLowerCase();
      if (ph.indexOf('khach') !== -1 || ph.indexOf('src') !== -1 || ph.indexOf('folder') !== -1) {
        return el;
      }
      // fallback: nếu có value /home/test/Data/Khach thì cũng dùng
      var v = (el.value || '').toLowerCase();
      if (v.indexOf('khach') !== -1) {
        best = el;
      }
    }
    return best;
  }

  function findTargetUrlInput() {
    var inputs = document.querySelectorAll('input[type="text"], input[type="url"]');
    for (var i = 0; i < inputs.length; i++) {
      var el = inputs[i];
      var ph = (el.placeholder || '').toLowerCase();
      if (ph.indexOf('https://app.example.com') !== -1 ||
          ph.indexOf('target url') !== -1 ||
          ph.indexOf('domain') !== -1) {
        return el;
      }
    }
    return null;
  }

  function showStatus(msg, isError) {
    var id = 'run-scan-status';
    var el = document.getElementById(id);
    if (!el) {
      el = document.createElement('div');
      el.id = id;
      el.style.marginTop = '8px';
      el.style.fontSize = '12px';
      el.style.opacity = '0.9';
      var dashboardTitle = document.querySelector('h2, h1');
      if (dashboardTitle && dashboardTitle.parentNode) {
        dashboardTitle.parentNode.appendChild(el);
      } else {
        document.body.appendChild(el);
      }
    }
    el.textContent = msg;
    el.style.color = isError ? '#ff6b6b' : '#a0ff9f';
  }

  function attach() {
    var btn = findRunScanButton();
    var srcInput = findSrcInput();

    if (!btn) {
      log('Không tìm thấy nút Run scan.');
      return;
    }
    if (!srcInput) {
      log('Không tìm thấy ô SRC FOLDER.');
    }

    var targetInput = findTargetUrlInput();

    log('Đã gắn handler cho nút Run scan.');

    btn.addEventListener('click', function (e) {
      try { e.preventDefault(); } catch (_) {}

      var src = srcInput ? (srcInput.value || '').trim() : '';
      var target = targetInput ? (targetInput.value || '').trim() : '';

      if (!src) {
        showStatus('Bạn chưa nhập SRC FOLDER.', true);
        alert('Bạn chưa nhập SRC FOLDER.');
        return;
      }

      // Normalize: nếu thiếu dấu / đầu, tự thêm
      if (src[0] !== '/' && !src.startsWith('~')) {
        src = '/' + src.replace(/^\/+/, '');
      }

      showStatus('Đang gửi yêu cầu scan cho: ' + src + ' ...', false);
      btn.disabled = true;

      fetch('/api/run_scan_simple', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json'
        },
        body: JSON.stringify({
          src_folder: src,
          target_url: target
        })
      })
        .then(function (res) { return res.json().catch(function(){ return {}; }); })
        .then(function (data) {
          btn.disabled = false;
          if (!data || data.ok === false) {
            var err = (data && data.error) || 'Không rõ lỗi.';
            showStatus('Run scan thất bại: ' + err, true);
            alert('Run scan thất bại: ' + err);
            return;
          }
          showStatus('Đã bắt đầu scan với SRC=' + data.src + '. Vui lòng đợi vài phút rồi F5 Dashboard.', false);
        })
        .catch(function (err) {
          btn.disabled = false;
          console.error('[RUN-SCAN] Lỗi gọi /api/run_scan_simple:', err);
          showStatus('Lỗi gọi /api/run_scan_simple. Xem console.', true);
        });
    });
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', attach);
  } else {
    attach();
  }
})();
JS

echo "[OK] Đã ghi $JS"

########################################
# 2) Include JS mới vào index.html
########################################
python3 - "$TPL" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
data = path.read_text(encoding="utf-8")

snippet = "patch_dashboard_run_scan.js"
if snippet in data:
    print("[INFO] templates/index.html đã include patch_dashboard_run_scan.js, bỏ qua.")
    raise SystemExit(0)

insert = '    <script src="{{ url_for(\'static\', filename=\'patch_dashboard_run_scan.js\') }}"></script>\\n</body>'

if "</body>" not in data:
    print("[ERR] Không tìm thấy </body> trong templates/index.html")
    raise SystemExit(1)

new_data = data.replace("</body>", insert)
path.write_text(new_data, encoding="utf-8")
print("[OK] Đã chèn script patch_dashboard_run_scan.js trước </body>.")
PY

########################################
# 3) Thêm API /api/run_scan_simple vào run_ui_server.py
########################################
python3 - "$APP" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
data = path.read_text(encoding="utf-8")

# Thêm import request, jsonify nếu chưa có
if "from flask import request, jsonify" not in data:
    if "from app import app" in data:
        data = data.replace(
            "from app import app",
            "from app import app\nfrom flask import request, jsonify",
            1,
        )
        print("[OK] Đã thêm import request, jsonify.")
    else:
        print("[WARN] Không tìm thấy 'from app import app', bỏ qua thêm import.")

if "/api/run_scan_simple" in data:
    print("[INFO] Đã có /api/run_scan_simple, không chèn nữa.")
    path.write_text(data, encoding="utf-8")
    raise SystemExit(0)

block = r'''
@app.route("/api/run_scan_simple", methods=["POST"])
def api_run_scan_simple():
    """
    Gọi bin/run_all_tools_v2.sh với SRC lấy từ Dashboard.
    Chạy nền, trả JSON báo đã nhận request.
    """
    import os
    from subprocess import Popen
    from pathlib import Path as _Path

    try:
        payload = request.get_json(force=True, silent=True) or {}
    except Exception:
        payload = {}

    src = payload.get("src_folder") or request.form.get("src_folder") or ""
    target = payload.get("target_url") or request.form.get("target_url") or ""

    src = (src or "").strip()
    if not src:
        return jsonify({"ok": False, "error": "src_folder is required"}), 400

    # Chuẩn hóa path: hỗ trợ ~/..., /..., và thiếu dấu / đầu
    if src.startswith("~"):
        src_path = _Path(os.path.expanduser(src))
    elif src.startswith("/"):
        src_path = _Path(src)
    else:
        src_path = _Path("/" + src.lstrip("/"))

    if not src_path.exists() or not src_path.is_dir():
        return jsonify({"ok": False, "error": f"SRC folder not found: {src_path}"}), 400

    ROOT = _Path(__file__).resolve().parent.parent  # /home/test/Data/SECURITY_BUNDLE
    env = os.environ.copy()
    env["SRC"] = str(src_path)
    if target:
        env["TARGET_URL"] = str(target)

    log_dir = ROOT / "out" / "logs"
    log_dir.mkdir(parents=True, exist_ok=True)
    log_file = log_dir / "run_scan_simple.log"

    with log_file.open("ab") as f:
        Popen(
            ["bash", "bin/run_all_tools_v2.sh"],
            cwd=str(ROOT),
            env=env,
            stdout=f,
            stderr=f,
        )

    return jsonify({"ok": True, "src": str(src_path)})
'''

# chèn block trước if __name__ == "__main__": nếu có
marker = 'if __name__ == "__main__":'
if marker in data:
    new_data = data.replace(marker, block + "\n\n" + marker, 1)
else:
    new_data = data.rstrip() + "\n\n" + block + "\n"

path.write_text(new_data, encoding="utf-8")
print("[OK] Đã chèn API /api/run_scan_simple vào run_ui_server.py")
PY

echo "[DONE] patch_run_scan_from_dashboard.sh hoàn thành."
