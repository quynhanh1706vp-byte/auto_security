#!/usr/bin/env bash
set -euo pipefail

ROOT="/home/test/Data/SECURITY_BUNDLE/ui"

echo "[PATCH] VSP tabs + runs + datasource – full v3"

############################################
# 1) Overwrite static/js/vsp_runs_v1.js
############################################
cat > "$ROOT/static/js/vsp_runs_v1.js" << 'JS1'
/**
 * VSP_RUNS_TAB v3
 * - Đọc /api/vsp/runs_index_v3
 * - Đổ KPI + bảng Run history vào TAB 2
 */
(function () {
  const LOG_PREFIX = "[VSP_RUNS_TAB]";

  function log() {
    if (window.console && console.log) {
      console.log.apply(console, [LOG_PREFIX].concat(Array.prototype.slice.call(arguments)));
    }
  }

  function normalizeRuns(payload) {
    if (!payload) return [];
    if (Array.isArray(payload)) return payload;
    if (Array.isArray(payload.runs)) return payload.runs;
    if (Array.isArray(payload.items)) return payload.items;
    return [];
  }

  function renderKpis(runs) {
    if (!runs.length) return;

    const kpiRow = document.querySelector("#tab-runs .runs-kpi-row");
    if (!kpiRow) {
      log("Không tìm thấy .runs-kpi-row");
      return;
    }

    const cards = kpiRow.querySelectorAll(".vsp-card");
    if (cards.length < 4) {
      log("Không đủ KPI card trong TAB 2 (cần >= 4)");
      return;
    }

    const totalRunsEl    = cards[0].querySelector(".kpi-value");
    const last10RunsEl   = cards[1].querySelector(".kpi-value");
    const avgFindingsEl  = cards[2].querySelector(".kpi-value");
    const toolsEnabledEl = cards[3].querySelector(".kpi-value");

    const totalRuns = runs.length;
    const recent    = runs.slice(0, 10);

    let sumFindings = 0;
    const toolsSet  = new Set();

    recent.forEach(function (r) {
      const tf = r.total_findings || r.findings_total || 0;
      sumFindings += tf;

      const tools = r.tools_enabled || r.tools || [];
      if (Array.isArray(tools)) {
        tools.forEach(function (t) { toolsSet.add(t); });
      }
    });

    const avgFindings = recent.length ? Math.round(sumFindings / recent.length) : 0;
    const toolsCount  = toolsSet.size || 0;

    if (totalRunsEl)    totalRunsEl.textContent    = totalRuns;
    if (last10RunsEl)   last10RunsEl.textContent   = recent.length;
    if (avgFindingsEl)  avgFindingsEl.textContent  = avgFindings;
    if (toolsEnabledEl) toolsEnabledEl.textContent = toolsCount + "/7";
  }

  function renderTable(runs) {
    const tbody = document.querySelector("#tab-runs table.vsp-table tbody");
    if (!tbody) {
      log("Không tìm thấy tbody run history trong TAB 2");
      return;
    }

    tbody.innerHTML = "";

    if (!runs.length) {
      const tr = document.createElement("tr");
      const td = document.createElement("td");
      td.colSpan = 14;
      td.textContent = "No runs yet";
      tr.appendChild(td);
      tbody.appendChild(tr);
      return;
    }

    runs = runs.slice().sort(function (a, b) {
      const ta = a.timestamp || a.started_at || "";
      const tb = b.timestamp || b.started_at || "";
      if (ta < tb) return 1;
      if (ta > tb) return -1;
      return 0;
    });

    runs.forEach(function (r) {
      const tr = document.createElement("tr");

      function cell(v) {
        const td = document.createElement("td");
        td.textContent = (v === null || v === undefined) ? "" : String(v);
        return td;
      }

      const sev = r.by_severity || r.severity || {};

      const toolsList = r.tools_enabled || r.tools || [];
      let toolsText = "";
      if (Array.isArray(toolsList)) {
        toolsText = toolsList.join(",");
      } else if (toolsList) {
        toolsText = String(toolsList);
      }

      tr.appendChild(cell(r.run_id || ""));
      tr.appendChild(cell(r.timestamp || r.started_at || ""));
      tr.appendChild(cell(r.profile || r.scan_profile || ""));
      tr.appendChild(cell(r.src_path || r.source_root || ""));
      tr.appendChild(cell(r.target_url || r.url || ""));
      tr.appendChild(cell(sev.CRITICAL || 0));
      tr.appendChild(cell(sev.HIGH || 0));
      tr.appendChild(cell(sev.MEDIUM || 0));
      tr.appendChild(cell(sev.LOW || 0));
      tr.appendChild(cell(sev.INFO || 0));
      tr.appendChild(cell(sev.TRACE || 0));
      tr.appendChild(cell(r.total_findings || r.findings_total || 0));
      tr.appendChild(cell(toolsText));
      tr.appendChild(cell("HTML · PDF · CSV"));

      tbody.appendChild(tr);
    });
  }

  function init() {
    if (!document.getElementById("tab-runs")) return;

    fetch("/api/vsp/runs_index_v3")
      .then(function (resp) {
        if (!resp.ok) throw new Error("HTTP " + resp.status);
        return resp.json();
      })
      .then(function (payload) {
        const runs = normalizeRuns(payload);
        log("Loaded " + runs.length + " runs từ runs_index_v3");
        renderKpis(runs);
        renderTable(runs);
      })
      .catch(function (err) {
        console.error(LOG_PREFIX, "Lỗi load runs_index_v3", err);
      });
  }

  document.addEventListener("DOMContentLoaded", init);
})();
JS1

