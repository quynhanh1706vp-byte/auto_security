#!/usr/bin/env bash
set -euo pipefail

LOG_PREFIX="[VSP_ENABLE_RUNS_SIMPLE_V1]"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

echo "$LOG_PREFIX ROOT = $ROOT"

# 1) Ghi file JS đơn giản cho Runs tab
cat > static/js/vsp_runs_tab_simple_v1.js << 'JS'
(function () {
  const LOG_PREFIX = "[VSP_RUNS_TAB_SIMPLE_V1]";

  function log(msg, extra) {
    if (extra !== undefined) {
      console.log(LOG_PREFIX, msg, extra);
    } else {
      console.log(LOG_PREFIX, msg);
    }
  }

  function ensureContainer() {
    let container = document.querySelector("#vsp-runs-overview");
    if (container) return container;

    const runsTab = document.querySelector("#vsp-tab-runs") || document.body;
    container = document.createElement("div");
    container.id = "vsp-runs-overview";
    container.className = "vsp-card vsp-card-runs";
    runsTab.appendChild(container);
    return container;
  }

  function injectStyles() {
    if (document.getElementById("vsp-runs-tab-simple-style")) return;

    const css = `
      #vsp-runs-overview {
        margin-top: 16px;
        padding: 16px;
        border-radius: 12px;
        background: rgba(15,23,42,0.9);
        border: 1px solid rgba(148,163,184,0.25);
        backdrop-filter: blur(10px);
      }
      #vsp-runs-overview h3 {
        margin: 0 0 12px 0;
        font-size: 14px;
        letter-spacing: .04em;
        text-transform: uppercase;
        color: #e5e7eb;
        opacity: .9;
      }
      #vsp-runs-overview table {
        width: 100%;
        border-collapse: collapse;
        font-size: 13px;
      }
      #vsp-runs-overview thead {
        border-bottom: 1px solid rgba(55,65,81,0.8);
      }
      #vsp-runs-overview th,
      #vsp-runs-overview td {
        padding: 8px 10px;
        text-align: left;
        white-space: nowrap;
      }
      #vsp-runs-overview th {
        font-weight: 500;
        color: #9ca3af;
        text-transform: uppercase;
        font-size: 11px;
        letter-spacing: .06em;
      }
      #vsp-runs-overview tbody tr:nth-child(even) {
        background: rgba(15,23,42,0.7);
      }
      #vsp-runs-overview tbody tr:hover {
        background: rgba(30,64,175,0.35);
      }
      #vsp-runs-overview .run-id {
        font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, "Liberation Mono", "Courier New", monospace;
        font-size: 12px;
        color: #e5e7eb;
      }
      #vsp-runs-overview .badge {
        display: inline-flex;
        align-items: center;
        padding: 2px 8px;
        border-radius: 999px;
        font-size: 10px;
        font-weight: 600;
        letter-spacing: .06em;
        text-transform: uppercase;
      }
      #vsp-runs-overview .badge-ci {
        background: rgba(248,113,113,0.12);
        color: #fecaca;
        border: 1px solid rgba(248,113,113,0.5);
      }
      #vsp-runs-overview .badge-full {
        background: rgba(52,211,153,0.12);
        color: #bbf7d0;
        border: 1px solid rgba(52,211,153,0.5);
      }
      #vsp-runs-overview .score-pill {
        padding: 2px 10px;
        border-radius: 999px;
        font-size: 11px;
        border: 1px solid rgba(148,163,184,0.6);
        color: #e5e7eb;
      }
      #vsp-runs-overview .score-pill-empty {
        opacity: .6;
        font-style: italic;
      }
    `;

    const style = document.createElement("style");
    style.id = "vsp-runs-tab-simple-style";
    style.textContent = css;
    document.head.appendChild(style);
  }

  function formatDate(iso) {
    if (!iso) return "-";
    try {
      const d = new Date(iso);
      if (Number.isNaN(d.getTime())) return iso;
      return d.toLocaleString();
    } catch (e) {
      return iso;
    }
  }

  function detectBadge(item) {
    const id = String(item.run_id || "");
    if (id.startsWith("RUN_VSP_CI_")) return { label: "CI", className: "badge badge-ci" };
    return { label: "FULL_EXT", className: "badge badge-full" };
  }

  function renderTable(container, items) {
    injectStyles();
    container.innerHTML = "";

    const title = document.createElement("h3");
    title.textContent = "Runs history (simple view)";
    container.appendChild(title);

    if (!items || !items.length) {
      const empty = document.createElement("div");
      empty.textContent = "No runs found.";
      empty.style.color = "#9ca3af";
      empty.style.fontSize = "13px";
      container.appendChild(empty);
      return;
    }

    const table = document.createElement("table");
    const thead = document.createElement("thead");
    thead.innerHTML = `
      <tr>
        <th>Run ID</th>
        <th>Type</th>
        <th>Total findings</th>
        <th>Score</th>
        <th>Started at</th>
      </tr>
    `;
    table.appendChild(thead);

    const tbody = document.createElement("tbody");

    items.forEach((item) => {
      const tr = document.createElement("tr");

      const tdId = document.createElement("td");
      tdId.innerHTML = `<span class="run-id">${item.run_id || "-"}</span>`;
      tr.appendChild(tdId);

      const tdType = document.createElement("td");
      const badge = detectBadge(item);
      tdType.innerHTML = `<span class="${badge.className}">${badge.label}</span>`;
      tr.appendChild(tdType);

      const tdTotal = document.createElement("td");
      tdTotal.textContent = (item.total_findings != null ? item.total_findings : "-");
      tr.appendChild(tdTotal);

      const tdScore = document.createElement("td");
      const scoreVal = item.security_posture_score;
      if (typeof scoreVal === "number") {
        tdScore.innerHTML = `<span class="score-pill">${scoreVal}</span>`;
      } else {
        tdScore.innerHTML = `<span class="score-pill score-pill-empty">n/a</span>`;
      }
      tr.appendChild(tdScore);

      const tdStarted = document.createElement("td");
      tdStarted.textContent = formatDate(item.started_at);
      tr.appendChild(tdStarted);

      tbody.appendChild(tr);
    });

    table.appendChild(tbody);
    container.appendChild(table);
  }

  async function loadRunsSimple() {
    const container = ensureContainer();
    try {
      const resp = await fetch("/api/vsp/runs_index_v3?limit=20");
      if (!resp.ok) throw new Error("HTTP " + resp.status);
      const data = await resp.json();
      if (!data || !data.ok) {
        log("API error", data);
        container.textContent = "Failed to load runs (API error).";
        return;
      }
      const items = Array.isArray(data.items) ? data.items : [];
      log("Loaded runs", { count: items.length });
      renderTable(container, items);
    } catch (err) {
      console.error(LOG_PREFIX, "Fetch error", err);
      const container2 = ensureContainer();
      container2.textContent = "Failed to load runs (network error).";
    }
  }

  document.addEventListener("DOMContentLoaded", loadRunsSimple);
  window.vspRunsSimpleReload = loadRunsSimple;
})();
JS

