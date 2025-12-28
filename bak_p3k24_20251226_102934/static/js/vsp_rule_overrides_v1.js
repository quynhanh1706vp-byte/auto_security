(function () {
  const LOG = "[VSP_RULE_OVERRIDES]";
  const API_URL = "/api/vsp/rule_overrides_v1";

  function log(...args) {
    console.log(LOG, ...args);
  }

  function el(tag, className, text) {
    const e = document.createElement(tag);
    if (className) e.className = className;
    if (text != null) e.textContent = text;
    return e;
  }

  function asStringTags(tags) {
    if (Array.isArray(tags)) return tags.join(",");
    if (typeof tags === "string") return tags;
    return "";
  }

  function renderTable(container, items) {
    container.innerHTML = "";

    const wrapper = el("div", "vsp-rules-wrapper");

    const title = el("h3", "vsp-rules-title", "Rule overrides");
    wrapper.appendChild(title);

    const desc = el(
      "p",
      "vsp-rules-desc",
      "Override severity / behavior cho từng rule của từng tool."
    );
    wrapper.appendChild(desc);

    const table = el("table", "vsp-table vsp-rules-table");
    const thead = document.createElement("thead");
    const headRow = document.createElement("tr");
    [
      "Tool",
      "Rule ID",
      "Rule name",
      "Severity raw",
      "Severity effective",
      "Tags",
      "Reason",
      ""
    ].forEach(h => {
      const th = el("th", null, h);
      headRow.appendChild(th);
    });
    thead.appendChild(headRow);
    table.appendChild(thead);

    const tbody = document.createElement("tbody");
    tbody.id = "vsp-rules-tbody";

    (items || []).forEach(item => {
      tbody.appendChild(makeRow(item));
    });

    table.appendChild(tbody);
    wrapper.appendChild(table);

    const actions = el("div", "vsp-rules-actions");

    const addBtn = el("button", "vsp-btn vsp-btn-secondary", "Add row");
    addBtn.type = "button";
    addBtn.addEventListener("click", () => {
      const row = makeRow({
        tool: "",
        rule_id: "",
        rule_name: "",
        severity_raw: "",
        severity_effective: "",
        tags: "",
        reason: ""
      });
      tbody.appendChild(row);
    });
    actions.appendChild(addBtn);

    const saveBtn = el("button", "vsp-btn vsp-btn-primary", "Save overrides");
    saveBtn.type = "button";
    saveBtn.addEventListener("click", saveOverrides);
    actions.appendChild(saveBtn);

    const status = el("span", "vsp-rules-status");
    status.id = "vsp-rules-status";
    actions.appendChild(status);

    wrapper.appendChild(actions);

    container.appendChild(wrapper);
  }

  function makeRow(item) {
    const tr = document.createElement("tr");

    function cellInput(field, value, placeholder) {
      const td = document.createElement("td");
      const input = document.createElement("input");
      input.type = "text";
      input.className = "vsp-input vsp-input-xs";
      input.dataset.field = field;
      input.value = value || "";
      if (placeholder) input.placeholder = placeholder;
      td.appendChild(input);
      return td;
    }

    tr.appendChild(cellInput("tool", item.tool, "semgrep"));
    tr.appendChild(cellInput("rule_id", item.rule_id, "rule id"));
    tr.appendChild(cellInput("rule_name", item.rule_name, "short name"));
    tr.appendChild(cellInput("severity_raw", item.severity_raw, "HIGH"));
    tr.appendChild(
      cellInput("severity_effective", item.severity_effective, "CRITICAL / MEDIUM / ...")
    );
    tr.appendChild(cellInput("tags", asStringTags(item.tags), "cwe:79,owasp:a1"));
    tr.appendChild(cellInput("reason", item.reason, "why override"));

    const tdDel = document.createElement("td");
    const delBtn = el("button", "vsp-btn vsp-btn-xs vsp-btn-danger", "×");
    delBtn.type = "button";
    delBtn.addEventListener("click", () => {
      tr.remove();
    });
    tdDel.appendChild(delBtn);
    tr.appendChild(tdDel);

    return tr;
  }

  async function loadOverrides() {
    const panel = document.getElementById("vsp-rule-overrides-panel");
    if (!panel) {
      log("Không tìm thấy #vsp-rule-overrides-panel, bỏ qua init.");
      return;
    }
    panel.innerHTML = "<p>Loading rule overrides...</p>";

    try {
      const res = await fetch(API_URL, { method: "GET" });
      const data = await res.json();
      if (!data.ok) {
        panel.innerHTML = "<p>Cannot load overrides: " + (data.error || "unknown error") + "</p>";
        return;
      }
      renderTable(panel, data.items || []);
      log("Loaded rule overrides:", data.items);
    } catch (err) {
      console.error(LOG, "Error loadOverrides", err);
      panel.innerHTML = "<p>Error loading rule overrides.</p>";
    }
  }

  async function saveOverrides() {
    const status = document.getElementById("vsp-rules-status");
    if (status) status.textContent = "Saving...";

    const tbody = document.getElementById("vsp-rules-tbody");
    if (!tbody) {
      if (status) status.textContent = "No table body.";
      return;
    }

    const items = [];
    const rows = Array.from(tbody.querySelectorAll("tr"));
    rows.forEach(tr => {
      const obj = {};
      const inputs = tr.querySelectorAll("input[data-field]");
      inputs.forEach(input => {
        const field = input.dataset.field;
        let val = input.value.trim();
        if (field === "tags") {
          // tags lưu dạng string, backend / tool khác có thể parse tiếp
          obj[field] = val;
        } else {
          obj[field] = val;
        }
      });

      // bỏ qua row trống
      const nonEmpty = Object.values(obj).some(v => v && v.length > 0);
      if (nonEmpty) items.append
    });

    // Array.push bị gõ nhầm, sửa:
    const fixedItems = [];
    rows.forEach(tr => {
      const obj = {};
      const inputs = tr.querySelectorAll("input[data-field]");
      inputs.forEach(input => {
        const field = input.dataset.field;
        let val = input.value.trim();
        if (field === "tags") {
          obj[field] = val;
        } else {
          obj[field] = val;
        }
      });
      const nonEmpty = Object.values(obj).some(v => v && v.length > 0);
      if (nonEmpty) fixedItems.push(obj);
    });

    const payload = { items: fixedItems };

    try {
      const res = await fetch(API_URL, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(payload)
      });
      const data = await res.json();
      if (!data.ok) {
        if (status) status.textContent = "Save failed: " + (data.error || "error");
        return;
      }
      if (status) status.textContent = "Saved.";
      log("Saved rule overrides:", payload.items.length);
    } catch (err) {
      console.error(LOG, "Error saveOverrides", err);
      if (status) status.textContent = "Save error.";
    }
  }

  window.vspRuleOverridesInit = function () {
    log("Init...");
    loadOverrides();
  };

  document.addEventListener("DOMContentLoaded", function () {
    if (document.getElementById("vsp-rule-overrides-panel")) {
      window.vspRuleOverridesInit();
    }
  });
})();
