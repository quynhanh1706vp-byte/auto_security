#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
JS="$ROOT/static/js/vsp_console_patch_v1.js"

if [ ! -f "$JS" ]; then
  echo "[ERR] Không tìm thấy $JS"
  exit 1
fi

TS="$(date +%Y%m%d_%H%M%S)"
cp "$JS" "${JS}.bak_tabs_layout_${TS}"
echo "[BACKUP] $JS -> ${JS}.bak_tabs_layout_${TS}"

cat >> "$JS" << 'JS_EOF'

// [VSP_TABS_LAYOUT_V1]
(function () {
  "use strict";
  var LOG = "[VSP_TABS_LAYOUT]";

  function log() {
    if (typeof console !== "undefined" && console.log) {
      var args = Array.prototype.slice.call(arguments);
      args.unshift(LOG);
      console.log.apply(console, args);
    }
  }

  function setRunsLayout() {
    var root = document.getElementById("vsp-tab-runs");
    if (!root) {
      log("No #vsp-tab-runs, skip.");
      return;
    }
    if (root.dataset.vspLayout === "full") return;
    root.dataset.vspLayout = "full";

    root.innerHTML = [
      '<div class="vsp-two-col">',
      '  <div class="vsp-card">',
      '    <div class="vsp-card-header">',
      '      <div>',
      '        <div class="vsp-card-title">Runs &amp; Reports</div>',
      '        <div class="vsp-card-subtitle">Danh sách scan runs từ thư mục out/</div>',
      '      </div>',
      '    </div>',
      '    <div class="vsp-card-body">',
      '      <div class="vsp-filters-row">',
      '        <select id="vsp-runs-filter-profile" class="vsp-input">',
      '          <option value="">All profiles</option>',
      '          <option value="FAST">FAST</option>',
      '          <option value="EXT">EXT</option>',
      '          <option value="FULL">FULL</option>',
      '        </select>',
      '        <select id="vsp-runs-filter-severity" class="vsp-input">',
      '          <option value="">Any severity</option>',
      '          <option value="CRITICAL">CRITICAL</option>',
      '          <option value="HIGH">HIGH</option>',
      '          <option value="MEDIUM">MEDIUM</option>',
      '          <option value="LOW">LOW</option>',
      '        </select>',
      '        <input id="vsp-runs-filter-daterange" class="vsp-input" placeholder="Date range (optional)" />',
      '      </div>',
      '      <div class="vsp-table-wrapper">',
      '        <table class="vsp-table vsp-table-runs">',
      '          <thead>',
      '            <tr>',
      '              <th>Run ID</th>',
      '              <th>Profile</th>',
      '              <th>Posture</th>',
      '              <th>Total</th>',
      '              <th>Max severity</th>',
      '              <th>Started at</th>',
      '            </tr>',
      '          </thead>',
      '          <tbody id="vsp-runs-tbody"></tbody>',
      '        </table>',
      '      </div>',
      '    </div>',
      '  </div>',
      '  <div class="vsp-card vsp-card-side">',
      '    <div class="vsp-card-header vsp-card-header-actions">',
      '      <div>',
      '        <div class="vsp-card-title">Run detail</div>',
      '        <div class="vsp-card-subtitle">Posture / total / severity tối đa.</div>',
      '      </div>',
      '      <div class="vsp-card-actions">',
      '        <button id="vsp-run-export-html" class="vsp-chip-btn vsp-run-export-btn">Export HTML</button>',
      '        <button id="vsp-run-export-zip" class="vsp-chip-btn vsp-run-export-btn">Export ZIP</button>',
      '      </div>',
      '    </div>',
      '    <div class="vsp-card-body" id="vsp-run-detail"></div>',
      '  </div>',
      '</div>'
    ].join("");

    if (typeof window.vspReloadRuns === "function") {
      try {
        window.vspReloadRuns();
      } catch (e) {
        log("vspReloadRuns error:", e);
      }
    } else {
      log("window.vspReloadRuns not found – runs table sẽ được JS khác lo nếu có.");
    }
  }

  function setDataSourceLayout() {
    var root = document.getElementById("vsp-tab-datasource");
    if (!root) {
      log("No #vsp-tab-datasource, skip.");
      return;
    }
    if (root.dataset.vspLayout === "full") return;
    root.dataset.vspLayout = "full";

    root.innerHTML = [
      '<div id="vsp-ds-root" class="vsp-card">',
      '  <div class="vsp-card-header">',
      '    <div>',
      '      <div class="vsp-card-title">Unified Findings</div>',
      '      <div class="vsp-card-subtitle">Data source từ summary_unified / findings_unified.</div>',
      '    </div>',
      '    <div class="vsp-card-actions">',
      '      <button id="vsp-ds-reload" class="vsp-chip-btn">Reload</button>',
      '    </div>',
      '  </div>',
      '  <div class="vsp-card-body">',
      '    <div class="vsp-filters-row">',
      '      <select id="vsp-ds-filter-severity" class="vsp-input">',
      '        <option value="">Severity: Any</option>',
      '        <option value="CRITICAL">CRITICAL</option>',
      '        <option value="HIGH">HIGH</option>',
      '        <option value="MEDIUM">MEDIUM</option>',
      '        <option value="LOW">LOW</option>',
      '        <option value="INFO">INFO</option>',
      '        <option value="TRACE">TRACE</option>',
      '      </select>',
      '      <select id="vsp-ds-filter-tool" class="vsp-input">',
      '        <option value="">Tool: Any</option>',
      '        <option value="semgrep">Semgrep</option>',
      '        <option value="bandit">Bandit</option>',
      '        <option value="codeql">CodeQL</option>',
      '        <option value="trivy">Trivy</option>',
      '        <option value="grype">Grype</option>',
      '        <option value="kics">KICS</option>',
      '        <option value="gitleaks">Gitleaks</option>',
      '      </select>',
      '      <input id="vsp-ds-filter-text" class="vsp-input" placeholder="Search message / path / CWE..." />',
      '    </div>',
      '    <div class="vsp-table-wrapper vsp-table-wrapper-ds">',
      '      <table class="vsp-table vsp-table-ds">',
      '        <thead>',
      '          <tr>',
      '            <th>Severity</th>',
      '            <th>Tool</th>',
      '            <th>CWE</th>',
      '            <th>Rule</th>',
      '            <th>Path</th>',
      '            <th>Line</th>',
      '            <th>Message</th>',
      '            <th>Run</th>',
      '          </tr>',
      '        </thead>',
      '        <tbody id="vsp-ds-tbody"></tbody>',
      '      </table>',
      '    </div>',
      '    <div class="vsp-ds-pager">',
      '      <button id="vsp-ds-prev" class="vsp-chip-btn">Prev</button>',
      '      <span id="vsp-ds-page-info" class="vsp-ds-page-info">Page 1</span>',
      '      <button id="vsp-ds-next" class="vsp-chip-btn">Next</button>',
      '    </div>',
      '  </div>',
      '</div>'
    ].join("");

    log("Data Source layout ready (chưa gắn API – sẽ làm V2).");
  }

  function setSettingsLayout() {
    var root = document.getElementById("vsp-tab-settings");
    if (!root) {
      log("No #vsp-tab-settings, skip.");
      return;
    }
    if (root.dataset.vspLayout === "full") return;
    root.dataset.vspLayout = "full";

    root.innerHTML = [
      '<div id="vsp-settings-root" class="vsp-card">',
      '  <div class="vsp-card-header">',
      '    <div>',
      '      <div class="vsp-card-title">Profiles &amp; Tools</div>',
      '      <div class="vsp-card-subtitle">settings_v1 – profiles, tool toggles, default profile.</div>',
      '    </div>',
      '    <div class="vsp-card-actions">',
      '      <button id="vsp-settings-reload" class="vsp-chip-btn">Reload</button>',
      '      <button id="vsp-settings-save" class="vsp-chip-btn">Save</button>',
      '    </div>',
      '  </div>',
      '  <div class="vsp-card-body">',
      '    <textarea id="vsp-settings-json" class="vsp-json-editor" spellcheck="false"></textarea>',
      '    <div id="vsp-settings-status" class="vsp-status-line"></div>',
      '  </div>',
      '</div>'
    ].join("");

    if (!window.vspInitSettingsTab) {
      window.vspInitSettingsTab = function () {
        console.log("[VSP_SETTINGS_TAB] stub init – UI only (chưa gắn API).");
      };
    }
  }

  function setRulesLayout() {
    var root = document.getElementById("vsp-tab-rules");
    if (!root) {
      log("No #vsp-tab-rules, skip.");
      return;
    }
    if (root.dataset.vspLayout === "full") return;
    root.dataset.vspLayout = "full";

    root.innerHTML = [
      '<div id="vsp-rules-root" class="vsp-card">',
      '  <div class="vsp-card-header">',
      '    <div>',
      '      <div class="vsp-card-title">Rule Overrides</div>',
      '      <div class="vsp-card-subtitle">Override severity / pattern cho từng tool – rule_overrides_v1.</div>',
      '    </div>',
      '    <div class="vsp-card-actions">',
      '      <button id="vsp-rules-reload" class="vsp-chip-btn">Reload</button>',
      '      <button id="vsp-rules-save" class="vsp-chip-btn">Save</button>',
      '    </div>',
      '  </div>',
      '  <div class="vsp-card-body">',
      '    <div class="vsp-two-col">',
      '      <div>',
      '        <div class="vsp-section-title">Danh sách overrides</div>',
      '        <div class="vsp-table-wrapper vsp-table-wrapper-rules">',
      '          <table class="vsp-table vsp-table-rules">',
      '            <thead>',
      '              <tr>',
      '                <th>ID</th>',
      '                <th>Tool</th>',
      '                <th>Pattern</th>',
      '                <th>Severity</th>',
      '                <th>Reason</th>',
      '              </tr>',
      '            </thead>',
      '            <tbody id="vsp-rules-tbody">',
      '              <tr><td colspan="5">V1 – chưa load dữ liệu.</td></tr>',
      '            </tbody>',
      '          </table>',
      '        </div>',
      '      </div>',
      '      <div>',
      '        <div class="vsp-section-title">JSON rule_overrides_v1</div>',
      '        <textarea id="vsp-rules-json" class="vsp-json-editor" spellcheck="false"></textarea>',
      '        <div id="vsp-rules-status" class="vsp-status-line"></div>',
      '      </div>',
      '    </div>',
      '  </div>',
      '</div>'
    ].join("");

    log("Rule Overrides layout ready (V1, chưa gắn API).");
  }

  function run() {
    setRunsLayout();
    setDataSourceLayout();
    setSettingsLayout();
    setRulesLayout();
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", run);
  } else {
    run();
  }
})();
JS_EOF

echo "[OK] Đã append layout V1 cho 4 tab vào $JS"
