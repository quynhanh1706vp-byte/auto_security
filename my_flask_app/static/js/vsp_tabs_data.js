async function vspFetchJson(url) {
  const res = await fetch(url);
  if (!res.ok) throw new Error("HTTP " + res.status);
  return await res.json();
}

// ---------------- RUNS & REPORTS ----------------
async function renderVspRunsTab() {
  const container = document.getElementById("tab-runs");
  if (!container) return;

  try {
    const data = await vspFetchJson("/api/vsp/runs_v2_index");
    const runs = data.runs || [];

    if (!runs.length) {
      container.innerHTML = '<div class="vsp-empty">Chưa có RUN nào trong thư mục <code>out/</code>.</div>';
      return;
    }

    const rowsHtml = runs
      .map((r, idx) => {
        const sev = r.severity || {};
        return `
          <tr>
            <td>${idx + 1}</td>
            <td>${r.run_id}</td>
            <td>${r.ts || ""}</td>
            <td title="${r.src_path || ""}">${r.src_path || ""}</td>
            <td>${r.profile || ""}</td>
            <td>${r.total_findings}</td>
            <td>${sev.CRITICAL || 0}</td>
            <td>${sev.HIGH || 0}</td>
            <td>${sev.MEDIUM || 0}</td>
            <td>${sev.LOW || 0}</td>
            <td>${sev.INFO || 0}</td>
            <td>${sev.TRACE || 0}</td>
            <td>${(r.tools || []).join(", ")}</td>
            <td>
              ${r.report_html ? `<a href="${r.report_html}" target="_blank">HTML</a>` : "-"}
              ${r.report_pdf ? ` | <a href="${r.report_pdf}" target="_blank">PDF</a>` : ""}
            </td>
          </tr>`;
      })
      .join("");

    container.innerHTML = `
      <h2 class="vsp-section-title">Runs & Reports</h2>
      <p class="vsp-section-subtitle">
        Lịch sử các lần quét từ thư mục <code>out/RUN_*</code>. Luôn lấy data thật từ SECURITY_BUNDLE.
      </p>
      <div class="vsp-table-wrapper">
        <table class="vsp-table">
          <thead>
            <tr>
              <th>#</th>
              <th>Run ID</th>
              <th>Timestamp</th>
              <th>Source</th>
              <th>Profile</th>
              <th>Total</th>
              <th>CRIT</th>
              <th>HIGH</th>
              <th>MED</th>
              <th>LOW</th>
              <th>INFO</th>
              <th>TRACE</th>
              <th>Tools</th>
              <th>Report</th>
            </tr>
          </thead>
          <tbody>${rowsHtml}</tbody>
        </table>
      </div>
    `;
  } catch (err) {
    console.error(err);
    container.innerHTML = '<div class="vsp-error">Không tải được dữ liệu Runs & Reports.</div>';
  }
}

// ---------------- DATA SOURCE ----------------
async function renderVspDataTab() {
  const container = document.getElementById("tab-data");
  if (!container) return;

  try {
    const data = await vspFetchJson("/api/vsp/datasource_v2");
    if (!data.ok) {
      container.innerHTML = '<div class="vsp-empty">Không có <code>findings_unified.json</code> để hiển thị.</div>';
      return;
    }
    const rows = data.rows || [];

    const rowsHtml = rows
      .map((r) => {
        return `
          <tr>
            <td>${r.idx}</td>
            <td>${r.tool}</td>
            <td>${r.severity}</td>
            <td>${r.rule_id}</td>
            <td>${r.title}</td>
            <td title="${r.file}">${r.file}</td>
            <td>${r.line}</td>
            <td>${r.cwe || ""}</td>
            <td>${r.cve || ""}</td>
          </tr>`;
      })
      .join("");

    container.innerHTML = `
      <h2 class="vsp-section-title">Data Source – findings_unified</h2>
      <p class="vsp-section-subtitle">
        Run: <code>${data.run_id}</code> – Hiển thị tối đa 300 findings đầu tiên (tổng: ${data.total_rows}).
      </p>
      <div class="vsp-table-wrapper">
        <table class="vsp-table">
          <thead>
            <tr>
              <th>#</th>
              <th>Tool</th>
              <th>Severity</th>
              <th>Rule</th>
              <th>Title / Message</th>
              <th>File</th>
              <th>Line</th>
              <th>CWE</th>
              <th>CVE</th>
            </tr>
          </thead>
          <tbody>${rowsHtml}</tbody>
        </table>
      </div>
    `;
  } catch (err) {
    console.error(err);
    container.innerHTML = '<div class="vsp-error">Không tải được Data Source.</div>';
  }
}

