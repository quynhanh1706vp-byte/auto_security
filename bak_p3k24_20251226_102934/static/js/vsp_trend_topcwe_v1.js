// ======================= VSP TOP CWE EXPOSURE V1 =======================
// Cung cấp 2 hàm global cho vsp_dashboard_live_v2.js:
//   - api_TOPCWE_v1()      -> Promise<{ ok, items: [{cwe, count}] }>
//   - renderTopCweBar(payload)  -> render vào panel Top CWE Exposure

(function () {
  async function api_TOPCWE_v1() {
    try {
      const res = await fetch('/api/vsp/dashboard_v3');
      if (!res.ok) {
        console.warn('[VSP][TOPCWE] /api/vsp/dashboard_v3 HTTP', res.status);
        return { ok: false, items: [] };
      }
      const data = await res.json();
      let items = [];
      const raw = data.top_cwe;

      if (Array.isArray(raw)) {
        // [{cwe, count, ...}, ...]
        items = raw.map(it => ({
          cwe: it.cwe || it.CWE || 'UNKNOWN',
          count: it.count || it.total || 0
        }));
      } else if (raw && typeof raw === 'object') {
        // {cwe:'UNKNOWN', total:1458} hoặc tương tự
        items = [{
          cwe: raw.cwe || raw.CWE || 'UNKNOWN',
          count: raw.total || raw.count || data.total_findings || 0
        }];
      } else {
        // Fallback: 1 entry UNKNOWN = tổng findings
        const total = data.total_findings || 0;
        items = [{ cwe: 'UNKNOWN', count: total }];
      }

      return { ok: true, items };
    } catch (e) {
      console.error('[VSP][TOPCWE] api_TOPCWE_v1 error:', e);
      return { ok: false, items: [] };
    }
  }

  function renderTopCweBar(payload) {
    try {
      const root =
        document.querySelector('[data-vsp-topcwe]') ||
        document.getElementById('vsp-topcwe-panel');

      if (!root) {
        // Không có panel, thôi bỏ qua.
        return;
      }

      const items = (payload && payload.items) || [];
      if (!items.length) {
        root.innerHTML = '<div class="vsp-empty-hint">No CWE data for this run.</div>';
        return;
      }

      const max = items.reduce((m, it) => Math.max(m, it.count || 0), 0) || 1;

      const rows = items.slice(0, 6).map(it => {
        const w = Math.round((it.count || 0) * 100 / max);
        return `
          <div class="vsp-topcwe-row">
            <span class="vsp-topcwe-code">${it.cwe}</span>
            <span class="vsp-topcwe-bar">
              <span class="vsp-topcwe-bar-fill" style="width:${w}%"></span>
            </span>
            <span class="vsp-topcwe-count">${it.count}</span>
          </div>
        `;
      }).join('');

      root.innerHTML = `
        <div class="vsp-topcwe-legend">
          <span class="label">CWE</span>
          <span class="label">Count</span>
        </div>
        <div class="vsp-topcwe-rows">
          ${rows}
        </div>
      `;
    } catch (e) {
      console.error('[VSP][TOPCWE] renderTopCweBar error:', e);
    }
  }

  // Expose globals cho vsp_dashboard_live_v2.js
  window.api_TOPCWE_v1 = api_TOPCWE_v1;
  window.renderTopCweBar = renderTopCweBar;

  // Auto init nếu file được load sau DOMContentLoaded
  if (document.readyState === 'complete' || document.readyState === 'interactive') {
    api_TOPCWE_v1().then(renderTopCweBar);
  } else {
    document.addEventListener('DOMContentLoaded', () => {
      api_TOPCWE_v1().then(renderTopCweBar);
    });
  }
})();
