#!/usr/bin/env bash
set -euo pipefail

ROOT="/home/test/Data/SECURITY_BUNDLE/ui"
APP="$ROOT/run_ui_server.py"
TPL="$ROOT/templates/index.html"
JS_TREND="$ROOT/static/patch_dashboard_trend_runs.js"
JS_TOOLS="$ROOT/static/patch_dashboard_by_tool_config.js"

echo "[i] ROOT  = $ROOT"
echo "[i] APP   = $APP"
echo "[i] TPL   = $TPL"

if [ ! -f "$APP" ]; then
  echo "[ERR] Không tìm thấy $APP (run_ui_server.py)."
  exit 1
fi

if [ ! -f "$TPL" ]; then
  echo "[ERR] Không tìm thấy $TPL"
  exit 1
fi

mkdir -p "$ROOT/static"

############################################
# 1) JS cho TREND – LAST RUNS
############################################
cat > "$JS_TREND" <<'JS'
(function () {
  function log(msg) {
    console.log('[TREND-RUNS]', msg);
  }

  function findTrendTable() {
    var tables = document.querySelectorAll('table');
    for (var i = 0; i < tables.length; i++) {
      var t = tables[i];
      var wrapper = t.closest('section, div, .card, .panel') || t.parentElement;
      if (!wrapper) continue;
      var txt = (wrapper.textContent || '').toLowerCase();
      if (txt.indexOf('trend') !== -1 && txt.indexOf('last runs') !== -1) {
        return t;
      }
    }
    return null;
  }

  function renderTrend(table, runs) {
    if (!table) return;
    var tbody = table.querySelector('tbody');
    if (!tbody) {
      tbody = document.createElement('tbody');
      table.appendChild(tbody);
    }
    tbody.innerHTML = '';

    if (!runs || !runs.length) {
      var tr = document.createElement('tr');
      var td = document.createElement('td');
      td.colSpan = 4;
      td.textContent = 'Chưa có RUN_* nào có report/summary_unified.json.';
      tr.appendChild(td);
      tbody.appendChild(tr);
      return;
    }

    runs.forEach(function (r) {
      var tr = document.createElement('tr');

      var tdRun = document.createElement('td');
      tdRun.textContent = r.run || '';
      tr.appendChild(tdRun);

      var tdTime = document.createElement('td');
      tdTime.textContent = r.time || '';
      tr.appendChild(tdTime);

      var tdTotal = document.createElement('td');
      tdTotal.textContent = (r.total != null ? r.total : '');
      tr.appendChild(tdTotal);

      var tdCH = document.createElement('td');
      var ch = '';
      if (r.critical != null || r.high != null) {
        ch = (r.critical || 0) + '/' + (r.high || 0);
      }
      tdCH.textContent = ch;
      tr.appendChild(tdCH);

      tbody.appendChild(tr);
    });
  }

  function init() {
    var table = findTrendTable();
    if (!table) {
      log('Không tìm thấy bảng Trend – Last runs.');
      return;
    }

    fetch('/api/runs_brief')
      .then(function (res) { return res.json(); })
      .then(function (data) {
        if (!Array.isArray(data)) {
          log('api/runs_brief trả về không phải array.');
          return;
        }
        renderTrend(table, data);
      })
      .catch(function (err) {
        console.error('[TREND-RUNS] Lỗi fetch /api/runs_brief:', err);
      });
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }
})();
JS

echo "[OK] Đã ghi $JS_TREND"

