#!/usr/bin/env bash
set -euo pipefail

ROOT="/home/test/Data/SECURITY_BUNDLE/ui"

echo "[PATCH] Wire TAB 2 – Runs & Reports"

python - << 'PY'
from pathlib import Path

ROOT = Path("/home/test/Data/SECURITY_BUNDLE/ui")
tpl = ROOT / "my_flask_app/templates/vsp_5tabs_full.html"

if not tpl.is_file():
    print("[ERR] Không tìm thấy", tpl)
else:
    txt = tpl.read_text(encoding="utf-8")
    orig = txt

    marker = '<div class="scroll-y-soft">\n                <table class="vsp-table">'
    if marker not in txt:
        print("[WARN] Không tìm thấy marker bảng Run history, bỏ qua phần HTML.")
    else:
        before, after = txt.split(marker, 1)
        # thay tbody đầu tiên trong block Run history
        old = "<tbody>"
        new = '<tbody id="vsp-runs-tbody">'
        if old in after:
            after_new = after.replace(old, new, 1)
            txt = before + marker + after_new
            backup = tpl.with_suffix(tpl.suffix + ".bak_runs_tbody_v2")
            backup.write_text(orig, encoding="utf-8")
            tpl.write_text(txt, encoding="utf-8")
            print(f"[OK] Thêm id=\"vsp-runs-tbody\" cho Run history (backup -> {backup.name})")
        else:
            print("[WARN] Không tìm thấy <tbody> trong block Run history, không sửa.")

PY

JS_PATH="$ROOT/static/js/vsp_runs_v1.js"
JS_BAK="$ROOT/static/js/vsp_runs_v1.js.bak_wire_v2"

if [ -f "$JS_PATH" ]; then
  cp "$JS_PATH" "$JS_BAK"
  echo "[OK] Backup JS -> $(basename "$JS_BAK")"
fi

