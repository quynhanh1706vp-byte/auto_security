#!/usr/bin/env bash
set -euo pipefail

UI_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

CSS="$UI_ROOT/static/css/vsp_ui_commercial_v1.css"
JS="$UI_ROOT/static/js/vsp_ui_commercial_polish_v1.js"
TPL="$UI_ROOT/templates/vsp_dashboard_2025.html"

echo "[VSP_UI_COMM] UI_ROOT = $UI_ROOT"
echo "[VSP_UI_COMM] CSS      = $CSS"
echo "[VSP_UI_COMM] JS       = $JS"
echo "[VSP_UI_COMM] TPL      = $TPL"

mkdir -p "$(dirname "$CSS")" "$(dirname "$JS")"

########################################
# 1) CSS: button / badge / toast / row #
########################################

cat > "$CSS" << 'CSS_EOF'
/* VSP_UI 2025 – Commercial polish layer
 * Không thay theme gốc, chỉ thêm lớp "enterprise" cho button / badge / toast.
 */

.vsp-btn,
button.vsp-btn {
  border-radius: 9999px;
  padding: 0.4rem 0.9rem;
  font-size: 0.85rem;
  font-weight: 600;
  border-width: 1px;
  border-style: solid;
  cursor: pointer;
  transition: all 120ms ease-out;
  display: inline-flex;
  align-items: center;
  gap: 0.4rem;
  white-space: nowrap;
}

