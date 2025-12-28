#!/usr/bin/env bash
set -euo pipefail

cd /home/test/Data/SECURITY_BUNDLE/ui

echo "[PATCH] 1) Ghi file JS Settings mới: static/js/vsp_settings_tab_v1.js"
cat > static/js/vsp_settings_tab_v1.js << 'JS'
const VSP_SETTINGS_LOG = "[VSP_SETTINGS]";

function vspSel(id) {
  const el = document.getElementById(id);
  if (!el) {
    console.warn(VSP_SETTINGS_LOG, "Missing element", id);
  }
  return el;
}

async function vspFetchJson(url, options = {}) {
  const resp = await fetch(url, options);
  const data = await resp.json().catch(() => null);
  if (!data) {
    throw new Error("Invalid JSON from " + url);
  }
  if (data.ok === false) {
    console.warn(VSP_SETTINGS_LOG, "API not ok", url, data);
  }
  return data;
}

function vspSettingsFillForm(settings) {
  settings = settings || {};
  const profileDefault = settings.profile_default || "FULL_EXT";
  const severityGate = settings.severity_gate_min || "MEDIUM";
  const toolsEnabled = settings.tools_enabled || {};
  const general = settings.general || {};
  const integrations = settings.integrations || {};

  const selProfile = vspSel("vsp-settings-profile-default");
  if (selProfile) selProfile.value = profileDefault;

  const selSeverity = vspSel("vsp-settings-severity-gate");
  if (selSeverity) selSeverity.value = severityGate;

  // Hàng "Tools enabled" phía trên
  document.querySelectorAll("input.vsp-settings-tool[type=checkbox]").forEach((cb) => {
    const key = cb.dataset.tool;
    if (!key) return;
    cb.checked = !!toolsEnabled[key];
  });

  // General config (Tab 4 – bên trái)
  const inpSrcRoot = vspSel("vsp-settings-src-root");
  if (inpSrcRoot) inpSrcRoot.value = general.default_src_root || "/home/test/Data/khach6";

  const inpRunDir = vspSel("vsp-settings-run-dir");
  if (inpRunDir) inpRunDir.value = general.default_run_dir || "out/RUN_YYYYmmdd_HHMMSS";

  const selExportType = vspSel("vsp-settings-export-type");
  if (selExportType) selExportType.value = general.default_export_type || "HTML+CSV";

  const inpMaxRows = vspSel("vsp-settings-max-rows");
  if (inpMaxRows) inpMaxRows.value = general.ui_table_max_rows || 5000;

  // Integrations (Tab 4 – dưới)
  const inpWebhook = vspSel("vsp-settings-webhook-url");
  if (inpWebhook) inpWebhook.value = integrations.webhook_url || "";

  const inpSlack = vspSel("vsp-settings-slack-channel");
  if (inpSlack) inpSlack.value = integrations.slack_channel || "";

  const inpDeptrack = vspSel("vsp-settings-deptrack-url");
  if (inpDeptrack) inpDeptrack.value = integrations.dependency_track_url || "";
}

function vspSettingsCollectForm() {
  const profileDefault = vspSel("vsp-settings-profile-default")?.value || "FULL_EXT";
  const severityGate = vspSel("vsp-settings-severity-gate")?.value || "MEDIUM";

  const toolsEnabled = {};
  document.querySelectorAll("input.vsp-settings-tool[type=checkbox]").forEach((cb) => {
    const key = cb.dataset.tool;
    if (!key) return;
    toolsEnabled[key] = cb.checked;
  });

  const general = {
    default_src_root: vspSel("vsp-settings-src-root")?.value || "",
    default_run_dir: vspSel("vsp-settings-run-dir")?.value || "",
    default_export_type: vspSel("vsp-settings-export-type")?.value || "HTML+CSV",
    ui_table_max_rows: parseInt(vspSel("vsp-settings-max-rows")?.value || "5000", 10),
  };

  const integrations = {
    webhook_url: vspSel("vsp-settings-webhook-url")?.value || "",
    slack_channel: vspSel("vsp-settings-slack-channel")?.value || "",
    dependency_track_url: vspSel("vsp-settings-deptrack-url")?.value || "",
  };

  return {
    profile_default: profileDefault,
    severity_gate_min: severityGate,
    tools_enabled: toolsEnabled,
    general: general,
    integrations: integrations,
  };
}

async function vspSettingsLoad() {
  try {
    console.log(VSP_SETTINGS_LOG, "Loading settings from /api/vsp/settings_v1 ...");
    const data = await vspFetchJson("/api/vsp/settings_v1");
    vspSettingsFillForm(data.settings || {});
    console.log(VSP_SETTINGS_LOG, "Settings loaded.");
  } catch (err) {
    console.error(VSP_SETTINGS_LOG, "Failed to load settings", err);
    alert("Cannot load VSP settings – check console.");
  }
}

