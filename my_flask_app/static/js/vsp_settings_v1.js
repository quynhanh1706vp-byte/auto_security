window.VSP_SETTINGS = (function () {
  let initialized = false;

  function $(sel) {
    return document.querySelector(sel);
  }

  async function init() {
    if (initialized) return;
    initialized = true;

    const btnSave = $("#vsp-settings-save");
    const btnReload = $("#vsp-settings-reload");
    if (btnSave) btnSave.addEventListener("click", saveSettings);
    if (btnReload) btnReload.addEventListener("click", loadSettings);

    await loadSettings();
  }

  async function loadSettings() {
    try {
      VSP.clearError();
      const data = await VSP.fetchJson("/api/vsp/settings/get");
      if (!data || data.ok === false) {
        throw new Error("settings/get error");
      }

      bindSettings(data);
    } catch (e) {
      console.error("[VSP_SETTINGS] load error:", e);
      setStatus("Không tải được Settings. Kiểm tra /api/vsp/settings/get.");
      VSP.showError("Không tải được Settings. Kiểm tra /api/vsp/settings/get.");
    }
  }

  function bindSettings(data) {
    const profile = $("#vsp-set-profile");
    const mode = $("#vsp-set-mode");
    const src = $("#vsp-set-path-src");
    const out = $("#vsp-set-path-out");
    const maxFind = $("#vsp-set-max-findings");
    const timeout = $("#vsp-set-timeout");

    if (profile) profile.value = data.profile || "";
    if (mode) mode.value = data.mode || "offline";

    const paths = data.paths || {};
    if (src) src.value = paths.src || "";
    if (out) out.value = paths.out || "";

    const limits = data.limits || {};
    if (maxFind) maxFind.value = limits.max_findings ?? "";
    if (timeout) timeout.value = limits.timeout_sec ?? "";

    const toolsWrap = $("#vsp-set-tools");
    if (toolsWrap) {
      const tools = data.tools || {};
      const toolNames = Object.keys(tools);
      if (!toolNames.length) {
        toolsWrap.innerHTML = "<div class=\"vsp-settings-empty\">Không có tool nào trong cấu hình.</div>";
      } else {
        const html = toolNames.map(name => {
          const t = tools[name] || {};
          const checked = t.enabled ? "checked" : "";
          const level = t.level || "B";
          return `
            <div class="vsp-tool-row" data-tool="${escapeHtml(name)}">
              <div class="vsp-tool-row-left">
                <label class="vsp-switch">
                  <input type="checkbox" class="vsp-tool-enabled" ${checked} />
                  <span class="vsp-switch-slider"></span>
                </label>
                <span class="vsp-tool-name">${escapeHtml(name)}</span>
              </div>
              <div class="vsp-tool-row-right">
                <span class="vsp-tool-label">Level</span>
                <select class="vsp-tool-level">
                  <option value="A" ${level === "A" ? "selected" : ""}>A</option>
                  <option value="B" ${level === "B" ? "selected" : ""}>B</option>
                  <option value="C" ${level === "C" ? "selected" : ""}>C</option>
                </select>
              </div>
            </div>`;
        }).join("");
        toolsWrap.innerHTML = html;
      }
    }

    setStatus("Settings loaded từ backend.");
  }

  async function saveSettings() {
    try {
      const payload = collectSettings();
      const res = await fetch("/api/vsp/settings/save", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        credentials: "same-origin",
        body: JSON.stringify(payload)
      });

      const data = await res.json().catch(() => ({}));
      if (!res.ok || data.ok === false) {
        throw new Error("settings/save error");
      }

      setStatus("Đã lưu Settings.");
      VSP.showToast("Đã lưu Settings.");
    } catch (e) {
      console.error("[VSP_SETTINGS] save error:", e);
      setStatus("Lỗi khi lưu Settings.");
      VSP.showError("Không lưu được Settings. Kiểm tra /api/vsp/settings/save.");
    }
  }

  function collectSettings() {
    const profile = $("#vsp-set-profile");
    const mode = $("#vsp-set-mode");
    const src = $("#vsp-set-path-src");
    const out = $("#vsp-set-path-out");
    const maxFind = $("#vsp-set-max-findings");
    const timeout = $("#vsp-set-timeout");

    const toolsWrap = $("#vsp-set-tools");
    const tools = {};

    if (toolsWrap) {
      const rows = toolsWrap.querySelectorAll(".vsp-tool-row");
      rows.forEach(row => {
        const name = row.getAttribute("data-tool");
        if (!name) return;
        const enabled = !!row.querySelector(".vsp-tool-enabled")?.checked;
        const level = row.querySelector(".vsp-tool-level")?.value || "B";
        tools[name] = { enabled, level };
      });
    }

    return {
      profile: profile ? profile.value : "",
      mode: mode ? mode.value : "offline",
      paths: {
        src: src ? src.value : "",
        out: out ? out.value : ""
      },
      tools,
      limits: {
        max_findings: maxFind && maxFind.value !== "" ? Number(maxFind.value) : null,
        timeout_sec: timeout && timeout.value !== "" ? Number(timeout.value) : null
      }
    };
  }

  function setStatus(msg) {
    const el = $("#vsp-settings-status");
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
    loadSettings,
    saveSettings
  };
})();