/* PRIMARY – dùng cho action chính như Export HTML, Save */
.vsp-btn-primary,
button.vsp-btn-primary {
  background: linear-gradient(135deg, #0f766e, #22c55e);
  border-color: rgba(34, 197, 94, 0.8);
  color: #ecfdf5;
  box-shadow: 0 10px 25px rgba(16, 185, 129, 0.35);
}

.vsp-btn-primary:hover {
  transform: translateY(-1px);
  box-shadow: 0 14px 30px rgba(16, 185, 129, 0.45);
}

/* SECONDARY – dùng cho Export ZIP, Reload */
.vsp-btn-secondary,
button.vsp-btn-secondary {
  background: rgba(15, 23, 42, 0.8);
  border-color: rgba(148, 163, 184, 0.6);
  color: #e5e7eb;
}

.vsp-btn-secondary:hover {
  background: rgba(30, 64, 175, 0.9);
  border-color: rgba(129, 140, 248, 0.9);
}

/* GHOST – dùng cho nút phụ, ít quan trọng */
.vsp-btn-ghost,
button.vsp-btn-ghost {
  background: transparent;
  border-color: rgba(148, 163, 184, 0.25);
  color: #9ca3af;
}

.vsp-btn-ghost:hover {
  background: rgba(15, 23, 42, 0.7);
}

/* ICON nhỏ trong button */
.vsp-btn-icon {
  font-size: 0.9em;
  opacity: 0.9;
}

/* Badge base */
.vsp-badge {
  display: inline-flex;
  align-items: center;
  border-radius: 9999px;
  padding: 0.12rem 0.55rem;
  font-size: 0.7rem;
  font-weight: 600;
  letter-spacing: 0.03em;
  text-transform: uppercase;
}

/* Severity badge */
.vsp-badge-sev {
  border-width: 1px;
  border-style: solid;
}

/* 6-level DevSecOps */
.vsp-badge-sev-critical {
  color: #fee2e2;
  background: rgba(220, 38, 38, 0.18);
  border-color: rgba(248, 113, 113, 0.8);
}

.vsp-badge-sev-high {
  color: #ffedd5;
  background: rgba(249, 115, 22, 0.22);
  border-color: rgba(251, 146, 60, 0.95);
}

.vsp-badge-sev-medium {
  color: #fef9c3;
  background: rgba(202, 138, 4, 0.18);
  border-color: rgba(234, 179, 8, 0.9);
}

.vsp-badge-sev-low {
  color: #dcfce7;
  background: rgba(22, 163, 74, 0.1);
  border-color: rgba(34, 197, 94, 0.85);
}

.vsp-badge-sev-info {
  color: #dbeafe;
  background: rgba(37, 99, 235, 0.18);
  border-color: rgba(59, 130, 246, 0.85);
}

.vsp-badge-sev-trace {
  color: #e5e7eb;
  background: rgba(17, 24, 39, 0.8);
  border-color: rgba(75, 85, 99, 0.9);
}

/* Tool badge */
.vsp-badge-tool {
  color: #e5e7eb;
  background: rgba(31, 41, 55, 0.9);
  border-radius: 9999px;
  padding-inline: 0.5rem;
  font-size: 0.7rem;
  text-transform: uppercase;
  letter-spacing: 0.05em;
}

/* Hover row + selected run trong bảng Runs & Reports */
.vsp-table-hover tbody tr:hover {
  background: rgba(15, 23, 42, 0.75);
}

.vsp-run-selected {
  background: linear-gradient(90deg, rgba(56, 189, 248, 0.2), transparent);
}

/* Toast (notification) */
.vsp-toast-container {
  position: fixed;
  right: 1.5rem;
  bottom: 1.5rem;
  z-index: 9999;
  display: flex;
  flex-direction: column;
  gap: 0.5rem;
}

.vsp-toast {
  min-width: 220px;
  padding: 0.6rem 0.9rem;
  border-radius: 0.75rem;
  font-size: 0.8rem;
  display: flex;
  align-items: center;
  gap: 0.5rem;
  box-shadow: 0 18px 45px rgba(15, 23, 42, 0.85);
  border-width: 1px;
  border-style: solid;
  backdrop-filter: blur(12px);
  animation: vsp-toast-in 120ms ease-out;
}

.vsp-toast-info {
  background: rgba(15, 23, 42, 0.92);
  border-color: rgba(59, 130, 246, 0.8);
  color: #dbeafe;
}

.vsp-toast-success {
  background: rgba(6, 78, 59, 0.9);
  border-color: rgba(34, 197, 94, 0.9);
  color: #bbf7d0;
}

.vsp-toast-error {
  background: rgba(127, 29, 29, 0.95);
  border-color: rgba(248, 113, 113, 0.95);
  color: #fee2e2;
}

.vsp-toast-hide {
  opacity: 0;
  transform: translateY(4px);
  transition: all 150ms ease-in;
}

@keyframes vsp-toast-in {
  from {
    opacity: 0;
    transform: translateY(6px);
  }
  to {
    opacity: 1;
    transform: translateY(0);
  }
}
CSS_EOF

echo "[VSP_UI_COMM] Wrote CSS polish -> $CSS"

##################################
# 2) JS polish cho 3 tab:        #
#    Runs, Data Source, Settings #
##################################

cat > "$JS" << 'JS_EOF';
/**
 * VSP_UI 2025 – Commercial polish layer
 * - KHÔNG thay đổi logic fetch hiện tại.
 * - Chỉ "enhance" DOM sau khi dữ liệu đã render:
 *   + Badge severity / tool ở Data Source.
 *   + Row hover + selected ở Runs.
 *   + Toast khi Save Settings / Rules.
 */

(function () {
  const LOG_PREFIX = "[VSP_UI_COMMERCIAL]";

  function ready(fn) {
    if (document.readyState !== "loading") {
      fn();
    } else {
      document.addEventListener("DOMContentLoaded", fn);
    }
  }

  function getToastContainer() {
    let c = document.querySelector(".vsp-toast-container");
    if (!c) {
      c = document.createElement("div");
      c.className = "vsp-toast-container";
      document.body.appendChild(c);
    }
    return c;
  }

  function showToast(message, type) {
    type = type || "info";
    const c = getToastContainer();
    const toast = document.createElement("div");
    toast.className = "vsp-toast vsp-toast-" + type;
    toast.textContent = message;
    c.appendChild(toast);
    setTimeout(function () {
      toast.classList.add("vsp-toast-hide");
    }, 2200);
    setTimeout(function () {
      if (toast.parentNode) toast.parentNode.removeChild(toast);
    }, 2600);
  }

  /**
   * Runs & Reports:
   * - Thêm hover + selected row cho bảng runs.
   * - Nếu có panel detail với id="vsp-run-detail-box" và các span data-field
   *   thì fill thêm thông tin cơ bản.
   */
  function enhanceRunsTab() {
    const tbody = document.getElementById("vsp-runs-tbody");
    if (!tbody) {
      console.log(LOG_PREFIX, "Không thấy #vsp-runs-tbody – bỏ qua polish Runs.");
      return;
    }

    // Thêm class hover cho bảng nếu table cha chưa có
    const table = tbody.closest("table");
    if (table && !table.classList.contains("vsp-table-hover")) {
      table.classList.add("vsp-table-hover");
    }

    tbody.addEventListener("click", function (ev) {
      const tr = ev.target.closest("tr");
      if (!tr || !tbody.contains(tr)) return;

      Array.from(tbody.querySelectorAll("tr")).forEach(function (row) {
        row.classList.remove("vsp-run-selected");
      });
      tr.classList.add("vsp-run-selected");

      const detailBox = document.getElementById("vsp-run-detail-box");
      if (!detailBox) return;

      const cells = tr.children;
      const runId =
        tr.getAttribute("data-run-id") ||
        (cells[0] && cells[0].textContent.trim()) ||
        "-";

      const startedAt =
        tr.getAttribute("data-started-at") ||
        (cells[1] && cells[1].textContent.trim()) ||
        "-";

      const profile =
        tr.getAttribute("data-profile") ||
        (cells[2] && cells[2].textContent.trim()) ||
        "-";

      const status =
        tr.getAttribute("data-status") ||
        (cells[3] && cells[3].textContent.trim()) ||
        "-";

      const mapField = function (field, value) {
        const el = detailBox.querySelector('[data-field="' + field + '"]');
        if (el) el.textContent = value || "-";
      };

      mapField("run_id", runId);
      mapField("started_at", startedAt);
      mapField("profile", profile);
      mapField("status", status);
    });
  }

  /**
   * Data Source:
   * - Wrap Severity thành pill màu (6-level).
   * - Tool thành badge nhỏ.
   * - Path dài thì rút gọn + tooltip full path.
   *
   * Giả định cấu trúc cột:
   * [0] severity, [1] tool, [2] CWE, [3] rule, [4] path, [5] line, [6] message, [7] run
   */
  function enhanceDataSourceTab() {
    const tbody =
      document.getElementById("vsp-datasource-tbody") ||
      document.getElementById("vsp-ds-tbody");
    if (!tbody) {
      console.log(
        LOG_PREFIX,
        "Không thấy tbody Data Source (#vsp-datasource-tbody / #vsp-ds-tbody) – bỏ qua polish Data."
      );
      return;
    }

    const rows = Array.from(tbody.querySelectorAll("tr"));
    if (!rows.length) {
      console.log(LOG_PREFIX, "Data Source rỗng – không cần polish.");
      return;
    }

    rows.forEach(function (tr) {
      const cells = tr.children;
      if (!cells || !cells.length) return;

      const sevCell = cells[0];
      const toolCell = cells[1];
      const pathCell = cells[4];

      // Severity badge
      if (sevCell) {
        const raw = (sevCell.textContent || "").trim();
        if (raw) {
          const sev = raw.toUpperCase();
          const span = document.createElement("span");
          span.textContent = sev;
          const cls =
            "vsp-badge vsp-badge-sev vsp-badge-sev-" + sev.toLowerCase();
          span.className = cls;
          sevCell.textContent = "";
          sevCell.appendChild(span);
        }
      }

      // Tool badge
      if (toolCell) {
        const tool = (toolCell.textContent || "").trim();
        if (tool) {
          const span = document.createElement("span");
          span.textContent = tool;
          span.className = "vsp-badge vsp-badge-tool";
          toolCell.textContent = "";
          toolCell.appendChild(span);
        }
      }

      // Path short + tooltip
      if (pathCell) {
        const full = (pathCell.textContent || "").trim();
        if (full.length > 70) {
          const short = "…" + full.slice(-65);
          pathCell.textContent = short;
          pathCell.title = full;
        }
      }
    });
  }

  /**
   * Settings & Rules:
   * - Thêm toast khi click Save.
   * - Giả định có 2 nút:
   *   + id="vsp-settings-save"
   *   + id="vsp-rules-save"
   *   (nếu chưa có thì không làm gì).
   */
  function wireSettingsAndRulesToasts() {
    const settingsSave = document.getElementById("vsp-settings-save");
    if (settingsSave && !settingsSave.classList.contains("vsp-btn-primary")) {
      settingsSave.classList.add("vsp-btn-primary", "vsp-btn");
    }

    const rulesSave = document.getElementById("vsp-rules-save");
    if (rulesSave && !rulesSave.classList.contains("vsp-btn-primary")) {
      rulesSave.classList.add("vsp-btn-primary", "vsp-btn");
    }

    if (settingsSave) {
      settingsSave.addEventListener("click", function () {
        showToast("Đang lưu settings_v1.json ...", "info");
        setTimeout(function () {
          showToast("Settings đã được gửi lên server.", "success");
        }, 700);
      });
    }

    if (rulesSave) {
      rulesSave.addEventListener("click", function () {
        showToast("Đang lưu rule_overrides_v1.json ...", "info");
        setTimeout(function () {
          showToast("Rule overrides đã được gửi lên server.", "success");
        }, 700);
      });
    }
  }

  ready(function () {
    console.log(LOG_PREFIX, "Khởi tạo polish cho Runs / Data / Settings / Rules.");
    try {
      enhanceRunsTab();
    } catch (e) {
      console.error(LOG_PREFIX, "Lỗi enhanceRunsTab:", e);
    }
    try {
      enhanceDataSourceTab();
    } catch (e) {
      console.error(LOG_PREFIX, "Lỗi enhanceDataSourceTab:", e);
    }
    try {
      wireSettingsAndRulesToasts();
    } catch (e) {
      console.error(LOG_PREFIX, "Lỗi wireSettingsAndRulesToasts:", e);
    }
  });
})();
JS_EOF

echo "[VSP_UI_COMM] Wrote JS polish -> $JS"

#################################
# 3) Patch template: add CSS/JS #
#################################

if [ ! -f "$TPL" ]; then
  echo "[ERR] Không tìm thấy template: $TPL"
  exit 1
fi

python - "$UI_ROOT" << 'PY'
import sys, pathlib, shutil

ui_root = pathlib.Path(sys.argv[1])
tpl_path = ui_root / "templates" / "vsp_dashboard_2025.html"

original = tpl_path.read_text(encoding="utf-8")
txt = original
changed = False

if "vsp_ui_commercial_v1.css" not in txt:
    txt = txt.replace(
        "</head>",
        '  <link rel="stylesheet" href="/static/css/vsp_ui_commercial_v1.css">\n</head>',
        1,
    )
    changed = True
    print("[PATCH] Injected CSS link vào <head>.")

if "vsp_ui_commercial_polish_v1.js" not in txt:
    txt = txt.replace(
        "</body>",
        '  <script src="/static/js/vsp_ui_commercial_polish_v1.js"></script>\n</body>',
        1,
    )
    changed = True
    print("[PATCH] Injected JS polish trước </body>.")

if changed:
    backup = tpl_path.with_suffix(tpl_path.suffix + ".bak_comm_tabs")
    backup.write_text(original, encoding="utf-8")
    tpl_path.write_text(txt, encoding="utf-8")
    print("[PATCH] Template updated, backup ->", backup)
else:
    print("[PATCH] Template đã có CSS/JS polish, bỏ qua.")
PY

echo "[VSP_UI_COMM] DONE – nhớ refresh lại UI (Ctrl+F5)."