############################################
# 2) JS cho BY TOOL / CONFIG (tool_config.json)
############################################
cat > "$JS_TOOLS" <<'JS'
(function () {
  function log(msg) {
    console.log('[TOOLS-CONFIG]', msg);
  }

  function findToolsTable() {
    var tables = document.querySelectorAll('table');
    for (var i = 0; i < tables.length; i++) {
      var t = tables[i];
      var wrapper = t.closest('section, div, .card, .panel') || t.parentElement;
      if (!wrapper) continue;
      var txt = (wrapper.textContent || '').toLowerCase();
      if (txt.indexOf('by tool') !== -1 && txt.indexOf('config') !== -1) {
        return t;
      }
    }
    return null;
  }

  function renderTools(table, tools) {
    if (!table) return;
    var tbody = table.querySelector('tbody');
    if (!tbody) {
      tbody = document.createElement('tbody');
      table.appendChild(tbody);
    }
    tbody.innerHTML = '';

    if (!tools || !tools.length) {
      var tr = document.createElement('tr');
      var td = document.createElement('td');
      td.colSpan = 4;
      td.textContent = 'Chưa đọc được tool_config.json hoặc chưa có tool nào.';
      tr.appendChild(td);
      tbody.appendChild(tr);
      return;
    }

    tools.forEach(function (t) {
      var tr = document.createElement('tr');

      var tdTool = document.createElement('td');
      tdTool.textContent = t.tool || '';
      tr.appendChild(tdTool);

      var tdEnabled = document.createElement('td');
      tdEnabled.textContent = t.enabled ? 'ON' : 'OFF';
      tr.appendChild(tdEnabled);

      var tdLevel = document.createElement('td');
      tdLevel.textContent = t.level || '';
      tr.appendChild(tdLevel);

      var tdModes = document.createElement('td');
      tdModes.textContent = t.modes || '';
      tr.appendChild(tdModes);

      tbody.appendChild(tr);
    });
  }

  function init() {
    var table = findToolsTable();
    if (!table) {
      log('Không tìm thấy bảng BY TOOL / CONFIG.');
      return;
    }

    fetch('/api/tools_by_config')
      .then(function (res) { return res.json(); })
      .then(function (data) {
        var tools = data && data.tools;
        if (!Array.isArray(tools)) {
          log('api/tools_by_config trả về không phải {tools:[...]}');
          return;
        }
        renderTools(table, tools);
      })
      .catch(function (err) {
        console.error('[TOOLS-CONFIG] Lỗi fetch /api/tools_by_config:', err);
      });
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }
})();
JS

echo "[OK] Đã ghi $JS_TOOLS"

############################################
# 3) Thêm API vào run_ui_server.py
############################################
python3 - "$APP" <<'PY'
from pathlib import Path
import sys, json, os
from collections import Counter

path = Path(sys.argv[1])
data = path.read_text(encoding="utf-8")

# Nếu đã patch rồi thì bỏ qua
if "/api/runs_brief" in data and "/api/tools_by_config" in data:
    print("[INFO] run_ui_server.py đã có API runs_brief + tools_by_config, bỏ qua.")
    sys.exit(0)

