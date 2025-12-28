/**
 * VSP Data Source Renderer V2
 *
 * Đọc data từ /api/vsp/datasource_v2 (schema VSP_FINDING_V1)
 * Render bảng findings + drawer chi tiết.
 */

let VSP_DS_ITEMS = [];

// ------------------------------
// Severity → màu
// ------------------------------
const VSP_SEV_COLORS = {
  "CRITICAL": "#ff0033",
  "HIGH": "#ff6600",
  "MEDIUM": "#ffaa00",
  "LOW": "#00b300",
  "INFO": "#00aaff",
  "TRACE": "#aaaaaa"
};

async function vspLoadDataSource(filters = {}) {
  const params = new URLSearchParams(filters);
  const resp = await fetch(`/api/vsp/datasource_v2?${params.toString()}`);
  const data = await resp.json();
  return data;
}

function vspRenderDataSourceTable(items) {
  VSP_DS_ITEMS = items || [];

  const tbody = document.getElementById("vsp-datasource-tbody");
  if (!tbody) return;
  tbody.innerHTML = "";

  VSP_DS_ITEMS.forEach((f, idx) => {
    const tr = document.createElement("tr");
    tr.className = "vsp-ds-row";
    tr.dataset.index = String(idx);

    tr.addEventListener("click", () => {
      vspOpenFindingDrawer(idx);
    });

    // ==== Severity ====
    const sevTd = document.createElement("td");
    const sevColor = VSP_SEV_COLORS[f.severity_effective] || "#888";
    sevTd.innerHTML = `
      <span class="vsp-sev-badge" style="background:${sevColor}">
        ${f.severity_effective}
      </span>
    `;
    tr.appendChild(sevTd);

    // ==== Tool ====
    const toolTd = document.createElement("td");
    toolTd.textContent = f.tool || "-";
    toolTd.className = "vsp-ds-tool";
    tr.appendChild(toolTd);

    // ==== File + line + language ====
    const fileTd = document.createElement("td");
    const langBadge = f.code_context && f.code_context.language
      ? `<span class="vsp-lang-badge">${f.code_context.language}</span>`
      : "";
    fileTd.innerHTML = `
      <div class="vsp-file-main">${f.file || "-"}</div>
      <div class="vsp-file-meta">
        Line ${f.line || "-"} ${langBadge}
      </div>
    `;
    tr.appendChild(fileTd);

    // ==== Asset ====
    const assetTd = document.createElement("td");
    if (f.asset && f.asset.package_name) {
      assetTd.innerHTML = `
        <div class="vsp-asset-main">
          ${f.asset.package_name} ${f.asset.package_version || ""}
        </div>
        <div class="vsp-asset-meta">
          ${f.asset.package_type || ""}
        </div>
      `;
    } else {
      assetTd.innerHTML = "-";
    }
    tr.appendChild(assetTd);

    // ==== CVE / CVSS ====
    const vulnTd = document.createElement("td");
    if (f.vuln && f.vuln.cve_id) {
      vulnTd.innerHTML = `
        <div class="vsp-cve-badge">${f.vuln.cve_id}</div>
        <div class="vsp-cvss-meta">CVSS: ${f.vuln.cvss_score ?? "-"} </div>
      `;
    } else {
      vulnTd.innerHTML = "-";
    }
    tr.appendChild(vulnTd);

    // ==== Message short ====
    const msgTd = document.createElement("td");
    const msg = (f.title || f.message || "").trim();
    msgTd.textContent = msg.length > 90 ? msg.slice(0, 90) + "…" : msg;
    msgTd.className = "vsp-ds-message";
    tr.appendChild(msgTd);

    // ==== Override tag ====
    const ovTd = document.createElement("td");
    if (f.overridden) {
      ovTd.innerHTML = `<span class="vsp-override-tag">Override (${f.override_rule_id || "rule"})</span>`;
    } else {
      ovTd.innerHTML = "-";
    }
    tr.appendChild(ovTd);

    tbody.appendChild(tr);
  });
}

