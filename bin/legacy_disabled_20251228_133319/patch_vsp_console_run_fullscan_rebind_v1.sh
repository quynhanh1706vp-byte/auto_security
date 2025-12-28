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
BACKUP="${FILE}.bak_run_fullscan_rebind_${TS}"
cp "$FILE" "$BACKUP"
echo "[BACKUP] Đã backup console patch thành: $BACKUP"

cat >> "$FILE" << 'JS'

// [VSP_RUN_FULLSCAN_REBIND] allow EXT_ONLY / URL_ONLY / FULL_EXT
(function() {
  function rebindRunFullscan() {
    var btn = document.querySelector('#vsp-run-fullscan-btn');
    if (!btn) {
      console.log('[VSP_RUN_FULLSCAN_REBIND] Không thấy nút #vsp-run-fullscan-btn');
      return;
    }

    // Chỉ bind 1 lần
    if (btn.dataset.vspRunRebound === '1') {
      console.log('[VSP_RUN_FULLSCAN_REBIND] Đã bind trước đó, skip.');
      return;
    }

    // Clone để xoá hết event listener cũ
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

      // Rule: phải có ÍT NHẤT 1 trong 2
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

      console.log('[VSP_RUN_FULLSCAN_REBIND] payload', payload);

      fetch('/api/vsp/run_fullscan_v1', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(payload)
      })
      .then(function(r) { return r.json(); })
      .then(function(data) {
        console.log('[VSP_RUN_FULLSCAN_REBIND] resp', data);
        if (!data.ok) {
          window.alert('Run full scan failed: ' + (data.error || 'unknown error'));
        }
      })
      .catch(function(err) {
        console.error('[VSP_RUN_FULLSCAN_REBIND] error', err);
        window.alert('Có lỗi khi gửi yêu cầu run full scan.');
      });
    });

    console.log('[VSP_RUN_FULLSCAN_REBIND] Đã bind lại nút Run full scan.');
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', rebindRunFullscan);
  } else {
    rebindRunFullscan();
  }
})();
JS

echo "[OK] Đã append khối rebind Run full scan vào vsp_console_patch_v1.js"
