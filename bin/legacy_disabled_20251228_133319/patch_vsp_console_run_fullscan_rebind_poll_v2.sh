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
BACKUP="${FILE}.bak_run_fullscan_rebind_poll_${TS}"
cp "$FILE" "$BACKUP"
echo "[BACKUP] Đã backup console patch thành: $BACKUP"

cat >> "$FILE" << 'JS'

// [VSP_RUN_FULLSCAN_REBIND_POLL] rebind nút Run full scan sau khi panel được inject
(function() {
  console.log('[VSP_RUN_FULLSCAN_REBIND_POLL] start');

  var tries = 0;
  var maxTries = 30; // ~6s nếu interval = 200ms

  var timer = setInterval(function() {
    tries += 1;

    var btn = document.querySelector('#vsp-run-fullscan-btn');
    if (!btn) {
      if (tries >= maxTries) {
        console.warn('[VSP_RUN_FULLSCAN_REBIND_POLL] Hết số lần thử, không thấy nút.');
        clearInterval(timer);
      }
      return;
    }

    if (btn.dataset.vspRunRebound === '1') {
      console.log('[VSP_RUN_FULLSCAN_REBIND_POLL] Nút đã được bind trước đó, dừng poll.');
      clearInterval(timer);
      return;
    }

    // Clone để xoá toàn bộ listener cũ (bao gồm alert "Vui lòng nhập Target URL")
    var newBtn = btn.cloneNode(true);
    btn.parentNode.replaceChild(newBtn, btn);
    newBtn.dataset.vspRunRebound = '1';

    var inputRoot  = document.querySelector('#vsp-source-root');
    var inputUrl   = document.querySelector('#vsp-target-url');
    var selProfile = document.querySelector('#vsp-profile');

    newBtn.addEventListener('click', function() {
      var sourceRoot = (inputRoot && inputRoot.value || '').trim();
      var targetUrl  = (inputUrl  && inputUrl.value  || '').trim();
      var profile    = (selProfile && selProfile.value || '').trim() || 'FULL_EXT';

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

      console.log('[VSP_RUN_FULLSCAN_REBIND_POLL] payload', payload);

      fetch('/api/vsp/run_fullscan_v1', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(payload)
      })
      .then(function(r) { return r.json(); })
      .then(function(data) {
        console.log('[VSP_RUN_FULLSCAN_REBIND_POLL] resp', data);
        if (!data.ok) {
          window.alert('Run full scan failed: ' + (data.error || 'unknown error'));
        }
      })
      .catch(function(err) {
        console.error('[VSP_RUN_FULLSCAN_REBIND_POLL] error', err);
        window.alert('Có lỗi khi gửi yêu cầu run full scan.');
      });
    });

    console.log('[VSP_RUN_FULLSCAN_REBIND_POLL] Đã bind lại nút Run full scan.');
    clearInterval(timer);
  }, 200);
})();
JS

echo "[OK] Đã append poll rebind vào vsp_console_patch_v1.js"