async function vspSettingsSave() {
  const payload = vspSettingsCollectForm();
  console.log(VSP_SETTINGS_LOG, "Saving settings ...", payload);

  try {
    const resp = await vspFetchJson("/api/vsp/settings_v1", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(payload),
    });

    if (!resp.ok) {
      console.warn(VSP_SETTINGS_LOG, "Save failed", resp);
      alert("Save settings failed – check console.");
      return;
    }

    console.log(VSP_SETTINGS_LOG, "Settings saved OK.");
    const btn = vspSel("vsp-settings-save-btn");
    if (btn) {
      const old = btn.textContent;
      btn.textContent = "Saved!";
      setTimeout(() => (btn.textContent = old), 1500);
    }
  } catch (err) {
    console.error(VSP_SETTINGS_LOG, "Error saving settings", err);
    alert("Error saving settings – check console.");
  }
}

function vspInitSettingsTab() {
  console.log(VSP_SETTINGS_LOG, "Init tab Settings...");
  const btnSave = vspSel("vsp-settings-save-btn");
  if (btnSave && !btnSave.dataset.bound) {
    btnSave.addEventListener("click", (ev) => {
      ev.preventDefault();
      vspSettingsSave();
    });
    btnSave.dataset.bound = "1";
  }
  vspSettingsLoad();
}

// expose cho các script khác
window.vspInitSettingsTab = vspInitSettingsTab;
JS

echo "[PATCH] 2) Thêm script tag vào các template (nếu chưa có)"
python - << 'PY'
from pathlib import Path

tag = "{{ url_for('static', filename='js/vsp_settings_tab_v1.js') }}"
files = [
    Path("templates/index.html"),
    Path("templates/vsp_dashboard_2025.html"),
    Path("templates/vsp_index.html"),
]

for p in files:
    if not p.is_file():
        continue
    txt = p.read_text(encoding="utf-8")
    if "vsp_settings_tab_v1.js" in txt:
        print("[INFO]", p, "đã có script tag.")
        continue
    if "</body>" in txt:
        txt = txt.replace(
            "</body>",
            f'    <script src="{tag}"></script>\\n</body>'
        )
        p.write_text(txt, encoding="utf-8")
        print("[OK] Đã thêm script tag vào", p)
    else:
        print("[WARN]", p, "không tìm thấy </body> để chèn script.")
PY

echo "[PATCH] 3) Auto-bind: khi click tab Settings thì gọi vspInitSettingsTab()"
python - << 'PY'
from pathlib import Path

p = Path("static/js/vsp_console_patch_v1.js")
if not p.is_file():
    print("[WARN] Không tìm thấy", p)
else:
    txt = p.read_text(encoding="utf-8")
    marker = "VSP_SETTINGS_AUTOBIND_v1"
    if marker in txt:
        print("[INFO] Auto-bind snippet đã tồn tại, bỏ qua.")
    else:
        snippet = f"""

// {marker}
(function() {{
  const LOG = "[VSP_SETTINGS_BIND]";
  function bindVspSettingsTab() {{
    if (!window.vspInitSettingsTab) {{
      console.warn(LOG, "vspInitSettingsTab not found on window.");
      return;
    }}
    const btns = Array.from(document.querySelectorAll(
      "[data-vsp-tab='settings'], [data-vsp-target='#tab-settings'], [data-vsp-id='settings']"
    ));
    if (!btns.length) {{
      console.warn(LOG, "No Settings tab button found.");
      return;
    }}
    btns.forEach(btn => {{
      if (btn.dataset.vspSettingsBound === "1") return;
      btn.addEventListener("click", () => {{
        try {{
          window.vspInitSettingsTab();
        }} catch (e) {{
          console.error(LOG, "Error in vspInitSettingsTab", e);
        }}
      }});
      btn.dataset.vspSettingsBound = "1";
    }});
    console.log(LOG, "bound", btns.length, "Settings tab buttons.");
  }}
  if (document.readyState === "loading") {{
    document.addEventListener("DOMContentLoaded", bindVspSettingsTab);
  }} else {{
    bindVspSettingsTab();
  }}
}})();
"""
        txt = txt + snippet
        p.write_text(txt, encoding="utf-8")
        print("[OK] Đã append auto-bind snippet vào", p)
PY

echo "[PATCH] DONE. Hãy restart UI (nếu cần) và Ctrl+Shift+R rồi click tab Settings."
