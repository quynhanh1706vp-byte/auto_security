(function () {
  'use strict';

  function $(sel) {
    return document.querySelector(sel);
  }

  function getValue(selector, fallback) {
    var el = $(selector);
    if (!el) return fallback;
    var v = (el.value || el.textContent || '').trim();
    return v || fallback;
  }

  function setStatus(text, isError) {
    var statusEl = $('#vsp-run-fullscan-status');
    if (!statusEl) return;
    statusEl.textContent = text;
    statusEl.classList.remove('status-ok', 'status-err');
    statusEl.classList.add(isError ? 'status-err' : 'status-ok');
  }

  async function handleRunFullScan(ev) {
    ev.preventDefault();

    var btn = ev.currentTarget;
    var profile = getValue('#vsp-scan-profile', 'FULL_EXT');
    var sourceRoot = getValue('#vsp-scan-source-root', '');
    var targetUrl = getValue('#vsp-scan-target-url', '');

    if (!sourceRoot || !targetUrl) {
      setStatus('Vui lòng điền đủ Source Root và Target URL trước khi chạy.', true);
      return;
    }

    // Disable button + đổi text
    btn.disabled = true;
    if (!btn.dataset.originalText) {
      btn.dataset.originalText = btn.textContent;
    }
    btn.textContent = 'Đang gửi FULL scan...';
    setStatus('Đang gọi /api/vsp/run_full_scan ...', false);

    try {
      var res = await fetch('/api/vsp/run_full_scan', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          profile: profile,
          source_root: sourceRoot,
          target_url: targetUrl
        })
      });

      if (!res.ok) {
        setStatus('HTTP ' + res.status + ' khi gọi run_full_scan.', true);
        return;
      }

      var data = await res.json();
      if (data.ok) {
        var msg = 'Started ' + (data.profile || profile) +
          ' trên ' + (data.source_root || sourceRoot) +
          ' → ' + (data.target_url || targetUrl);
        if (data.pid) msg += ' (PID ' + data.pid + ')';
        setStatus(msg, false);
      } else {
        setStatus(data.message || 'run_full_scan trả về ok=false.', true);
      }
    } catch (err) {
      console.error('[VSP_RUN_FULLSCAN]', err);
      setStatus('Lỗi khi gọi run_full_scan: ' + err, true);
    } finally {
      btn.disabled = false;
      if (btn.dataset.originalText) {
        btn.textContent = btn.dataset.originalText;
      }
    }
  }

  document.addEventListener('DOMContentLoaded', function () {
    var btn = $('#vsp-run-fullscan-btn');
    if (!btn) {
      console.warn('[VSP_RUN_FULLSCAN] Không tìm thấy #vsp-run-fullscan-btn – chưa gắn được handler.');
      return;
    }
    btn.addEventListener('click', handleRunFullScan);
  });
})();
