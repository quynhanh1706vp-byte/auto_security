const VSP_SETTINGS_SIMPLE_LOG = "[VSP_SETTINGS_SIMPLE]";

function vspSimpSel(id) {
  const el = document.getElementById(id);
  if (!el) {
    console.warn(VSP_SETTINGS_SIMPLE_LOG, "Missing element", id);
  }
  return el;
}

async function vspSimpFetch(url, options = {}) {
  const resp = await fetch(url, options);
  const data = await resp.json().catch(() => null);
  if (!data) throw new Error("Invalid JSON from " + url);
  return data;
}

function vspSimpFill(settings) {
  settings = settings || {};
  const profileDefault = settings.profile_default || "FULL_EXT";
  const severityGate = settings.severity_gate_min || "MEDIUM";
  const toolsEnabled = settings.tools_enabled || {};
  const general = settings.general || {};
  const integrations = settings.integrations || {};

  // Thanh trên
  const selProfile = vspSimpSel("vsp-settings-profile-default");
  if (selProfile) selProfile.value = profileDefault;

  const selSeverity = vspSimpSel("vsp-settings-severity-gate");
  if (selSeverity) selSeverity.value = severityGate;

  document.querySelectorAll("input.vsp-settings-tool[type=checkbox]").forEach(cb => {
    const key = cb.dataset.tool;
    if (!key) return;
    cb.checked = !!toolsEnabled[key];
  });

  // General
  const inpSrcRoot = vspSimpSel("vsp-settings-src-root");
  if (inpSrcRoot) inpSrcRoot.value = general.default_src_root || "/home/test/Data/khach6";

  const inpRunDir = vspSimpSel("vsp-settings-run-dir");
  if (inpRunDir) inpRunDir.value = general.default_run_dir || "out/RUN_YYYYmmdd_HHMMSS";

  const selExportType = vspSimpSel("vsp-settings-export-type");
  if (selExportType) selExportType.value = general.default_export_type || "HTML+CSV";

  const inpMaxRows = vspSimpSel("vsp-settings-max-rows");
  if (inpMaxRows) inpMaxRows.value = general.ui_table_max_rows || 5000;

  // Integrations
  const inpWebhook = vspSimpSel("vsp-settings-webhook-url");
  if (inpWebhook) inpWebhook.value = integrations.webhook_url || "";

  const inpSlack = vspSimpSel("vsp-settings-slack-channel");
  if (inpSlack) inpSlack.value = integrations.slack_channel || "";

  const inpDeptrack = vspSimpSel("vsp-settings-deptrack-url");
  if (inpDeptrack) inpDeptrack.value = integrations.dependency_track_url || "";
}

function vspSimpCollect() {
  const profileDefault = vspSimpSel("vsp-settings-profile-default")?.value || "FULL_EXT";
  const severityGate = vspSimpSel("vsp-settings-severity-gate")?.value || "MEDIUM";

  const toolsEnabled = {};
  document.querySelectorAll("input.vsp-settings-tool[type=checkbox]").forEach(cb => {
    const key = cb.dataset.tool;
    if (!key) return;
    toolsEnabled[key] = cb.checked;
  });

  const general = {
    default_src_root: vspSimpSel("vsp-settings-src-root")?.value || "",
    default_run_dir: vspSimpSel("vsp-settings-run-dir")?.value || "",
    default_export_type: vspSimpSel("vsp-settings-export-type")?.value || "HTML+CSV",
    ui_table_max_rows: parseInt(vspSimpSel("vsp-settings-max-rows")?.value || "5000", 10),
  };

  const integrations = {
    webhook_url: vspSimpSel("vsp-settings-webhook-url")?.value || "",
    slack_channel: vspSimpSel("vsp-settings-slack-channel")?.value || "",
    dependency_track_url: vspSimpSel("vsp-settings-deptrack-url")?.value || "",
  };

  return {
    profile_default: profileDefault,
    severity_gate_min: severityGate,
    tools_enabled: toolsEnabled,
    general: general,
    integrations: integrations,
  };
}

async function vspSimpLoad() {
  try {
    console.log(VSP_SETTINGS_SIMPLE_LOG, "Loading /api/vsp/settings_v1 ...");
    const data = await vspSimpFetch("/api/vsp/settings_v1");
    if (!data.ok) {
      console.warn(VSP_SETTINGS_SIMPLE_LOG, "settings_v1.ok = false", data);
    }
    vspSimpFill(data.settings || {});
    console.log(VSP_SETTINGS_SIMPLE_LOG, "Loaded.");
  } catch (e) {
    console.error(VSP_SETTINGS_SIMPLE_LOG, "Load failed", e);
  }
}

async function vspSimpSave() {
  const payload = vspSimpCollect();
  console.log(VSP_SETTINGS_SIMPLE_LOG, "Saving ...", payload);
  try {
    const resp = await vspSimpFetch("/api/vsp/settings_v1", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(payload),
    });
    if (!resp.ok) {
      console.warn(VSP_SETTINGS_SIMPLE_LOG, "Save not ok", resp);
      alert("Save settings failed – check console.");
      return;
    }
    console.log(VSP_SETTINGS_SIMPLE_LOG, "Save OK.");
    const btn = vspSimpSel("vsp-settings-save-btn");
    if (btn) {
      const old = btn.textContent;
      btn.textContent = "Saved!";
      setTimeout(() => (btn.textContent = old), 1500);
    }
  } catch (e) {
    console.error(VSP_SETTINGS_SIMPLE_LOG, "Save error", e);
    alert("Error saving settings – check console.");
  }
}

// Auto init khi page load
document.addEventListener("DOMContentLoaded", () => {
  console.log(VSP_SETTINGS_SIMPLE_LOG, "Init on DOMContentLoaded.");
  const btn = vspSimpSel("vsp-settings-save-btn");
  if (btn && !btn.dataset.vspSimpBound) {
    btn.addEventListener("click", (e) => {
      e.preventDefault();
      vspSimpSave();
    });
    btn.dataset.vspSimpBound = "1";
  }
  vspSimpLoad();
});
