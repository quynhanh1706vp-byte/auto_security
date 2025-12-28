#!/usr/bin/env bash
set -euo pipefail

ROOT="/home/test/Data/SECURITY_BUNDLE/ui"
JS_DIR="$ROOT/static"
TPL="$ROOT/templates/index.html"

echo "[i] ROOT = $ROOT"
echo "[i] JS_DIR = $JS_DIR"
echo "[i] TEMPLATE = $TPL"

mkdir -p "$JS_DIR"

# === tool_config.js ===
cat > "$JS_DIR/tool_config.js" <<'JS1'
(function () {
  const DEFAULT_CONFIG = {
    order: [
      "Bandit",
      "Gitleaks",
      "Semgrep",
      "TrivyVuln",
      "TrivySecret",
      "TrivyMisconfig",
      "TrivySBOM",
      "Grype"
    ],
    tools: {
      Bandit:        { label: "Bandit (Python)",        enabled: true,  category: "SAST" },
      Gitleaks:      { label: "Gitleaks (Secrets)",     enabled: true,  category: "Secrets" },
      Semgrep:       { label: "Semgrep (Code)",         enabled: true,  category: "SAST" },
      TrivyVuln:     { label: "Trivy FS (Vuln)",        enabled: true,  category: "Vuln" },
      TrivySecret:   { label: "Trivy FS (Secrets)",     enabled: false, category: "Secrets" },
      TrivyMisconfig:{ label: "Trivy FS (Misconfig)",   enabled: false, category: "Misconfig" },
      TrivySBOM:     { label: "Trivy SBOM",             enabled: false, category: "SBOM" },
      Grype:         { label: "Grype (SBOM SCA)",       enabled: true,  category: "SBOM" }
    }
  };

  function mergeConfig() {
    const override = window.SECBUNDLE_TOOL_CONFIG_OVERRIDE || {};
    const cfg = JSON.parse(JSON.stringify(DEFAULT_CONFIG));

    if (override.order && Array.isArray(override.order)) {
      cfg.order = override.order.slice();
    }
    if (override.tools && typeof override.tools === "object") {
      Object.keys(override.tools).forEach(function (k) {
        const base = cfg.tools[k] || {};
        cfg.tools[k] = Object.assign({}, base, override.tools[k]);
      });
    }
    return cfg;
  }

  const EFFECTIVE_CONFIG = mergeConfig();

  function getToolMeta(name) {
    const meta = EFFECTIVE_CONFIG.tools[name] || {};
    return {
      key: name,
      label: meta.label || name,
      enabled: typeof meta.enabled === "boolean" ? meta.enabled : true,
      category: meta.category || null
    };
  }

  function normalizeTools(byTool) {
    const names = Object.keys(byTool || {});
    const seen = {};
    const ordered = [];

    EFFECTIVE_CONFIG.order.forEach(function (name) {
      if (names.indexOf(name) !== -1) {
        ordered.push(name);
        seen[name] = true;
      }
    });

    names.forEach(function (name) {
      if (!seen[name]) ordered.push(name);
    });

    return ordered.map(function (name) {
      const meta = getToolMeta(name);
      const data = byTool[name] || {};
      const total = Number(data.total || 0);
      return {
        key: name,
        label: meta.label,
        enabled: meta.enabled,
        total: total,
        raw: data
      };
    });
  }

  window.SECBUNDLE_TOOL_CONFIG = EFFECTIVE_CONFIG;
  window.SECBUNDLE_getToolMeta = getToolMeta;
  window.SECBUNDLE_normalizeTools = normalizeTools;
})();
JS1

# === tool_chart.js ===
cat > "$JS_DIR/tool_chart.js" <<'JS2'
(function () {
  function injectStyles() {
    const id = "tool-chart-inline-style";
    if (document.getElementById(id)) return;
    const style = document.createElement("style");
    style.id = id;
    style.textContent = `
      #toolChart {
        padding: 8px 0;
        font-size: 12px;
      }
      .tool-chart-line {
        display: flex;
        align-items: center;
        margin-bottom: 6px;
        gap: 8px;
      }
      .tool-chart-label {
        flex: 0 0 140px;
        white-space: nowrap;
        overflow: hidden;
        text-overflow: ellipsis;
        opacity: 0.9;
      }
      .tool-chart-bar-container {
        position: relative;
        flex: 1;
        height: 18px;
        background: rgba(255,255,255,0.04);
        border-radius: 999px;
        overflow: hidden;
      }
      .tool-chart-bar {
        position: absolute;
        left: 0;
        top: 0;
        bottom: 0;
        border-radius: 999px;
        background: rgba(100, 181, 246, 0.9);
      }
      .tool-chart-value {
        position: absolute;
        right: 8px;
        top: 50%;
        transform: translateY(-50%);
        font-size: 11px;
        opacity: 0.9;
      }
    `;
    document.head.appendChild(style);
  }

  function renderToolChart(byTool) {
    const mount = document.getElementById("toolChart");
    if (!mount) {
      console.warn("[tool_chart] Không thấy #toolChart");
      return;
    }
    mount.innerHTML = "";

    if (!byTool || typeof byTool !== "object") {
      mount.textContent = "Không có dữ liệu tool.";
      return;
    }
    if (typeof window.SECBUNDLE_normalizeTools !== "function") {
      mount.textContent = "Thiếu tool_config.js.";
      return;
    }

    const rows = window.SECBUNDLE_normalizeTools(byTool)
      .filter(function (r) { return r.enabled && r.total > 0; });

    if (!rows.length) {
      mount.textContent = "Không có findings nào cho các tool bật.";
      return;
    }

    const maxTotal = rows.reduce(function (m, r) {
      return r.total > m ? r.total : m;
    }, 0);

    const wrapper = document.createElement("div");
    wrapper.className = "tool-chart-wrapper";

    rows.forEach(function (row) {
      const line = document.createElement("div");
      line.className = "tool-chart-line";

      const label = document.createElement("div");
      label.className = "tool-chart-label";
      label.textContent = row.label;

      const barContainer = document.createElement("div");
      barContainer.className = "tool-chart-bar-container";

      const bar = document.createElement("div");
      bar.className = "tool-chart-bar";
      const pct = maxTotal > 0 ? (row.total * 100 / maxTotal) : 0;
      bar.style.width = pct.toFixed(1) + "%";

      const value = document.createElement("span");
      value.className = "tool-chart-value";
      value.textContent = row.total.toString();

      barContainer.appendChild(bar);
      barContainer.appendChild(value);

      line.appendChild(label);
      line.appendChild(barContainer);
      wrapper.appendChild(line);
    });

    mount.appendChild(wrapper);
  }

  injectStyles();
  window.SECBUNDLE_renderToolChart = renderToolChart;
})();
JS2

# === Thêm <script> vào template index.html nếu chưa có ===
if [ -f "$TPL" ]; then
  if ! grep -q 'tool_config.js' "$TPL"; then
    printf '\n  <script src="{{ url_for('"'"'static'"'"', filename='"'"'tool_config.js'"'"') }}"></script>\n' >> "$TPL"
  fi
  if ! grep -q 'tool_chart.js' "$TPL"; then
    printf '  <script src="{{ url_for('"'"'static'"'"', filename='"'"'tool_chart.js'"'"') }}"></script>\n' >> "$TPL"
  fi
else
  echo "[WARN] Không tìm thấy template: $TPL" >&2
fi

echo "[OK] setup_tool_ui done."
