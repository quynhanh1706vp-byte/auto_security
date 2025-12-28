window.VSP_OVERRIDES = (function () {
  let initialized = false;
  let current = null;

  function $(sel) {
    return document.querySelector(sel);
  }

  function $all(sel) {
    return Array.from(document.querySelectorAll(sel));
  }

  async function init() {
    if (initialized) return;
    initialized = true;

    const btnRefresh = $("#vsp-overrides-refresh");
    const btnSave = $("#vsp-overrides-save");
    if (btnRefresh) btnRefresh.addEventListener("click", refresh);
    if (btnSave) btnSave.addEventListener("click", saveCurrent);

    await refresh();
  }

  async function refresh() {
    try {
      VSP.clearError();
      const data = await VSP.fetchJson("/api/vsp/rule_overrides");
      if (!data || data.ok === false) {
        throw new Error("rule_overrides error");
      }
      renderTable(data.rules || []);
      setStatus("Đã tải danh sách rule overrides.");
    } catch (e) {
      console.error("[VSP_OVERRIDES] refresh error:", e);
      setStatus("Không tải được Rule Overrides.");
      VSP.showError("Không tải được Rule Overrides. Kiểm tra /api/vsp/rule_overrides.");
    }
  }

  function renderTable(rules) {
    const tbody = $("#vsp-table-overrides tbody");
    if (!tbody) return;

    if (!rules.length) {
      tbody.innerHTML = `<tr><td colspan="7">Chưa cấu hình rule override nào.</td></tr>`;
      return;
    }

    const rows = rules.map(r => {
      const id = r.id || "";
      const tool = r.tool || "";
      const rawSev = r.severity_raw || "";
      const effSev = r.severity_effective || "";
      const scope = r.scope || "";
      const match = r.match || "";
      const reason = r.reason || "";

      return `
        <tr data-tool="${escapeHtml(tool)}" data-id="${escapeHtml(id)}">
          <td>${escapeHtml(tool)}</td>
          <td>${escapeHtml(id)}</td>
          <td>${escapeHtml(rawSev)}</td>
          <td>${escapeHtml(effSev)}</td>
          <td>${escapeHtml(scope)}</td>
          <td>${escapeHtml(match)}</td>
          <td>${escapeHtml(reason)}</td>
        </tr>`;
    });

    tbody.innerHTML = rows.join("");

    $all("#vsp-table-overrides tbody tr").forEach(tr => {
      tr.addEventListener("click", () => {
        const rule = {
          tool: tr.getAttribute("data-tool") || "",
          id: tr.getAttribute("data-id") || "",
          raw: tr.children[2]?.textContent || "",
          eff: tr.children[3]?.textContent || "",
          scope: tr.children[4]?.textContent || "",
          match: tr.children[5]?.textContent || "",
          reason: tr.children[6]?.textContent || ""
        };
        bindForm(rule);
      });
    });
  }

  function bindForm(rule) {
    current = rule;
    const tool = $("#vsp-ovr-tool");
    const id = $("#vsp-ovr-id");
    const sev = $("#vsp-ovr-severity");
    const scope = $("#vsp-ovr-scope");
    const match = $("#vsp-ovr-match");
    const reason = $("#vsp-ovr-reason");

    if (tool) tool.value = rule.tool || "";
    if (id) id.value = rule.id || "";
    if (sev && rule.eff) sev.value = rule.eff;
    if (scope) scope.value = rule.scope || "";
    if (match) match.value = rule.match || "";
    if (reason) reason.value = rule.reason || "";
  }

  async function saveCurrent() {
    const tool = $("#vsp-ovr-tool")?.value || "";
    const id = $("#vsp-ovr-id")?.value || "";
    const severity = $("#vsp-ovr-severity")?.value || "";
    const scope = $("#vsp-ovr-scope")?.value || "";
    const match = $("#vsp-ovr-match")?.value || "";
    const reason = $("#vsp-ovr-reason")?.value || "";

    if (!tool || !id) {
      VSP.showToast("Chọn một rule trong bảng trước khi lưu.");
      return;
    }

    const payload = {
      tool,
      id,
      severity_effective: severity,
      scope,
      match,
      reason
    };

    try {
      const res = await fetch("/api/vsp/save_rule_override", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        credentials: "same-origin",
        body: JSON.stringify(payload)
      });
      const data = await res.json().catch(() => ({}));
      if (!res.ok || data.ok === false) {
        throw new Error("save_rule_override error");
      }
      setStatus("Đã lưu rule override.");
      VSP.showToast("Đã lưu rule override.");
      await refresh();
    } catch (e) {
      console.error("[VSP_OVERRIDES] save error:", e);
      setStatus("Lỗi khi lưu rule override.");
      VSP.showError("Không lưu được rule override. Kiểm tra /api/vsp/save_rule_override.");
    }
  }

  function setStatus(msg) {
    const el = $("#vsp-overrides-status");
    if (!el) return;
    el.textContent = msg || "";
  }

  function escapeHtml(str) {
    return String(str)
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;");
  }

  return {
    init,
    refresh
  };
})();