############################################
# 2) Overwrite static/js/vsp_datasource_filters_v2.js
############################################
cat > "$ROOT/static/js/vsp_datasource_filters_v2.js" << 'JS2'
/**
 * VSP_DS_TAB v2
 * - Đọc /api/vsp/datasource_v2?limit=500
 * - Đổ bảng Unified findings + mini charts trong TAB 3
 */
(function () {
  const LOG_PREFIX = "[VSP_DS_TAB]";

  function log() {
    if (window.console && console.log) {
      console.log.apply(console, [LOG_PREFIX].concat(Array.prototype.slice.call(arguments)));
    }
  }

  function normalizeItems(payload) {
    if (!payload) return [];
    if (Array.isArray(payload)) return payload;
    if (Array.isArray(payload.items)) return payload.items;
    return [];
  }

  function renderTable(items) {
    const tbody = document.querySelector("#tab-data table.vsp-table tbody");
    if (!tbody) {
      log("Không tìm thấy tbody unified findings trong TAB 3");
      return;
    }

    tbody.innerHTML = "";

    if (!items.length) {
      const tr = document.createElement("tr");
      const td = document.createElement("td");
      td.colSpan = 11;
      td.textContent = "No findings";
      tr.appendChild(td);
      tbody.appendChild(tr);
      return;
    }

    items.slice(0, 200).forEach(function (it) {
      const tr = document.createElement("tr");

      function cell(v) {
        const td = document.createElement("td");
        td.textContent = (v === null || v === undefined) ? "" : String(v);
        return td;
      }

      tr.appendChild(cell(it.severity || it.severity_effective || ""));
      tr.appendChild(cell(it.tool || ""));
      tr.appendChild(cell(it.file || it.path || ""));
      tr.appendChild(cell(it.line || ""));
      tr.appendChild(cell(it.rule_id || ""));
      tr.appendChild(cell(it.message || ""));
      tr.appendChild(cell(it.cwe || ""));
      tr.appendChild(cell(it.cve || ""));
      tr.appendChild(cell(it.module || ""));
      tr.appendChild(cell(it.fix || ""));
      tr.appendChild(cell(
        Array.isArray(it.tags) ? it.tags.join(",") : (it.tags || "")
      ));

      tbody.appendChild(tr);
    });
  }

  function computeSeverityBuckets(items) {
    const buckets = { CRITICAL: 0, HIGH: 0, MEDIUM: 0, LOW: 0, INFO: 0, TRACE: 0 };
    items.forEach(function (it) {
      const sev = (it.severity_effective || it.severity || "").toUpperCase();
      if (buckets.hasOwnProperty(sev)) {
        buckets[sev] += 1;
      }
    });
    return buckets;
  }

  function computeCweCounts(items) {
    const map = {};
    items.forEach(function (it) {
      const cwe = (it.cwe || "").trim();
      if (!cwe) return;
      map[cwe] = (map[cwe] || 0) + 1;
    });
    const arr = Object.keys(map).map(function (k) {
      return { cwe: k, count: map[k] };
    });
    arr.sort(function (a, b) { return b.count - a.count; });
    return arr.slice(0, 5);
  }

  function renderCharts(items) {
    if (!window.Chart) {
      log("Chart.js chưa load, bỏ qua chart");
      return;
    }

    const sevBuckets = computeSeverityBuckets(items);
    const topCwe     = computeCweCounts(items);

    // Donut severity
    (function () {
      const el = document.getElementById("dataSeverityDonut");
      if (!el) return;
      const ctx = el.getContext("2d");

      new Chart(ctx, {
        type: "doughnut",
        data: {
          labels: ["CRIT", "HIGH", "MED", "LOW", "INFO", "TRACE"],
          datasets: [{
            data: [
              sevBuckets.CRITICAL,
              sevBuckets.HIGH,
              sevBuckets.MEDIUM,
              sevBuckets.LOW,
              sevBuckets.INFO,
              sevBuckets.TRACE
            ],
            backgroundColor: [
              "#ff1744",
              "#ff6d00",
              "#fbbf24",
              "#22c55e",
              "#38bdf8",
              "#a855f7"
            ],
            borderWidth: 0
          }]
        },
        options: {
          responsive: true,
          maintainAspectRatio: false,
          plugins: {
            legend: {
              position: "bottom",
              labels: { color: "#e5e7eb", font: { size: 9 } }
            }
          },
          cutout: "65%"
        }
      });
    })();

    // Top CWE bar
    (function () {
      const el = document.getElementById("dataCWEAndDirs");
      if (!el) return;
      const ctx = el.getContext("2d");

      const labels = topCwe.map(function (x) { return x.cwe; });
      const counts = topCwe.map(function (x) { return x.count; });

      new Chart(ctx, {
        type: "bar",
        data: {
          labels: labels,
          datasets: [{
            label: "Findings",
            data: counts,
            backgroundColor: "#22d3ee"
          }]
        },
        options: {
          responsive: true,
          maintainAspectRatio: false,
          scales: {
            x: {
              ticks: { color: "#9ca3af", font: { size: 9 } },
              grid: { display: false }
            },
            y: {
              ticks: { color: "#9ca3af", font: { size: 9 } },
              grid: { color: "rgba(55,65,81,0.4)" }
            }
          },
          plugins: {
            legend: { display: false }
          }
        }
      });
    })();
  }

  function init() {
    if (!document.getElementById("tab-data")) return;

    fetch("/api/vsp/datasource_v2?limit=500")
      .then(function (resp) {
        if (!resp.ok) throw new Error("HTTP " + resp.status);
        return resp.json();
      })
      .then(function (payload) {
        const items = normalizeItems(payload);
        log("Loaded " + items.length + " findings từ datasource_v2");
        renderTable(items);
        renderCharts(items);
      })
      .catch(function (err) {
        console.error(LOG_PREFIX, "Lỗi load datasource_v2", err);
      });
  }

  document.addEventListener("DOMContentLoaded", init);
})();
JS2

