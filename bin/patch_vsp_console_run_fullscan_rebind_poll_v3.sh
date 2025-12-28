#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UI_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
FILE="$UI_ROOT/static/js/vsp_console_patch_v1.js"

if [ ! -f "$FILE" ]; then
  echo "[ERR] Không tìm thấy vsp_console_patch_v1.js: $FILE" >&2
  exit 1
fi

TS="$(date +%Y%m%d_%H%M%S)"
BACKUP="${FILE}.bak_run_fullscan_rebind_poll_v3_${TS}"
cp "$FILE" "$BACKUP"
echo "[BACKUP] Đã backup console patch thành: $BACKUP"

python - << 'PY'
import pathlib, os

path = pathlib.Path(os.environ["FILE"])
txt = path.read_text(encoding="utf-8")

marker = "// [VSP_RUN_FULLSCAN_REBIND_POLL]"
idx = txt.find(marker)

if idx != -1:
    print("[INFO] Tìm thấy block REBIND_POLL cũ, sẽ thay thế.")
    txt = txt[:idx]
else:
    print("[INFO] Không thấy block REBIND_POLL cũ, sẽ append mới vào cuối file.")

NEW_BLOCK = r"""
// [VSP_RUN_FULLSCAN_REBIND_POLL] rebind nút Run full scan sau khi panel được inject (V2)
(function() {
  console.log('[VSP_RUN_FULLSCAN_REBIND_POLL_V2] start');

  var tries = 0;
  var maxTries = 30; // ~6s nếu interval = 200ms

  var timer = setInterval(function() {
    tries += 1;

    var btn = document.querySelector('#vsp-run-fullscan-btn');
    if (!btn) {
      if (tries >= maxTries) {
        console.warn('[VSP_RUN_FULLSCAN_REBIND_POLL_V2] Hết số lần thử, không thấy nút.');
        clearInterval(timer);
      }
      return;
    }

    if (btn.dataset.vspRunReboundV2 === '1') {
      console.log('[VSP_RUN_FULLSCAN_REBIND_POLL_V2] Nút đã được bind V2, dừng poll.');
      clearInterval(timer);
      return;
    }

    // Clone để xoá mọi listener cũ
    var newBtn = btn.cloneNode(true);
    btn.parentNode.replaceChild(newBtn, btn);
    newBtn.dataset.vspRunReboundV2 = '1';

    console.log('[VSP_RUN_FULLSCAN_REBIND_POLL_V2] Đã clone nút Run full scan.');

    newBtn.addEventListener('click', function() {
      // Lấy 2 ô input trong cùng card/panel với nút
      var card = newBtn.closest('.vsp-card') || newBtn.closest('section') || document;
      var inputs = card.querySelectorAll('input');

      var sourceRoot = inputs[0] ? (inputs[0].value || '').trim() : '';
      var targetUrl  = inputs[1] ? (inputs[1].value || '').trim() : '';

      var profileSel = card.querySelector('select');
      var profile = profileSel && profileSel.value ? profileSel.value.trim() : 'FULL_EXT';

      console.log('[VSP_RUN_FULLSCAN_REBIND_POLL_V2] current values', {
        sourceRoot: sourceRoot,
        targetUrl: targetUrl,
        profile: profile
      });

      if (!sourceRoot && !targetUrl) {
        window.alert('Vui lòng nhập ít nhất Source root hoặc Target URL.');
        return;
      }

      var mode;
      if (sourceRoot && targetUrl) {
        mode = 'FULL_EXT';
      } else if (sourceRoot && !targetUrl) {
        mode = 'EXT_ONLY';
      } else {
        mode = 'URL_ONLY';
      }

      var payload = {
        source_root: sourceRoot || null,
        target_url:  targetUrl  || null,
        profile: profile,
        mode: mode
      };

      console.log('[VSP_RUN_FULLSCAN_REBIND_POLL_V2] payload', payload);

      fetch('/api/vsp/run_fullscan_v1', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(payload)
      })
      .then(function(r) { return r.json(); })
      .then(function(data) {
        console.log('[VSP_RUN_FULLSCAN_REBIND_POLL_V2] resp', data);
        if (!data.ok) {
          window.alert('Run full scan failed: ' + (data.error || 'unknown error'));
        }
      })
      .catch(function(err) {
        console.error('[VSP_RUN_FULLSCAN_REBIND_POLL_V2] error', err);
        window.alert('Có lỗi khi gửi yêu cầu run full scan.');
      });
    });

    console.log('[VSP_RUN_FULLSCAN_REBIND_POLL_V2] Đã bind lại nút Run full scan.');
    clearInterval(timer);
  }, 200);
})();
"""

txt = txt.rstrip() + "\n" + NEW_BLOCK.strip() + "\n"
path.write_text(txt, encoding="utf-8")
print("[DONE] Đã ghi block REBIND_POLL_V2 vào", path)
PY
