/**
 * VSP Rule Overrides Renderer V2
 *
 * API expected:
 *  GET /api/vsp/rule_overrides  -> { ok, rules: [ ... ] }
 *  (sau này) POST/PUT để save, ở đây tạm chỉ render view.
 */

let VSP_RO_RULES = [];

async function vspLoadRuleOverrides() {
  const resp = await fetch("/api/vsp/rule_overrides");
  const data = await resp.json();
  return data;
}

function vspRenderRuleOverridesTable(rules) {
  VSP_RO_RULES = rules || [];
  const tbody = document.getElementById("vsp-ro-tbody");
  if (!tbody) return;
  tbody.innerHTML = "";

  VSP_RO_RULES.forEach((r, idx) => {
    const tr = document.createElement("tr");

    const idTd = document.createElement("td");
    idTd.textContent = r.id || "-";
    tr.appendChild(idTd);

    const enTd = document.createElement("td");
    enTd.innerHTML = r.enabled
      ? '<span class="ro-enabled">ON</span>'
      : '<span class="ro-disabled">OFF</span>';
    tr.appendChild(enTd);

    const actTd = document.createElement("td");
    actTd.textContent = r.action || "-";
    tr.appendChild(actTd);

    const matchTd = document.createElement("td");
    const m = r.match || {};
    const chunks = [];
    if (m.tool) chunks.push("tool=" + m.tool);
    if (m.severity) chunks.push("severity=" + m.severity);
    if (m.cwe) chunks.push("cwe=" + m.cwe);
    if (m.rule_id) chunks.push("rule=" + m.rule_id);
    if (m.file_pattern) chunks.push("file~" + m.file_pattern);
    if (m.module_pattern) chunks.push("module~" + m.module_pattern);
    matchTd.textContent = chunks.join(", ") || "-";
    tr.appendChild(matchTd);

    const targetTd = document.createElement("td");
    targetTd.textContent = r.target_severity || "-";
    tr.appendChild(targetTd);

    const prioTd = document.createElement("td");
    prioTd.textContent = r.priority != null ? String(r.priority) : "-";
    tr.appendChild(prioTd);

    const noteTd = document.createElement("td");
    noteTd.textContent = r.note || "";
    tr.appendChild(noteTd);

    const act2Td = document.createElement("td");
    act2Td.innerHTML = `<button class="ro-view-btn" onclick="vspShowRuleDetail(${idx})">View</button>`;
    tr.appendChild(act2Td);

    tbody.appendChild(tr);
  });

  const totalEl = document.getElementById("vsp-ro-total");
  if (totalEl) totalEl.innerText = VSP_RO_RULES.length;
}

function vspShowRuleDetail(idx) {
  const r = VSP_RO_RULES[idx];
  if (!r) return;

  const pane = document.getElementById("vsp-ro-detail");
  if (!pane) return;

  const pre = pane.querySelector("pre");
  if (!pre) return;

  pre.textContent = JSON.stringify(r, null, 2);
}

async function vspInitRuleOverrides() {
  const wrapper = document.getElementById("vsp-ruleoverrides-wrapper");
  if (!wrapper) return;

  try {
    const data = await vspLoadRuleOverrides();
    if (!data.ok) {
      console.error("[VSP][RO] Load failed:", data);
      return;
    }
    vspRenderRuleOverridesTable(data.rules || []);
  } catch (err) {
    console.error("[VSP][RO] Error:", err);
  }
}

window.addEventListener("DOMContentLoaded", vspInitRuleOverrides);