echo "$LOG_PREFIX [OK] Đã ghi static/js/vsp_runs_tab_simple_v1.js"

# 2) Patch template: thêm container + script
CANDIDATES=(
  "templates/vsp_5tabs_full.html"
  "templates/vsp_dashboard_2025.html"
  "templates/vsp_layout_sidebar.html"
)

patched=0

for tpl in "${CANDIDATES[@]}"; do
  if [ ! -f "$tpl" ]; then
    echo "$LOG_PREFIX [INFO] Bỏ qua $tpl (không tồn tại)"
    continue
  fi

  if ! grep -q 'id="vsp-tab-runs"' "$tpl"; then
    echo "$LOG_PREFIX [INFO] Bỏ qua $tpl (không có vsp-tab-runs)"
    continue
  fi

  ts="$(date +%Y%m%d_%H%M%S)"
  backup="${tpl}.bak_runs_simple_${ts}"
  cp "$tpl" "$backup"
  echo "$LOG_PREFIX [BACKUP] $tpl -> $backup"

  python - << PY
import pathlib

LOG_PREFIX = "$LOG_PREFIX"
tpl_path = pathlib.Path("$tpl")
txt = tpl_path.read_text(encoding="utf-8")
changed = False

if 'id="vsp-runs-overview"' not in txt:
    idx = txt.find('id="vsp-tab-runs"')
    if idx != -1:
        gt_idx = txt.find('>', idx)
        if gt_idx != -1:
            inject = '\\n    <div id="vsp-runs-overview"></div>'
            txt = txt[:gt_idx+1] + inject + txt[gt_idx+1:]
            print(LOG_PREFIX, "[OK] Inject container vsp-runs-overview vào", "$tpl")
            changed = True

if 'vsp_runs_tab_simple_v1.js' not in txt:
    script_tag = '\\n    <script src="{{ url_for(\\'static\\', filename=\\'js/vsp_runs_tab_simple_v1.js\\') }}"></script>'
    body_idx = txt.lower().rfind("</body>")
    if body_idx != -1:
        txt = txt[:body_idx] + script_tag + "\\n" + txt[body_idx:]
        print(LOG_PREFIX, "[OK] Inject script vsp_runs_tab_simple_v1.js vào", "$tpl")
        changed = True

if changed:
    tpl_path.write_text(txt, encoding="utf-8")
else:
    print(LOG_PREFIX, "[INFO] Không cần thay đổi", "$tpl")
PY

  patched=1
done

if [ "$patched" -eq 0 ]; then
  echo "$LOG_PREFIX [WARN] Không patch được template nào (không tìm thấy file chứa vsp-tab-runs)."
else
  echo "$LOG_PREFIX [DONE] Hoàn tất enable Runs simple."
fi