cat > "$JS_PATH" << 'JS'
// vsp_runs_v1.js
// TAB 2 – Runs & Reports wiring (clean version, no VSP_RUNS_UI_V1 legacy)
(function() {
  const LOG_PREFIX = "[VSP_RUNS_TAB]";

  function log() {
    if (window.console && console.log) {
      console.log.apply(console, [LOG_PREFIX].concat(Array.from(arguments)));
    }
  }

  function getRunsFromPayload(payload) {
    if (!payload) return [];
    if (Array.isArray(payload)) return payload;
    if (Array.isArray(payload.runs)) return payload.runs;
    if (Array.isArray(payload.items)) return payload.items;
    if (Array.isArray(payload.data)) return payload.data;
    return [];
  }

  async function fetchRunsIndex() {
    try {
      const res = await fetch("/api/vsp/runs_index_v3");
      if (!res.ok) {
        log("runs_index_v3 HTTP error", res.status);
        return [];
      }
      const payload = await res.json();
      const runs = getRunsFromPayload(payload);
      log("Loaded", runs.length, "runs từ runs_index_v3");
      return runs;
    } catch (e) {
      log("Lỗi fetch /api/vsp/runs_index_v3", e);
      return [];
    }
  }

  function renderRunsTable(runs) {
    const tbody = document.getElementById("vsp-runs-tbody");
    if (!tbody) {
      log("Không tìm thấy #vsp-runs-tbody – bỏ qua render bảng.");
      return;
    }

    tbody.innerHTML = "";

    if (!runs || !runs.length) {
      const tr = document.createElement("tr");
      const td = document.createElement("td");
      td.colSpan = 14;
      td.textContent = "No runs available";
      tr.appendChild(td);
      tbody.appendChild(tr);
      return;
    }

    // sort desc theo timestamp nếu có
    runs.sort(function(a, b) {
      if (!a || !b) return 0;
      if (a.timestamp === b.timestamp) return 0;
      if (!a.timestamp) return 1;
      if (!b.timestamp) return -1;
      return a.timestamp < b.timestamp ? 1 : -1;
    });

    runs.forEach(function(r) {
      const tr = document.createElement("tr");
      function td(text) {
        const el = document.createElement("td");
        el.textContent = text == null ? "" : String(text);
        return el;
      }

      const sev = r.by_severity || {};
      const crit  = sev.CRITICAL || 0;
      const high  = sev.HIGH     || 0;
      const med   = sev.MEDIUM   || 0;
      const low   = sev.LOW      || 0;
      const info  = sev.INFO     || 0;
      const trace = sev.TRACE    || 0;
      const total = r.total_findings != null
        ? r.total_findings
        : crit + high + med + low + info + trace;

      tr.appendChild(td(r.run_id || r.id || ""));
      tr.appendChild(td(r.timestamp || ""));
      tr.appendChild(td(r.profile || r.scan_profile || ""));
      tr.appendChild(td(r.src_path || r.source_root || ""));
      tr.appendChild(td(r.target_url || r.url || ""));
      tr.appendChild(td(crit));
      tr.appendChild(td(high));
      tr.appendChild(td(med));
      tr.appendChild(td(low));
      tr.appendChild(td(info));
      tr.appendChild(td(trace));
      tr.appendChild(td(total));
      tr.appendChild(td(r.tools_enabled || r.tools || "Semgrep,Gitleaks,..."));
      tr.appendChild(td("HTML · PDF · CSV"));

      tbody.appendChild(tr);
    });
  }

  function fillRunsKpis(runs) {
    const cardValues = document.querySelectorAll(
      "#tab-runs .runs-kpi-row .vsp-card .kpi-value"
    );
    if (!cardValues || !cardValues.length) {
      return;
    }

    const totalRuns = runs.length;

    // avg findings
    let sumFindings = 0;
    runs.forEach(function(r) {
      const sev = r.by_severity || {};
      const crit  = sev.CRITICAL || 0;
      const high  = sev.HIGH     || 0;
      const med   = sev.MEDIUM   || 0;
      const low   = sev.LOW      || 0;
      const info  = sev.INFO     || 0;
      const trace = sev.TRACE    || 0;
      const total = r.total_findings != null
        ? r.total_findings
        : crit + high + med + low + info + trace;
      sumFindings += total;
    });
    const avgFindings = totalRuns ? Math.round(sumFindings / totalRuns) : 0;

    // tools enabled / run – tạm thời lấy max số tool xuất hiện trong run.by_tool
    let maxTools = 0;
    runs.forEach(function(r) {
      const byTool = r.by_tool || r.tool_stats || {};
      const count = Object.keys(byTool).length;
      if (count > maxTools) maxTools = count;
    });

    if (cardValues[0]) {
      cardValues[0].textContent = totalRuns;
    }
    if (cardValues[1]) {
      // Last 10 runs – tạm thời hiển thị số run gần nhất (min(10, total))
      cardValues[1].textContent = Math.min(10, totalRuns);
    }
    if (cardValues[2]) {
      cardValues[2].textContent = avgFindings || 0;
    }
    if (cardValues[3]) {
      if (maxTools) {
        cardValues[3].textContent = maxTools + " / 7";
      } else {
        cardValues[3].textContent = "– / 7";
      }
    }
  }

  async function initRunsTab() {
    const tabRuns = document.getElementById("tab-runs");
    if (!tabRuns) {
      // UI khác template – không làm gì.
      return;
    }

    const runs = await fetchRunsIndex();
    renderRunsTable(runs);
    fillRunsKpis(runs);
  }

  document.addEventListener("DOMContentLoaded", function() {
    // auto load khi DOM sẵn sàng
    log("vsp_runs_v1.js (mass replace) loaded – auto load runs.");
    initRunsTab();
  });
})();
JS

echo "[PATCH] JS vsp_runs_v1.js đã được ghi lại."

echo "[PATCH] Done."