// ---------------- SETTINGS ----------------
async function renderVspSettingsTab() {
  const container = document.getElementById("tab-settings");
  if (!container) return;

  try {
    const s = await vspFetchJson("/api/vsp/settings");

    const toolsList = (s.tools_enabled || [])
      .map((t) => `<span class="vsp-pill">${t}</span>`)
      .join("");

    container.innerHTML = `
      <h2 class="vsp-section-title">Engine Settings</h2>
      <div class="vsp-settings-grid">
        <div class="vsp-card">
          <div class="vsp-card-label">Profile</div>
          <div class="vsp-card-value">${s.profile_label || ""}</div>
        </div>
        <div class="vsp-card">
          <div class="vsp-card-label">Source path</div>
          <div class="vsp-card-value"><code>${s.src_path || ""}</code></div>
        </div>
        <div class="vsp-card">
          <div class="vsp-card-label">Engine mode</div>
          <div class="vsp-card-value">${s.engine_mode || "offline"}</div>
        </div>
        <div class="vsp-card">
          <div class="vsp-card-label">Last run</div>
          <div class="vsp-card-value"><code>${s.last_run_id || "-"}</code></div>
        </div>
      </div>

      <h3 class="vsp-subsection-title">Tools enabled</h3>
      <div class="vsp-pill-row">
        ${toolsList || "<span class='vsp-empty'>Không phát hiện tool nào.</span>"}
      </div>
    `;
  } catch (err) {
    console.error(err);
    container.innerHTML = '<div class="vsp-error">Không tải được Settings.</div>';
  }
}

// ---------------- RULE OVERRIDES ----------------
async function renderVspRulesTab() {
  const container = document.getElementById("tab-rules");
  if (!container) return;

  try {
    const data = await vspFetchJson("/api/vsp/rule_overrides");
    const rules = data.rules || [];

    if (!rules.length) {
      container.innerHTML = `
        <h2 class="vsp-section-title">Rule Overrides</h2>
        <p class="vsp-section-subtitle">
          Nguồn: <code>rules/vsp_rule_overrides.json</code>. Hiện tại chưa có rule override nào.
        </p>
      `;
      return;
    }

    const rowsHtml = rules
      .map((r, idx) => {
        return `
          <tr>
            <td>${idx + 1}</td>
            <td>${r.tool}</td>
            <td>${r.rule_id}</td>
            <td>${r.match}</td>
            <td>${r.action}</td>
            <td>${r.note || ""}</td>
          </tr>`;
      })
      .join("");

    container.innerHTML = `
      <h2 class="vsp-section-title">Rule Overrides / Noise Control</h2>
      <p class="vsp-section-subtitle">
        Các rule bị bỏ qua / hạ mức độ / custom theo context dự án (nguồn: <code>rules/vsp_rule_overrides.json</code>).
      </p>
      <div class="vsp-table-wrapper">
        <table class="vsp-table">
          <thead>
            <tr>
              <th>#</th>
              <th>Tool</th>
              <th>Rule ID</th>
              <th>Match</th>
              <th>Action</th>
              <th>Note</th>
            </tr>
          </thead>
          <tbody>${rowsHtml}</tbody>
        </table>
      </div>
    `;
  } catch (err) {
    console.error(err);
    container.innerHTML = '<div class="vsp-error">Không tải được Rule Overrides.</div>';
  }
}

// ---------------- BOOTSTRAP ----------------
document.addEventListener("DOMContentLoaded", () => {
  renderVspRunsTab();
  renderVspDataTab();
  renderVspSettingsTab();
  renderVspRulesTab();
});
