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
BACKUP="${FILE}.bak_run_fullscan_capture_${TS}"
cp "$FILE" "$BACKUP"
echo "[BACKUP] Đã backup console patch thành: $BACKUP"

FILE="$FILE" python - << 'PY'
import os, pathlib

path = pathlib.Path(os.environ["FILE"])
txt = path.read_text(encoding="utf-8")

BLOCK = r"""
// [VSP_RUN_FULLSCAN_CAPTURE_V1] Override click Run full scan (EXT_ONLY / URL_ONLY / FULL_EXT)
(function() {
  console.log('[VSP_RUN_FULLSCAN_CAPTURE_V1] start');

  function bindRunFullscanCapture() {
    var btn = document.querySelector('#vsp-run-fullscan-btn');
    if (!btn) {
      return;
    }
    if (btn.dataset.vspRunCaptureBound === '1') {
      return;
    }
    btn.dataset.vspRunCaptureBound = '1';

    console.log('[VSP_RUN_FULLSCAN_CAPTURE_V1] Bind capture listener cho nút Run full scan.');

    btn.addEventListener('click', function(ev) {
      // Chặn toàn bộ handler cũ (bao gồm alert "Vui lòng nhập Target URL.")
      ev.preventDefault();
      ev.stopImmediatePropagation();

      var card = btn.closest('.vsp-card') || btn.closest('section') || document;
      var inputs = card.querySelectorAll('input');

      var sourceRoot = inputs[0] ? (inputs[0].value || '').trim() : '';
      var targetUrl  = inputs[1] ? (inputs[1].value || '').trim() : '';

      var profileSel = card.querySelector('select');
      var profile = profileSel && profileSel.value ? profileSel.value.trim() : 'FULL_EXT';

      console.log('[VSP_RUN_FULLSCAN_CAPTURE_V1] values', {
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

      console.log('[VSP_RUN_FULLSCAN_CAPTURE_V1] payload', payload);

      fetch('/api/vsp/run_fullscan_v1', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(payload)
      })
      .then(function(r) { return r.json(); })
      .then(function(data) {
        console.log('[VSP_RUN_FULLSCAN_CAPTURE_V1] resp', data);
        if (!data.ok) {
          window.alert('Run full scan failed: ' + (data.error || 'unknown error'));
        }
      })
      .catch(function(err) {
        console.error('[VSP_RUN_FULLSCAN_CAPTURE_V1] error', err);
        window.alert('Có lỗi khi gửi yêu cầu run full scan.');
      });
    }, true); // <= CAPTURE = true
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', function() {
      setTimeout(bindRunFullscanCapture, 800);
    });
  } else {
    setTimeout(bindRunFullscanCapture, 800);
  }

  // Phòng trường hợp panel inject muộn
  var tries = 0;
  var maxTries = 30;
  var timer = setInterval(function() {
    tries += 1;
    bindRunFullscanCapture();
    if (tries >= maxTries) {
      clearInterval(timer);
    }
  }, 200);
})();
"""

txt = txt.rstrip() + "\n" + BLOCK.strip() + "\n"
path.write_text(txt, encoding="utf-8")
print("[DONE] Append VSP_RUN_FULLSCAN_CAPTURE_V1 vào", path)
PY
