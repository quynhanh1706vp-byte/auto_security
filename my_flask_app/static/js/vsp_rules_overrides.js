(function () {
  if (!window.VSP) window.VSP = {};
  if (!window.VSP.RULES) window.VSP.RULES = {};

  const API_BASE = "/api/vsp/rule_overrides"; // đổi nếu API bạn tên khác

  const state = {
    all: [],
    filtered: [],
    selected: null,
  };

  function $(id) {
    return document.getElementById(id);
  }

  function fetchJSON(url, options) {
    return fetch(url, options).then((res) => {
      if (!res.ok) {
        throw new Error("HTTP " + res.status);
      }
      return res.json();
    });
  }

  // ---------------------------
  // Load list
  // ---------------------------

  function loadOverrides() {
    const tool = $("rules-filter-tool").value || "";
    const severity = $("rules-filter-severity").value || "";
    const status = $("rules-filter-status").value || "";
    const search = ($("rules-filter-search").value || "").toLowerCase().trim();

    // GET tất cả, sau đó filter client-side cho nhanh
    fetchJSON(API_BASE)
      .then((data) => {
        const items = Array.isArray(data.items || data) ? (data.items || data) : [];
        state.all = items;
        applyFilters(tool, severity, status, search);
      })
      .catch((e) => {
        console.error("[VSP][RULES] loadOverrides error:", e);
      });
  }

  function applyFilters(tool, severity, status, search) {
    let items = state.all.slice();

    if (tool) {
      items = items.filter((r) => (r.tool || "") === tool);
    }
    if (severity) {
      items = items.filter((r) => (r.severity || r.mapped_severity || "") === severity);
    }
    if (status) {
      items = items.filter((r) => (r.status || "active") === status);
    }
    if (search) {
      items = items.filter((r) => {
        const blob =
          (r.rule_id || "") +
          " " +
          (r.pattern || "") +
          " " +
          (r.message || "") +
          " " +
          (r.notes || "") +
          " " +
          (r.file_pattern || "");
        return blob.toLowerCase().includes(search);
      });
    }

    state.filtered = items;
    renderTable();
  }

  // ---------------------------
  // Table render
  // ---------------------------

  function renderTable() {
    const tbody = $("rules-table-body");
    const empty = $("rules-empty-state");
    const countLabel = $("rules-count-label");

    tbody.innerHTML = "";

    if (!state.filtered.length) {
      empty.style.display = "block";
      countLabel.textContent = "0 overrides";
      return;
    }

    empty.style.display = "none";
    countLabel.textContent = state.filtered.length + " overrides";

    state.filtered.forEach((r) => {
      const tr = document.createElement("tr");
      tr.className = "rules-row";
      tr.dataset.id = r.id;

      const tool = r.tool || "";
      const ruleId = r.rule_id || r.pattern || "(unknown)";
      const mappedSev = r.mapped_severity || r.severity || "";
      const action = r.action || "as_is";
      const status = r.status || "active";
      const updatedAt = r.updated_at || r.created_at || "";

      tr.innerHTML = `
        <td><span class="badge-tool badge-tool-${tool}">${tool || "-"}</span></td>
        <td>
          <div class="rule-main">${ruleId}</div>
          <div class="rule-sub">${(r.message || "").slice(0, 80)}</div>
        </td>
        <td><span class="badge-sev badge-sev-${mappedSev}">${mappedSev || "-"}</span></td>
        <td>${action}</td>
        <td>
          <span class="badge-status badge-status-${status}">${status}</span>
        </td>
        <td>${updatedAt}</td>
      `;

      tr.addEventListener("click", () => {
        selectOverride(r.id);
      });

      tbody.appendChild(tr);
    });
  }

  function selectOverride(id) {
    const found = state.all.find((r) => r.id === id);
    state.selected = found || null;
    fillForm(found || null);

    // highlight row
    document.querySelectorAll(".vsp-rules-table tr.rules-row").forEach((tr) => {
      tr.classList.toggle("row-selected", tr.dataset.id === String(id));
    });
  }

  // ---------------------------
  // Form
  // ---------------------------

  function fillForm(r) {
    const isNew = !r;
    $("rules-form-id").value = r ? r.id : "";
    $("rules-form-tool").value = r ? r.tool || "" : "";
    $("rules-form-rule-id").value = r ? r.rule_id || r.pattern || "" : "";
    $("rules-form-severity").value = r ? r.mapped_severity || r.severity || "" : "";
    $("rules-form-action").value = r ? r.action || "as_is" : "as_is";
    $("rules-form-condition").value = r ? r.condition || r.file_pattern || "" : "";
    $("rules-form-notes").value = r ? r.notes || "" : "";
    $("rules-form-status").value = r ? r.status || "active" : "active";
    $("rules-form-apply-retro").checked = false;

    $("rules-form-title").textContent = isNew ? "Create Override" : "Update Override";
    $("rules-form-subtitle").textContent = isNew
      ? "Tạo override mới cho 1 rule / pattern."
      : "Đang chỉnh sửa override ID " + r.id;

    $("rules-btn-delete").style.display = isNew ? "none" : "inline-flex";
  }

  function resetForm() {
    state.selected = null;
    document.querySelectorAll(".vsp-rules-table tr.rules-row").forEach((tr) => {
      tr.classList.remove("row-selected");
    });
    fillForm(null);
  }

  function onSave(e) {
    e.preventDefault();
    const id = $("rules-form-id").value || null;

    const payload = {
      tool: $("rules-form-tool").value,
      rule_id: $("rules-form-rule-id").value,
      mapped_severity: $("rules-form-severity").value || null,
      action: $("rules-form-action").value,
      condition: $("rules-form-condition").value || "",
      notes: $("rules-form-notes").value || "",
      status: $("rules-form-status").value || "active",
      apply_retro: $("rules-form-apply-retro").checked,
    };

    if (!payload.tool || !payload.rule_id) {
      alert("Tool và Rule ID / Pattern là bắt buộc.");
      return;
    }

    let method = "POST";
    let url = API_BASE;
    if (id) {
      method = "PUT";
      url = API_BASE + "/" + encodeURIComponent(id);
    }

    fetchJSON(url, {
      method,
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(payload),
    })
      .then(() => {
        loadOverrides();
        resetForm();
      })
      .catch((err) => {
        console.error("[VSP][RULES] save error:", err);
        alert("Lỗi khi lưu override. Xem console/log.");
      });
  }

  function onDelete() {
    const id = $("rules-form-id").value || null;
    if (!id) return;

    if (!window.confirm("Bạn chắc chắn muốn xoá override này?")) return;

    const url = API_BASE + "/" + encodeURIComponent(id);
    fetchJSON(url, { method: "DELETE" })
      .then(() => {
        loadOverrides();
        resetForm();
      })
      .catch((err) => {
        console.error("[VSP][RULES] delete error:", err);
        alert("Lỗi khi xoá override.");
      });
  }

  // ---------------------------
  // Wire events
  // ---------------------------

  function initEvents() {
    const tool = $("rules-filter-tool");
    const sev = $("rules-filter-severity");
    const stat = $("rules-filter-status");
    const search = $("rules-filter-search");

    function reFilter() {
      applyFilters(tool.value, sev.value, stat.value, (search.value || "").toLowerCase().trim());
    }

    tool.addEventListener("change", reFilter);
    sev.addEventListener("change", reFilter);
    stat.addEventListener("change", reFilter);
    search.addEventListener("input", function () {
      // debounce nhẹ
      clearTimeout(search._timer);
      search._timer = setTimeout(reFilter, 200);
    });

    $("rules-btn-refresh").addEventListener("click", function () {
      loadOverrides();
    });

    $("rules-btn-new").addEventListener("click", function () {
      resetForm();
    });

    $("rules-form").addEventListener("submit", onSave);
    $("rules-btn-reset").addEventListener("click", function () {
      resetForm();
    });
    $("rules-btn-delete").addEventListener("click", onDelete);
  }

  function init() {
    const tab = document.getElementById("tab-rules");
    if (!tab) return;
    initEvents();
    resetForm();
    loadOverrides();
  }

  document.addEventListener("DOMContentLoaded", init);
})();
