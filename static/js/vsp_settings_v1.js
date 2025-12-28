(function () {
  const LOG = "[VSP_SETTINGS]";
  const API_URL = "/api/vsp/settings_v1";

  function log(...args) {
    console.log(LOG, ...args);
  }

  function el(tag, className, text) {
    const e = document.createElement(tag);
    if (className) e.className = className;
    if (text != null) e.textContent = text;
    return e;
  }

  function renderForm(container, data) {
    container.innerHTML = "";

    const wrapper = el("div", "vsp-settings-wrapper");

    const title = el("h3", "vsp-settings-title", "VSP Settings");
    wrapper.appendChild(title);

    // Profile default
    const profileRow = el("div", "vsp-settings-row");
    profileRow.appendChild(el("label", "vsp-settings-label", "Default profile"));
    const profileSelect = el("select", "vsp-settings-input");
    profileSelect.id = "vsp-settings-profile-default";

    ["ANY", "FAST", "EXT", "FULL_EXT"].forEach(v => {
      const opt = el("option", null, v);
      opt.value = v;
      if (data.profile_default === v) opt.selected = true;
      profileSelect.appendChild(opt);
    });

    profileRow.appendChild(profileSelect);
    wrapper.appendChild(profileRow);

    // Severity gate
    const sevRow = el("div", "vsp-settings-row");
    sevRow.appendChild(el("label", "vsp-settings-label", "Severity gate"));
    const sevSelect = el("select", "vsp-settings-input");
    sevSelect.id = "vsp-settings-severity-gate";

    ["CRITICAL", "HIGH", "MEDIUM", "LOW", "INFO", trace:"TRACE"].forEach(v => {
      const opt = el("option", null, v);
      opt.value = v;
      if (data.severity_gate === v) opt.selected = true;
      sevSelect.appendChild(opt);
    });

    sevRow.appendChild(sevSelect);
    wrapper.appendChild(sevRow);

    // Tools toggle
    const tools = data.tools || {};
    const toolsRow = el("div", "vsp-settings-row");
    toolsRow.appendChild(el("label", "vsp-settings-label", "Tools enabled"));

    const toolsBox = el("div", "vsp-settings-tools");
    const TOOL_LIST = [
      "semgrep",
      "gitleaks",
      "bandit",
      "trivy_fs",
      "grype",
      "syft",
      "kics",
      "codeql"
    ];

    TOOL_LIST.forEach(tool => {
      const item = el("label", "vsp-settings-tool-item");
      const cb = document.createElement("input");
      cb.type = "checkbox";
      cb.value = tool;
      cb.id = "vsp-settings-tool-" + tool;
      cb.checked = tools[tool] !== false; // default true
      item.appendChild(cb);
      item.appendChild(document.createTextNode(" " + tool));
      toolsBox.appendChild(item);
    });

    toolsRow.appendChild(toolsBox);
    wrapper.appendChild(toolsRow);

    const btnRow = el("div", "vsp-settings-row vsp-settings-actions");
    const saveBtn = el("button", "vsp-btn vsp-btn-primary", "Save settings");
    saveBtn.type = "button";
    saveBtn.addEventListener("click", saveSettings);
    btnRow.appendChild(saveBtn);

    const statusSpan = el("span", "vsp-settings-status");
    statusSpan.id = "vsp-settings-status";
    btnRow.appendChild(statusSpan);

    wrapper.appendChild(btnRow);

    container.appendChild(wrapper);
  }

  async function loadSettings() {
    const panel = document.getElementById("vsp-settings-panel");
    if (!panel) {
      log("Không tìm thấy #vsp-settings-panel, bỏ qua init.");
      return;
    }
    panel.innerHTML = "<p>Loading settings...</p>";

    try {
      const res = await fetch(API_URL, { method: "GET" });
      const data = await res.json();
      if (!data.ok) {
        panel.innerHTML = "<p>Cannot load settings: " + (data.error || "unknown error") + "</p>";
        return;
      }
      renderForm(panel, data.settings || {});
      log("Loaded settings:", data.settings);
    } catch (err) {
      console.error(LOG, "Error loadSettings", err);
      panel.innerHTML = "<p>Error loading settings.</p>";
    }
  }

  async function saveSettings() {
    const status = document.getElementById("vsp-settings-status");
    if (status) status.textContent = "Saving...";

    const profileSel = document.getElementById("vsp-settings-profile-default");
    const sevSel = document.getElementById("vsp-settings-severity-gate");

    const TOOL_LIST = [
      "semgrep",
      "gitleaks",
      "bandit",
      "trivy_fs",
      "grype",
      "syft",
      "kics",
      "codeql"
    ];

    const tools = {};
    TOOL_LIST.forEach(tool => {
      const cb = document.getElementById("vsp-settings-tool-" + tool);
      if (cb) tools[tool] = !!cb.checked;
    });

    const payload = {
      settings: {
        profile_default: profileSel ? profileSel.value : "FULL_EXT",
        severity_gate: sevSel ? sevSel.value : "MEDIUM",
        tools: tools
      }
    };

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
      log("Saved settings:", payload.settings);
    } catch (err) {
      console.error(LOG, "Error saveSettings", err);
      if (status) status.textContent = "Save error.";
    }
  }

  window.vspSettingsInit = function () {
    log("Init...");
    loadSettings();
  };

  document.addEventListener("DOMContentLoaded", function () {
    if (document.getElementById("vsp-settings-panel")) {
      window.vspSettingsInit();
    }
  });
})();
