(function () {
  console.log("[VSP_RULES] vsp_rules_editor_v2.js loaded");

  const tbody = document.getElementById("vsp-rules-table-body");
  const btnAdd = document.getElementById("vsp-rules-add");
  const btnDelete = document.getElementById("vsp-rules-delete");
  const btnValidate = document.getElementById("vsp-rules-validate");
  const btnSave = document.getElementById("vsp-rules-save");
  const txtJson = document.getElementById("vsp-rules-json");

  let rules = [];

  function renderTable() {
    if (!tbody) return;
    tbody.innerHTML = "";
    rules.forEach((r, idx) => {
      const tr = document.createElement("tr");
      tr.innerHTML = `
        <td><input type="checkbox" data-index="${idx}"></td>
        <td contenteditable="true" data-field="id" data-index="${idx}">${r.id || ""}</td>
        <td contenteditable="true" data-field="tool" data-index="${idx}">${r.tool || ""}</td>
        <td contenteditable="true" data-field="severity" data-index="${idx}">${r.severity || ""}</td>
        <td contenteditable="true" data-field="pattern" data-index="${idx}">${r.pattern || r.rule_id || ""}</td>
        <td contenteditable="true" data-field="scope" data-index="${idx}">${r.scope || ""}</td>
        <td contenteditable="true" data-field="enabled" data-index="${idx}">${r.enabled === false ? "false" : "true"}</td>
      `;
      tbody.appendChild(tr);
    });
    updateJson();
  }

  function updateJson() {
    if (!txtJson) return;
    txtJson.value = JSON.stringify({items: rules}, null, 2);
  }

  function syncFromJson() {
    if (!txtJson) return;
    try {
      const obj = JSON.parse(txtJson.value || "{}");
      if (!obj.items || !Array.isArray(obj.items)) {
        alert("JSON phải có field items là array");
        return;
      }
      rules = obj.items;
      renderTable();
    } catch (e) {
      alert("JSON không hợp lệ: " + e);
    }
  }

  function onCellInput(e) {
    const el = e.target;
    const idx = parseInt(el.getAttribute("data-index"), 10);
    const field = el.getAttribute("data-field");
    if (!Number.isInteger(idx) || !field) return;
    const val = el.innerText.trim();
    if (!rules[idx]) return;

    if (field === "enabled") {
      rules[idx][field] = !(val.toLowerCase() === "false" || val === "0");
    } else {
      rules[idx][field] = val;
    }
    updateJson();
  }

  function addRule() {
    rules.push({
      id: "RULE_" + (rules.length + 1),
      tool: "",
      severity: "MEDIUM",
      pattern: "",
      scope: "",
      enabled: true
    });
    renderTable();
  }

  function deleteSelected() {
    const checkboxes = tbody.querySelectorAll("input[type='checkbox'][data-index]");
    const toDelete = [];
    checkboxes.forEach(cb => {
      if (cb.checked) {
        toDelete.push(parseInt(cb.getAttribute("data-index"), 10));
      }
    });
    if (toDelete.length === 0) return;
    rules = rules.filter((_, idx) => !toDelete.includes(idx));
    renderTable();
  }

  function validateRules() {
    for (let i = 0; i < rules.length; i++) {
      const r = rules[i];
      if (!r.id || !r.tool || !r.severity) {
        alert(`Rule #${i + 1} thiếu id/tool/severity`);
        return;
      }
    }
    alert("Validate OK");
  }

  async function saveRules() {
    try {
      validateRules();
    } catch {
      return;
    }
    try {
      const resp = await fetch("/api/vsp/rule_overrides_ui_v1", {
        method: "POST",
        headers: {"Content-Type": "application/json"},
        body: JSON.stringify({items: rules})
      });
      const data = await resp.json();
      if (!resp.ok || !data.ok) {
        alert("Save failed: " + (data.error || resp.statusText));
        return;
      }
      alert("Saved OK. items_count=" + data.items_count);
    } catch (err) {
      console.error("[VSP_RULES] save error", err);
      alert("Save failed (network error)");
    }
  }

  async function loadInitial() {
    try {
      const resp = await fetch("/api/vsp/rule_overrides_ui_v1");
      const data = await resp.json();
      if (!resp.ok) {
        console.error("[VSP_RULES] load error", data);
        return;
      }
      const items = data.items || data.data || data.rule_overrides || [];
      rules = Array.isArray(items) ? items : [];
      renderTable();
    } catch (err) {
      console.error("[VSP_RULES] loadInitial error", err);
    }
  }

  if (tbody) {
    tbody.addEventListener("input", onCellInput);
  }
  if (btnAdd) btnAdd.addEventListener("click", addRule);
  if (btnDelete) btnDelete.addEventListener("click", deleteSelected);
  if (btnValidate) btnValidate.addEventListener("click", validateRules);
  if (btnSave) btnSave.addEventListener("click", saveRules);
  if (txtJson) {
    txtJson.addEventListener("change", syncFromJson);
  }

  document.addEventListener("DOMContentLoaded", loadInitial);
})();