// ------------------------------
// Drawer chi tiết
// ------------------------------
function vspOpenFindingDrawer(index) {
  const f = VSP_DS_ITEMS[index];
  if (!f) return;

  const drawer = document.getElementById("vsp-finding-drawer");
  if (!drawer) return;
  drawer.classList.add("open");

  // HEADER
  const titleEl = document.getElementById("vsp-fd-title");
  const sevEl = document.getElementById("vsp-fd-severity");
  const toolEl = document.getElementById("vsp-fd-tool");
  const runEl = document.getElementById("vsp-fd-runid");

  if (titleEl) titleEl.innerText = f.title || f.message || "(No title)";
  if (sevEl) {
    sevEl.style.background = VSP_SEV_COLORS[f.severity_effective] || "#666";
    sevEl.innerText = f.severity_effective;
  }
  if (toolEl) toolEl.innerText = f.tool || "-";
  if (runEl) runEl.innerText = f.run_id || "-";

  // LOCATION
  const fileEl = document.getElementById("vsp-fd-file");
  const lineEl = document.getElementById("vsp-fd-line");
  const langEl = document.getElementById("vsp-fd-language");

  if (fileEl) fileEl.innerText = f.file || "-";
  if (lineEl) lineEl.innerText = f.line || "-";
  if (langEl) langEl.innerText = f.code_context?.language || "-";

  // ASSET
  const assetBox = document.getElementById("vsp-fd-asset");
  if (assetBox) {
    if (f.asset && f.asset.package_name) {
      assetBox.innerHTML = `
        <div><b>Package:</b> ${f.asset.package_name} ${f.asset.package_version || ""}</div>
        <div><b>Type:</b> ${f.asset.package_type || "-"}</div>
      `;
    } else {
      assetBox.innerHTML = "(No asset)";
    }
  }

  // VULN
  const vulnBox = document.getElementById("vsp-fd-vuln");
  if (vulnBox) {
    if (f.vuln && f.vuln.cve_id) {
      vulnBox.innerHTML = `
        <div><b>CVE:</b> ${f.vuln.cve_id}</div>
        <div><b>CVSS:</b> ${f.vuln.cvss_score ?? "-"} (${f.vuln.cvss_vector || ""})</div>
        <div><b>Fixed:</b> ${f.vuln.fixed_version || "-"}</div>
        <div class="vsp-vuln-desc">${f.vuln.vuln_description || ""}</div>
      `;
    } else {
      vulnBox.innerHTML = "(No vulnerability metadata)";
    }
  }

  // SNIPPET
  const snipBox = document.getElementById("vsp-fd-snippet");
  if (snipBox) {
    if (f.evidence && f.evidence.code_snippet) {
      snipBox.innerHTML = `<pre class="vsp-snippet">${f.evidence.code_snippet}</pre>`;
    } else {
      snipBox.innerHTML = "(No snippet available)";
    }
  }

  // FIX GUIDE
  const fixBox = document.getElementById("vsp-fd-fix");
  const fg = f.fix_guide || {};
  if (fixBox) {
    if (fg.short_title) {
      const steps = (fg.dev_fix_steps || []).map(s => `<li>${s}</li>`).join("");
      fixBox.innerHTML = `
        <h4>${fg.short_title}</h4>
        <p>${fg.non_tech_summary || ""}</p>
        <p><b>Business risk:</b> ${fg.business_risk || "-"}</p>
        <p><b>Priority:</b> ${fg.priority || "-"}</p>
        <p><b>Deadline:</b> ${fg.recommended_deadline_days || "-"} days</p>
        <h5>Dev root cause</h5>
        <pre>${fg.dev_root_cause || "-"}</pre>
        <h5>Fix steps</h5>
        <ul>${steps}</ul>
      `;
    } else {
      fixBox.innerHTML = "(No fix guide)";
    }
  }

  // COMPLIANCE
  const compBox = document.getElementById("vsp-fd-compliance");
  if (compBox) {
    const cp = f.compliance || {};
    const chips = [];
    if (cp.owasp && cp.owasp.length)
      chips.push(`<span class="vsp-cmp-chip vsp-cmp-owasp">OWASP: ${cp.owasp.join(", ")}</span>`);
    if (cp.iso27001 && cp.iso27001.length)
      chips.push(`<span class="vsp-cmp-chip vsp-cmp-iso">ISO: ${cp.iso27001.join(", ")}</span>`);
    if (cp.nist && cp.nist.length)
      chips.push(`<span class="vsp-cmp-chip vsp-cmp-nist">NIST: ${cp.nist.join(", ")}</span>`);
    if (cp.cis && cp.cis.length)
      chips.push(`<span class="vsp-cmp-chip vsp-cmp-cis">CIS: ${cp.cis.join(", ")}</span>`);

    compBox.innerHTML = chips.length ? chips.join(" ") : "(No compliance mapping)";
  }
}

function vspCloseFindingDrawer() {
  const drawer = document.getElementById("vsp-finding-drawer");
  if (drawer) drawer.classList.remove("open");
}

// ------------------------------
// INIT
// ------------------------------
async function vspInitDataSource() {
  const tableWrapper = document.getElementById("vsp-datasource-wrapper");
  if (!tableWrapper) return;

  try {
    const data = await vspLoadDataSource({});
    if (!data.ok) {
      console.error("[VSP][DS] Load failed:", data);
      return;
    }
    vspRenderDataSourceTable(data.items || []);
    const totalEl = document.getElementById("vsp-ds-total");
    if (totalEl) totalEl.innerText = data.total ?? (data.items || []).length;
  } catch (err) {
    console.error("[VSP][DS] Error:", err);
  }
}

window.addEventListener("DOMContentLoaded", vspInitDataSource);