block = r'''
def _serialize_runs_brief():
    runs = []
    try:
        out_dir = OUT_DIR
    except NameError:
        from pathlib import Path as _Path
        out_dir = _Path(__file__).resolve().parent.parent / "out"

    if not out_dir.is_dir():
        return []

    for d in sorted(out_dir.glob("RUN_2*")):
        if not d.is_dir():
            continue
        name = d.name
        if name.startswith("RUN_GITLEAKS_EXT_") or name.startswith("RUN_DEMO_"):
            continue
        report_dir = d / "report"
        summary_path = report_dir / "summary_unified.json"
        if not summary_path.is_file():
            continue
        try:
            with summary_path.open("r", encoding="utf-8") as f:
                s = json.load(f)
        except Exception:
            continue
        total = s.get("total")
        crit  = s.get("critical") or s.get("crit") or s.get("C") or 0
        high  = s.get("high") or s.get("H") or 0
        med   = s.get("medium") or s.get("M") or 0
        low   = s.get("low") or s.get("L") or 0
        mt = d.stat().st_mtime
        from datetime import datetime
        ts = datetime.fromtimestamp(mt).strftime("%Y-%m-%d %H:%M:%S")
        runs.append({
            "run": name,
            "time": ts,
            "total": total,
            "critical": crit,
            "high": high,
            "medium": med,
            "low": low,
        })

    runs.sort(key=lambda x: x.get("run") or "", reverse=True)
    return runs


def api_runs_brief_impl():
    return _serialize_runs_brief()


if "api_runs_brief" in app.view_functions:
    app.view_functions["api_runs_brief"] = api_runs_brief_impl
else:
    app.add_url_rule(
        "/api/runs_brief",
        "api_runs_brief",
        api_runs_brief_impl,
        methods=["GET"],
    )


def api_runs_impl():
    return _serialize_runs_brief()


if "api_runs" in app.view_functions:
    app.view_functions["api_runs"] = api_runs_impl
else:
    app.add_url_rule(
        "/api/runs",
        "api_runs",
        api_runs_impl,
        methods=["GET"],
    )


TOOL_CFG_PATH = Path(__file__).resolve().parent / "tool_config.json"


def _load_tool_config_summary():
    cfg_path = TOOL_CFG_PATH
    if not cfg_path.is_file():
        return {"tools": []}

    try:
        with cfg_path.open("r", encoding="utf-8") as f:
            cfg = json.load(f)
    except Exception:
        return {"tools": []}

    # Nếu là dict có key 'tools' thì lấy ra
    if isinstance(cfg, dict):
        if "tools" in cfg and isinstance(cfg["tools"], list):
            items = cfg["tools"]
        elif "config" in cfg and isinstance(cfg["config"], list):
            items = cfg["config"]
        else:
            items = list(cfg.values()) if isinstance(list(cfg.values())[0], dict) else []
    elif isinstance(cfg, list):
        items = cfg
    else:
        items = []

    rows = []

    for idx, item in enumerate(items):
        if not isinstance(item, dict):
            continue
        name = (
            item.get("tool")
            or item.get("name")
            or item.get("id")
            or f"tool_{idx+1}"
        )

        def _b(val):
            if isinstance(val, bool):
                return val
            if isinstance(val, (int, float)):
                return val != 0
            if isinstance(val, str):
                return val.strip().lower() in ("1", "true", "yes", "y", "on")
            return False

        enabled = (
            _b(item.get("enabled"))
            or _b(item.get("enable"))
            or _b(item.get("ENABLED"))
            or _b(item.get("ENABLE"))
        )

        level = (
            item.get("profile")
            or item.get("level")
            or item.get("mode")
            or item.get("severity")
            or ""
        )

        modes = []
        for key, label in [
            ("mode_offline", "Offline"),
            ("mode_online", "Online"),
            ("mode_ci", "CI/CD"),
            ("offline", "Offline"),
            ("online", "Online"),
            ("ci_cd", "CI/CD"),
            ("ci", "CI/CD"),
        ]:
            if key in item and _b(item.get(key)):
                modes.append(label)

        modes_str = ", ".join(sorted(set(modes))) if modes else ""
        rows.append({
            "tool": name,
            "enabled": enabled,
            "level": level,
            "modes": modes_str,
        })

    return {"tools": rows}


def api_tools_by_config_impl():
    return _load_tool_config_summary()


if "api_tools_by_config" in app.view_functions:
    app.view_functions["api_tools_by_config"] = api_tools_by_config_impl
else:
    app.add_url_rule(
        "/api/tools_by_config",
        "api_tools_by_config",
        api_tools_by_config_impl,
        methods=["GET"],
    )
'''

marker = 'if __name__ == "__main__":'
if marker in data:
    new_data = data.replace(marker, block + "\n\n" + marker, 1)
else:
    new_data = data.rstrip() + "\n\n" + block + "\n"

path.write_text(new_data, encoding="utf-8")
print("[OK] Đã chèn API runs_brief + tools_by_config vào run_ui_server.py")
PY

############################################
# 4) Include 2 script JS vào index.html
############################################
python3 - "$TPL" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
data = path.read_text(encoding="utf-8")

need_trend = "patch_dashboard_trend_runs.js" not in data
need_tools = "patch_dashboard_by_tool_config.js" not in data

if not need_trend and not need_tools:
    print("[INFO] templates/index.html đã include JS trend+tools, bỏ qua.")
    sys.exit(0)

insert_block = ""
if need_trend:
    insert_block += "    <script src=\"{{ url_for('static', filename='patch_dashboard_trend_runs.js') }}\"></script>\\n"
if need_tools:
    insert_block += "    <script src=\"{{ url_for('static', filename='patch_dashboard_by_tool_config.js') }}\"></script>\\n"

if "</body>" not in data:
    print("[ERR] Không tìm thấy </body> trong templates/index.html")
    sys.exit(1)

new_data = data.replace("</body>", insert_block + "</body>")
path.write_text(new_data, encoding="utf-8")
print("[OK] Đã chèn script trend+tools vào templates/index.html")
PY

echo "[DONE] patch_dashboard_trend_and_tools.sh hoàn thành."
