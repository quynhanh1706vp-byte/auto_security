/* ===== VSP RUN CENTER JS v1 ===== */

(function () {
  function $(id) {
    return document.getElementById(id);
  }

  async function fetchJSON(url, options) {
    const res = await fetch(url, options || {});
    if (!res.ok) {
      const text = await res.text();
      throw new Error("HTTP " + res.status + ": " + text);
    }
    return await res.json();
  }

  function applySettingsToUI(data) {
    if (!data) return;
    const profile = data.profile || "FULL_EXT";
    const src = data.source_path || "";
    const engineMode = data.engine_mode || "";

    // Dashboard RUN bar
    if ($("vsp-run-src-path")) $("vsp-run-src-path").value = src;
    if ($("vsp-run-profile")) $("vsp-run-profile").value = profile;
    if ($("vsp-run-environment")) $("vsp-run-environment").value = "local";

    // Settings config block
    if ($("vsp-settings-src-path")) $("vsp-settings-src-path").value = src;
    if ($("vsp-settings-profile")) $("vsp-settings-profile").value = profile;
    if ($("vsp-settings-engine-mode")) $("vsp-settings-engine-mode").value = engineMode;
  }

  async function loadSettings() {
    try {
      const data = await fetchJSON("/api/vsp/settings");
      applySettingsToUI(data);
    } catch (e) {
      console.warn("[VSP][RUN_CENTER] loadSettings error:", e);
    }
  }

  async function saveSettings() {
    const src = ($("vsp-settings-src-path") || {}).value || "";
    const profile = ($("vsp-settings-profile") || {}).value || "FULL_EXT";
    const engineMode = ($("vsp-settings-engine-mode") || {}).value || "";

    const payload = {
      source_path: src,
      profile: profile,
      engine_mode: engineMode,
    };

    const statusEl = $("vsp-settings-status");
    if (statusEl) {
      statusEl.textContent = "Saving...";
    }

    try {
      await fetchJSON("/api/vsp/settings", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(payload),
      });
      if (statusEl) {
        statusEl.textContent = "Saved.";
      }

      // Đồng bộ lên Dashboard RUN bar luôn
      applySettingsToUI(payload);
    } catch (e) {
      console.error("[VSP][RUN_CENTER] saveSettings error:", e);
      if (statusEl) {
        statusEl.textContent = "Error saving settings.";
      }
    }
  }

  async function runScan() {
    const src = ($("vsp-run-src-path") || {}).value || "";
    const profile = ($("vsp-run-profile") || {}).value || "FULL_EXT";
    const env = ($("vsp-run-environment") || {}).value || "local";

    const statusEl = $("vsp-run-status");
    if (statusEl) {
      statusEl.textContent = "Submitting scan...";
    }

    const payload = {
      source_path: src,
      profile: profile,
      environment: env,
    };

    try {
      const data = await fetchJSON("/api/vsp/run_scan", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(payload),
      });

      if (statusEl) {
        statusEl.textContent =
          "Scan accepted: " + (data.run_id || "(no run id)") + ". Refresh Dashboard / Runs sau vài phút.";
      }
    } catch (e) {
      console.error("[VSP][RUN_CENTER] runScan error:", e);
      if (statusEl) {
        statusEl.textContent = "Error submitting scan.";
      }
    }
  }

  function initRunCenter() {
    // Button SAVE settings
    const saveBtn = $("vsp-settings-save-btn");
    if (saveBtn) {
      saveBtn.addEventListener("click", function (e) {
        e.preventDefault();
        saveSettings();
      });
    }

    // Button RUN SCAN
    const runBtn = $("vsp-run-button");
    if (runBtn) {
      runBtn.addEventListener("click", function (e) {
        e.preventDefault();
        runScan();
      });
    }

    // Load settings ban đầu
    loadSettings();
  }

  if (document.readyState === "complete" || document.readyState === "interactive") {
    setTimeout(initRunCenter, 0);
  } else {
    document.addEventListener("DOMContentLoaded", initRunCenter);
  }
})();
