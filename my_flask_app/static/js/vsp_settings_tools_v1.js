(function () {
  const API_BASE = '/api/vsp';

  const TOOL_META = {
    gitleaks: {
      label: 'Gitleaks',
      notes: 'Secret scan (token, password, API key…).',
      modes: ['inherit']
    },
    semgrep: {
      label: 'Semgrep',
      notes: 'SAST đa ngôn ngữ với local rules.',
      modes: ['inherit', 'fast', 'ext', 'aggr']
    },
    kics: {
      label: 'KICS (IaC)',
      notes: 'IaC scan (Terraform, Dockerfile, Kubernetes, YAML). Auto detect IaC.',
      modes: ['auto', 'inherit', 'fast', 'ext', 'aggr']
    },
    codeql: {
      label: 'CodeQL',
      notes: 'Multi-language (JS/TS, Python, Java, C#, Go) – auto detect languages.',
      modes: ['auto']
    },
    bandit: {
      label: 'Bandit',
      notes: 'Python SAST.',
      modes: ['inherit']
    },
    trivy_fs: {
      label: 'Trivy FS',
      notes: 'FileSystem vuln & misconfig scan.',
      modes: ['inherit']
    },
    syft: {
      label: 'Syft SBOM',
      notes: 'SBOM generator (packages → TRACE severity).',
      modes: ['inherit']
    },
    grype: {
      label: 'Grype',
      notes: 'Vulnerability scan dựa trên SBOM (CVE).',
      modes: ['inherit']
    }
  };

  const DEFAULT_SETTINGS = {
    profile: 'ext',
    src_base: '/home/test/Data',
    tools: {
      gitleaks: { enabled: true,  mode: 'inherit' },
      semgrep: { enabled: true,  mode: 'ext'     },
      kics:    { enabled: true,  mode: 'auto'    },
      codeql:  { enabled: true,  mode: 'auto'    },
      bandit:  { enabled: true,  mode: 'inherit' },
      trivy_fs:{ enabled: true,  mode: 'inherit' },
      syft:    { enabled: true,  mode: 'inherit' },
      grype:   { enabled: true,  mode: 'inherit' }
    }
  };

  function $(sel) {
    return document.querySelector(sel);
  }

  function createEl(tag, className, html) {
    const el = document.createElement(tag);
    if (className) el.className = className;
    if (html !== undefined) el.innerHTML = html;
    return el;
  }

  function mergeSettings(raw) {
    const cfg = JSON.parse(JSON.stringify(DEFAULT_SETTINGS));

    if (!raw || typeof raw !== 'object') return cfg;

    if (raw.profile && typeof raw.profile === 'string') {
      cfg.profile = raw.profile;
    }
    if (typeof raw.src_base === 'string') {
      cfg.src_base = raw.src_base;
    }
    if (raw.tools && typeof raw.tools === 'object') {
      for (const key of Object.keys(TOOL_META)) {
        if (raw.tools[key]) {
          cfg.tools[key].enabled = !!raw.tools[key].enabled;
          if (typeof raw.tools[key].mode === 'string') {
            cfg.tools[key].mode = raw.tools[key].mode;
          }
        }
      }
    }
    return cfg;
  }

  function buildSettingsUI(root, data) {
    root.innerHTML = '';

    const container = createEl('div', 'vsp-settings-container');

    // --- Block: Global Scan Profile + SRC input + Run Scan ---
    const globalCard = createEl('div', 'vsp-card vsp-card-global');
    globalCard.innerHTML = `
      <div class="vsp-card-header">
        <div class="vsp-card-title">Global Scan Profile</div>
        <div class="vsp-card-sub">Chọn profile chung cho Semgrep / KICS / các tool phụ thuộc LEVEL.</div>
      </div>
      <div class="vsp-card-body vsp-global-profile">
        <div class="vsp-profile-options">
          <label class="vsp-radio">
            <input type="radio" name="vsp-profile" value="fast">
            <span class="vsp-radio-label">Fast</span>
            <span class="vsp-radio-desc">Chạy nhanh, ít rule – dùng cho smoke / CI nhanh.</span>
          </label>
          <label class="vsp-radio">
            <input type="radio" name="vsp-profile" value="ext">
            <span class="vsp-radio-label">Extended (EXT)</span>
            <span class="vsp-radio-desc">Cân bằng: rule đủ rộng – dùng cho daily scan.</span>
          </label>
          <label class="vsp-radio">
            <input type="radio" name="vsp-profile" value="aggr">
            <span class="vsp-radio-label">Aggressive (AGGR)</span>
            <span class="vsp-radio-desc">Quét tối đa, chấp nhận chậm – dùng cho full audit.</span>
          </label>
        </div>
        <div class="vsp-src-run">
          <div class="vsp-src-block">
            <label class="vsp-label">Source Path</label>
            <input id="vsp-settings-src-input" type="text" class="vsp-input" placeholder="/home/test/Data/khach6">
            <div class="vsp-help">Thư mục hoặc file .zip. Nếu để trống, sẽ dùng giá trị mặc định từ UI.</div>
          </div>
          <div class="vsp-run-block">
            <button id="vsp-settings-run-btn" class="vsp-btn vsp-btn-primary">Run Scan</button>
            <div id="vsp-settings-run-status" class="vsp-run-status"></div>
          </div>
        </div>
      </div>
    `;
    container.appendChild(globalCard);

    // --- Block: Tool stack table ---
    const toolsCard = createEl('div', 'vsp-card vsp-card-tools');
    const toolsHeader = createEl('div', 'vsp-card-header');
    toolsHeader.innerHTML = `
      <div class="vsp-card-title">Tool Stack Configuration</div>
      <div class="vsp-card-sub">Bật/tắt từng tool và chọn mode (khi cần override Global Profile).</div>
    `;
    toolsCard.appendChild(toolsHeader);

    const toolsBody = createEl('div', 'vsp-card-body');
    const table = createEl('table', 'vsp-table-tools');
    const thead = createEl('thead');
    thead.innerHTML = `
      <tr>
        <th style="min-width: 160px;">Tool</th>
        <th style="width: 90px;">Enabled</th>
        <th style="width: 150px;">Mode</th>
        <th>Notes</th>
      </tr>
    `;
    table.appendChild(thead);

    const tbody = createEl('tbody');

    Object.keys(TOOL_META).forEach((key) => {
      const meta = TOOL_META[key];
      const cfg = data.tools[key] || DEFAULT_SETTINGS.tools[key];

      const tr = createEl('tr', 'vsp-tool-row');
      tr.dataset.toolKey = key;

      const tdName = createEl('td', 'vsp-tool-name', `<div class="vsp-tool-label">${meta.label}</div>`);
      const tdEnabled = createEl('td', 'vsp-tool-enabled');
      const tdMode = createEl('td', 'vsp-tool-mode');
      const tdNotes = createEl('td', 'vsp-tool-notes', meta.notes);

      const enabledId = `vsp-tool-enabled-${key}`;
      tdEnabled.innerHTML = `
        <label class="vsp-switch">
          <input type="checkbox" id="${enabledId}" ${cfg.enabled ? 'checked' : ''}>
          <span class="vsp-switch-slider"></span>
        </label>
      `;

      const select = createEl('select', 'vsp-select');
      select.id = `vsp-tool-mode-${key}`;
      meta.modes.forEach((mode) => {
        const opt = document.createElement('option');
        opt.value = mode;
        opt.textContent = mode.toUpperCase();
        if (cfg.mode === mode) opt.selected = true;
        select.appendChild(opt);
      });
      tdMode.appendChild(select);

      tr.appendChild(tdName);
      tr.appendChild(tdEnabled);
      tr.appendChild(tdMode);
      tr.appendChild(tdNotes);

      tbody.appendChild(tr);
    });

    table.appendChild(tbody);
    toolsBody.appendChild(table);

    const toolsFooter = createEl('div', 'vsp-tools-footer');
    toolsFooter.innerHTML = `
      <div class="vsp-tools-left">
        <div class="vsp-label">Source base path (optional)</div>
        <input id="vsp-settings-src-base" type="text" class="vsp-input" placeholder="/home/test/Data">
        <div class="vsp-help">UI gợi ý SRC dựa trên base path này (không bắt buộc).</div>
      </div>
      <div class="vsp-tools-right">
        <button id="vsp-settings-save-btn" class="vsp-btn vsp-btn-secondary">Save Settings</button>
        <span id="vsp-settings-save-status" class="vsp-save-status"></span>
      </div>
    `;
    toolsBody.appendChild(toolsFooter);

    toolsCard.appendChild(toolsBody);
    container.appendChild(toolsCard);

    root.appendChild(container);

    // Áp giá trị từ config vào UI
    const profileInputs = root.querySelectorAll('input[name="vsp-profile"]');
    profileInputs.forEach((inp) => {
      if (inp.value === data.profile) {
        inp.checked = true;
      }
    });

    const srcBaseInput = $('#vsp-settings-src-base');
    if (srcBaseInput) {
      srcBaseInput.value = data.src_base || '';
    }

    // Gắn event Save + Run
    const saveBtn = $('#vsp-settings-save-btn');
    const runBtn = $('#vsp-settings-run-btn');
    if (saveBtn) {
      saveBtn.addEventListener('click', () => saveSettings(root));
    }
    if (runBtn) {
      runBtn.addEventListener('click', () => runScan(root));
    }
  }

  function collectSettings(root) {
    const profileInputs = root.querySelectorAll('input[name="vsp-profile"]');
    let profile = 'ext';
    profileInputs.forEach((inp) => {
      if (inp.checked) profile = inp.value;
    });

    const srcBase = (root.querySelector('#vsp-settings-src-base') || {}).value || '';

    const tools = {};
    Object.keys(TOOL_META).forEach((key) => {
      const enabledEl = root.querySelector(`#vsp-tool-enabled-${key}`);
      const modeEl = root.querySelector(`#vsp-tool-mode-${key}`);

      tools[key] = {
        enabled: enabledEl ? enabledEl.checked : true,
        mode: modeEl ? modeEl.value : 'inherit'
      };
    });

    return {
      profile,
      src_base: srcBase,
      tools
    };
  }

  async function fetchJSON(url, options) {
    const res = await fetch(url, options || {});
    if (!res.ok) {
      const txt = await res.text();
      throw new Error(`HTTP ${res.status}: ${txt}`);
    }
    return res.json();
  }

  async function loadSettings(root) {
    const status = $('#vsp-settings-save-status');
    try {
      if (status) status.textContent = 'Loading...';
      const data = await fetchJSON(`${API_BASE}/settings`);
      const merged = mergeSettings(data);
      buildSettingsUI(root, merged);
      if (status) status.textContent = '';
    } catch (e) {
      console.error('[VSP][Settings] Load error:', e);
      buildSettingsUI(root, DEFAULT_SETTINGS);
      if (status) status.textContent = 'Error loading settings – using defaults.';
    }
  }

  async function saveSettings(root) {
    const status = $('#vsp-settings-save-status');
    try {
      const payload = collectSettings(root);
      if (status) status.textContent = 'Saving...';

      await fetchJSON(`${API_BASE}/settings`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(payload)
      });

      if (status) status.textContent = 'Saved.';
      setTimeout(() => {
        if (status) status.textContent = '';
      }, 2000);
    } catch (e) {
      console.error('[VSP][Settings] Save error:', e);
      if (status) status.textContent = 'Error saving settings.';
    }
  }

  async function runScan(root) {
    const srcInput = $('#vsp-settings-src-input');
    const runStatus = $('#vsp-settings-run-status');

    const src = srcInput && srcInput.value.trim();
    const payload = src ? { src } : {};

    try {
      if (runStatus) runStatus.textContent = 'Starting scan...';
      const res = await fetchJSON(`${API_BASE}/run_scan`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(payload)
      });

      if (runStatus) {
        if (res && res.ok) {
          runStatus.textContent = 'Scan started.';
        } else {
          runStatus.textContent = 'Scan request sent (check status tab).';
        }
      }
    } catch (e) {
      console.error('[VSP][Settings] Run scan error:', e);
      if (runStatus) runStatus.textContent = 'Error starting scan.';
    }
  }

  function ensureStyles() {
    if (document.getElementById('vsp-settings-styles')) return;
    const style = document.createElement('style');
    style.id = 'vsp-settings-styles';
    style.textContent = `
      .vsp-settings-container {
        display: flex;
        flex-direction: column;
        gap: 16px;
        padding: 8px;
      }
      .vsp-card {
        background: #111827;
        border-radius: 12px;
        padding: 16px 18px;
        border: 1px solid #1f2937;
        box-shadow: 0 12px 30px rgba(0,0,0,0.45);
      }
      .vsp-card-header {
        margin-bottom: 12px;
      }
      .vsp-card-title {
        font-size: 16px;
        font-weight: 600;
        color: #f9fafb;
      }
      .vsp-card-sub {
        font-size: 12px;
        color: #9ca3af;
        margin-top: 2px;
      }
      .vsp-card-body {
        margin-top: 6px;
      }
      .vsp-global-profile {
        display: flex;
        flex-direction: column;
        gap: 12px;
      }
      .vsp-profile-options {
        display: flex;
        flex-wrap: wrap;
        gap: 12px;
      }
      .vsp-radio {
        display: flex;
        flex-direction: column;
        padding: 8px 10px;
        border-radius: 8px;
        border: 1px solid #1f2937;
        background: #020617;
        cursor: pointer;
        min-width: 180px;
      }
      .vsp-radio input {
        margin-bottom: 4px;
      }
      .vsp-radio-label {
        font-size: 13px;
        font-weight: 500;
        color: #e5e7eb;
      }
      .vsp-radio-desc {
        font-size: 11px;
        color: #9ca3af;
      }
      .vsp-src-run {
        display: flex;
        flex-wrap: wrap;
        gap: 16px;
        align-items: flex-end;
      }
      .vsp-src-block {
        flex: 1 1 260px;
      }
      .vsp-run-block {
        display: flex;
        flex-direction: column;
        gap: 4px;
      }
      .vsp-label {
        font-size: 12px;
        color: #d1d5db;
        margin-bottom: 4px;
      }
      .vsp-input {
        width: 100%;
        background: #020617;
        border-radius: 8px;
        border: 1px solid #374151;
        color: #f9fafb;
        font-size: 13px;
        padding: 6px 8px;
      }
      .vsp-input::placeholder {
        color: #6b7280;
      }
      .vsp-help {
        font-size: 11px;
        color: #6b7280;
        margin-top: 3px;
      }
      .vsp-btn {
        border-radius: 999px;
        border: none;
        font-size: 13px;
        padding: 6px 14px;
        cursor: pointer;
        display: inline-flex;
        align-items: center;
        justify-content: center;
        gap: 6px;
        font-weight: 500;
      }
      .vsp-btn-primary {
        background: linear-gradient(to right, #22c55e, #16a34a);
        color: #022c22;
      }
      .vsp-btn-secondary {
        background: #111827;
        color: #e5e7eb;
        border: 1px solid #374151;
      }
      .vsp-run-status, .vsp-save-status {
        font-size: 11px;
        color: #9ca3af;
      }
      .vsp-table-tools {
        width: 100%;
        border-collapse: collapse;
        font-size: 12px;
        margin-top: 4px;
      }
      .vsp-table-tools th,
      .vsp-table-tools td {
        padding: 6px 8px;
        border-bottom: 1px solid #1f2937;
      }
      .vsp-table-tools th {
        text-align: left;
        font-weight: 500;
        color: #9ca3af;
      }
      .vsp-table-tools td {
        color: #e5e7eb;
      }
      .vsp-tool-name {
        font-weight: 500;
      }
      .vsp-tool-notes {
        font-size: 11px;
        color: #9ca3af;
      }
      .vsp-switch {
        position: relative;
        display: inline-block;
        width: 38px;
        height: 20px;
      }
      .vsp-switch input {
        opacity: 0;
        width: 0;
        height: 0;
      }
      .vsp-switch-slider {
        position: absolute;
        cursor: pointer;
        top: 0;
        left: 0;
        right: 0;
        bottom: 0;
        background-color: #374151;
        transition: .2s;
        border-radius: 999px;
      }
      .vsp-switch-slider:before {
        position: absolute;
        content: "";
        height: 14px;
        width: 14px;
        left: 3px;
        bottom: 3px;
        background-color: white;
        transition: .2s;
        border-radius: 50%;
      }
      .vsp-switch input:checked + .vsp-switch-slider {
        background-color: #22c55e;
      }
      .vsp-switch input:checked + .vsp-switch-slider:before {
        transform: translateX(16px);
      }
      .vsp-select {
        width: 100%;
        background: #020617;
        border-radius: 8px;
        border: 1px solid #374151;
        color: #f9fafb;
        font-size: 12px;
        padding: 4px 6px;
      }
      .vsp-tools-footer {
        display: flex;
        flex-wrap: wrap;
        justify-content: space-between;
        gap: 12px;
        margin-top: 10px;
        align-items: center;
      }
      .vsp-tools-left {
        flex: 1 1 260px;
      }
      .vsp-tools-right {
        display: flex;
        align-items: center;
        gap: 8px;
      }
    `;
    document.head.appendChild(style);
  }

  function init() {
    const root =
      document.getElementById('vsp-settings-root') ||
      document.querySelector('#tab-settings .vsp-settings-root');

    if (!root) {
      console.warn('[VSP][Settings] Không tìm thấy container #vsp-settings-root');
      return;
    }

    ensureStyles();
    loadSettings(root);
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }
})();