############################################
# 3) Fix tab switcher trong templates
############################################
python - << 'PY'
import re, pathlib, time

ROOT = pathlib.Path("/home/test/Data/SECURITY_BUNDLE/ui")
targets = [
    ROOT / "templates" / "index.html",
    ROOT / "my_flask_app" / "templates" / "vsp_5tabs_full.html",
]

new_block = """
<script>
  // VSP_TABS_V2: simple tab switcher, chạy sau khi DOM ready
  document.addEventListener('DOMContentLoaded', function () {
    console.log('[VSP_TABS] binding tab buttons');

    var buttons = document.querySelectorAll('.vsp-tab-btn');
    var panes   = document.querySelectorAll('.tab-pane');

    if (!buttons.length || !panes.length) {
      console.warn('[VSP_TABS] Không tìm thấy tabs để bind.');
      return;
    }

    function activateTab(targetId) {
      panes.forEach(function (p) {
        if (p.id === targetId) {
          p.classList.add('active');
        } else {
          p.classList.remove('active');
        }
      });
      buttons.forEach(function (b) {
        if (b.dataset.tab === targetId) {
          b.classList.add('active');
        } else {
          b.classList.remove('active');
        }
      });
    }

    buttons.forEach(function (btn) {
      btn.addEventListener('click', function (e) {
        e.preventDefault();
        var targetId = btn.dataset.tab;
        if (!targetId) return;
        console.log('[VSP_TABS] switch to', targetId);
        activateTab(targetId);
      });
    });

    var activeBtn = document.querySelector('.vsp-tab-btn.active') || buttons[0];
    if (activeBtn && activeBtn.dataset.tab) {
      activateTab(activeBtn.dataset.tab);
    }
  });
</script>
""".strip()

pattern = re.compile(
    r"<script>\\s*// Simple tab switcher[\\s\\S]*?</script>",
    re.MULTILINE,
)

for path in targets:
    if not path.is_file():
        print(f"[SKIP] {path} (không tồn tại)")
        continue

    txt = path.read_text(encoding="utf-8")
    new_txt, n = pattern.subn(new_block, txt, count=1)
    if n:
        backup = path.with_suffix(path.suffix + f".bak_tabs_v2_{time.strftime('%Y%m%d_%H%M%S')}")
        backup.write_text(txt, encoding="utf-8")
        path.write_text(new_txt, encoding="utf-8")
        print(f"[OK] Patched tab switcher trong {path} (backup -> {backup.name})")
    else:
        print(f"[WARN] Không tìm thấy block 'Simple tab switcher' trong {path} – bỏ qua.")
PY

echo "[PATCH] Done."
