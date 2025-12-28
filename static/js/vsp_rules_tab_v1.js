(function () {
  const API_URL = '/api/vsp/rule_overrides_ui_v1';
  const INIT_DELAY_MS = 1200;

  function esc(s) {
    if (s == null) return '';
    return String(s)
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;');
  }

  function renderSkeleton(tab) {
    tab.innerHTML = `
      <div class="vsp-tab-inner vsp-tab-rules">
        <div class="vsp-tab-header">
          <h2>Rule Overrides</h2>
          <p class="vsp-tab-subtitle">
            Quản lý các rule đã được chấp nhận rủi ro hoặc điều chỉnh severity. Dùng để giảm “noise”
            nhưng vẫn giữ được trace đầy đủ.
          </p>
        </div>

        <div class="vsp-card vsp-card-note">
          <p>
            Cơ chế rule overrides giúp:
          </p>
          <ul class="vsp-list">
            <li>Hạ severity cho một số rule đã được kiểm soát bằng biện pháp khác.</li>
            <li>Ẩn các findings đã được chấp nhận rủi ro nhưng vẫn lưu trong log để truy vết.</li>
            <li>Import/export bộ rule để áp dụng cho nhiều project.</li>
          </ul>
        </div>

        <div class="vsp-card vsp-table-card">
          <div class="vsp-table-header">
            <div>
              <h3>Current overrides</h3>
              <p class="vsp-table-subtitle">
                Danh sách rule override đang được áp dụng (theo tool, rule, CWE, action).
              </p>
            </div>
          </div>

          <div class="vsp-table-wrapper">
            <table class="vsp-table" id="vsp-rules-table">
              <thead>
                <tr>
                  <th>Tool</th>
                  <th>Rule ID</th>
                  <th>CWE</th>
                  <th>Action</th>
                  <th>Target</th>
                  <th>Reason</th>
                </tr>
              </thead>
              <tbody>
                <tr><td colspan="6" class="vsp-table-loading">Đang tải danh sách rule overrides…</td></tr>
              </tbody>
            </table>
          </div>
        </div>
      </div>
    `;
  }

  async function bindRules(tab) {
    renderSkeleton(tab);

    const tbody = tab.querySelector('#vsp-rules-table tbody');
    if (!tbody) return;

    let data;
    try {
      const res = await fetch(API_URL, { cache: 'no-store' });
      data = await res.json();
    } catch (e) {
      console.error('[VSP_RULES_TAB] Failed to load rule_overrides_ui_v1', e);
      tbody.innerHTML = `<tr><td colspan="6" class="vsp-table-error">
        Không tải được rule overrides từ API.
      </td></tr>`;
      return;
    }

    const items = Array.isArray(data.overrides)
      ? data.overrides
      : Array.isArray(data) ? data : [];

    if (!items.length) {
      tbody.innerHTML = `<tr><td colspan="6" class="vsp-table-empty">
        Hiện chưa có rule override nào. Hệ thống đang dùng rule mặc định của các tool.
      </td></tr>`;
      return;
    }

    tbody.innerHTML = items.map(o => {
      const tool = o.tool || '-';
      const ruleId = o.rule_id || o.id || '-';
      const cwe = o.cwe || o.cwe_id || '-';
      const action = o.action || o.mode || '-';
      const target = o.target || o.path || o.module || '-';
      const reason = o.reason || o.note || '-';

      return `
        <tr>
          <td>${esc(tool)}</td>
          <td>${esc(ruleId)}</td>
          <td>${esc(cwe)}</td>
          <td>${esc(action)}</td>
          <td class="vsp-mono">${esc(target)}</td>
          <td>${esc(reason)}</td>
        </tr>
      `;
    }).join('');

    console.log('[VSP_RULES_TAB] Rendered', items.length, 'rule overrides.');
  }

  let initialized = false;

  function tryInit() {
    if (initialized) return;
    const tab = document.querySelector('#vsp-tab-rules');
    if (!tab) {
      setTimeout(tryInit, 500);
      return;
    }
    initialized = true;
    setTimeout(() => bindRules(tab), INIT_DELAY_MS);
  }

  tryInit();
})();
