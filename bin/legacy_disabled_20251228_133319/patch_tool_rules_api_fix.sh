#!/usr/bin/env bash
set -euo pipefail

UI="/home/test/Data/SECURITY_BUNDLE/ui"
APP="$UI/app.py"
JS="$UI/static/js/datasource_tool_rules.js"

echo "[i] UI = $UI"

########################################
# 1) Ghi lại JS: dùng API_URL = /api/tool_rules
########################################

cat > "$JS" <<'JS'
(function () {
  const bodyEl = document.getElementById("tool-rules-body");
  if (!bodyEl) {
    return; // không có bảng -> không chạy gì
  }

  const btnAdd = document.getElementById("btn-add-rule");
  const btnSave = document.getElementById("btn-save-rules");
  const btnReload = document.getElementById("btn-reload-rules");
  const pathEl = document.getElementById("tool-rules-path");

  const API_URL = "/api/tool_rules";

  const TOOL_OPTIONS = [
    "",
    "semgrep",
    "bandit",
    "trivy-fs",
    "trivy-misconfig",
    "trivy-secret",
    "syft",
    "grype",
    "gitleaks",
    "codeql",
    "kics"
  ];

  const ACTION_OPTIONS = [
    "",
    "ignore",
    "downgrade",
    "upgrade",
    "tag"
  ];

  const SEVERITY_OPTIONS = [
    "",
    "critical",
    "high",
    "medium",
    "low",
    "info"
  ];

  function createSelect(options, value) {
    const sel = document.createElement("select");
    sel.className = "sb-input sb-input-sm";
    options.forEach(function (opt) {
      const o = document.createElement("option");
      o.value = opt;
      o.textContent = opt || "--";
      if (opt === value) {
        o.selected = true;
      }
      sel.appendChild(o);
    });
    return sel;
  }

  function addRuleRow(rule) {
    const tr = document.createElement("tr");

    const tdTool = document.createElement("td");
    tdTool.appendChild(createSelect(TOOL_OPTIONS, rule.tool || ""));
    tr.appendChild(tdTool);

    const tdRuleId = document.createElement("td");
    const inpRuleId = document.createElement("input");
    inpRuleId.type = "text";
    inpRuleId.className = "sb-input sb-input-sm";
    inpRuleId.value = rule.rule_id || rule.pattern || "";
    inpRuleId.placeholder = "rule id / pattern";
    tdRuleId.appendChild(inpRuleId);
    tr.appendChild(tdRuleId);

    const tdAction = document.createElement("td");
    tdAction.appendChild(createSelect(ACTION_OPTIONS, rule.action || ""));
    tr.appendChild(tdAction);

    const tdSeverity = document.createElement("td");
    tdSeverity.appendChild(createSelect(SEVERITY_OPTIONS, rule.new_severity || ""));
    tr.appendChild(tdSeverity);

    const tdEnabled = document.createElement("td");
    const chk = document.createElement("input");
    chk.type = "checkbox";
    chk.checked = rule.enabled !== false;
    tdEnabled.appendChild(chk);
    tr.appendChild(tdEnabled);

    const tdNote = document.createElement("td");
    const inpNote = document.createElement("input");
    inpNote.type = "text";
    inpNote.className = "sb-input sb-input-sm";
    inpNote.value = rule.note || "";
    inpNote.placeholder = "Note / lý do override (optional)";
    tdNote.appendChild(inpNote);
    tr.appendChild(tdNote);

    const tdDel = document.createElement("td");
    const btnDel = document.createElement("button");
    btnDel.type = "button";
    btnDel.className = "sb-btn sb-btn-icon sb-btn-ghost";
    btnDel.textContent = "×";
    btnDel.title = "Delete rule";
    btnDel.addEventListener("click", function () {
      tr.remove();
    });
    tdDel.appendChild(btnDel);
    tr.appendChild(tdDel);

    bodyEl.appendChild(tr);
  }

  function collectRules() {
    const rows = Array.from(bodyEl.querySelectorAll("tr"));
    return rows.map(function (tr) {
      const tds = tr.querySelectorAll("td");

      const toolSel = tds[0].querySelector("select");
      const ruleInput = tds[1].querySelector("input");
      const actionSel = tds[2].querySelector("select");
      const sevSel = tds[3].querySelector("select");
      const enabledChk = tds[4].querySelector("input[type='checkbox']");
      const noteInput = tds[5].querySelector("input");

      return {
        tool: toolSel.value || "",
        rule_id: (ruleInput.value || "").trim(),
        action: actionSel.value || "",
        new_severity: sevSel.value || "",
        enabled: !!enabledChk.checked,
        note: (noteInput.value || "").trim()
      };
    }).filter(function (r) {
      return r.tool || r.rule_id || r.action || r.new_severity || r.note;
    });
  }

  async function loadRules() {
    try {
      const resp = await fetch(API_URL);
      if (!resp.ok) throw new Error("HTTP " + resp.status);
      const data = await resp.json();

      bodyEl.innerHTML = "";

      if (data.path && pathEl) {
        pathEl.innerHTML = 'Rules file: <code>' + data.path + "</code>";
      }

      const rules = data.rules || [];
      if (!rules.length) {
        addRuleRow({});
      } else {
        rules.forEach(function (r) {
          addRuleRow(r);
        });
      }
    } catch (err) {
      console.error("Load tool_rules failed:", err);
      alert("Không load được tool_rules: " + err);
    }
  }

  async function saveRules() {
    const rules = collectRules();
    try {
      const resp = await fetch(API_URL, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ rules: rules })
      });
      const data = await resp.json();
      if (!resp.ok || !data.ok) {
        throw new Error(data.error || ("HTTP " + resp.status));
      }
      alert("Đã lưu " + (data.saved || rules.length) + " rule(s) vào " + (data.path || "tool_rules.json"));
    } catch (err) {
      console.error("Save tool_rules failed:", err);
      alert("Không lưu được tool_rules: " + err);
    }
  }

  if (btnAdd) {
    btnAdd.addEventListener("click", function () {
      addRuleRow({});
    });
  }

  if (btnSave) {
    btnSave.addEventListener("click", function () {
      saveRules();
    });
  }

  if (btnReload) {
    btnReload.addEventListener("click", function () {
      loadRules();
    });
  }

  document.addEventListener("DOMContentLoaded", function () {
    loadRules();
  });
})();
JS

echo "[OK] Đã ghi lại $JS với API_URL = /api/tool_rules"

########################################
# 2) Thêm route /api/tool_rules vào app.py nếu chưa có
########################################
python3 - <<'PY'
from pathlib import Path
import re

app_path = Path("/home/test/Data/SECURITY_BUNDLE/ui/app.py")
text = app_path.read_text(encoding="utf-8")
orig = text

if '@app.route("/api/tool_rules"' in text:
    print("[INFO] app.py đã có route /api/tool_rules, không chèn thêm.")
else:
    block = '''

# === Tool rules API (GET/POST) ===
@app.route("/api/tool_rules", methods=["GET"])
def api_tool_rules_get():
    from pathlib import Path as _Path
    import json
    from flask import jsonify
    rules_path = _Path(__file__).resolve().parent.parent / "tool_rules.json"
    if rules_path.exists():
        try:
            data = json.loads(rules_path.read_text(encoding="utf-8"))
        except Exception:
            data = []
    else:
        data = []
    if not isinstance(data, list):
        data = []
    return jsonify({"ok": True, "path": str(rules_path), "rules": data})


@app.route("/api/tool_rules", methods=["POST"])
def api_tool_rules_post():
    from pathlib import Path as _Path
    import json
    from flask import request, jsonify
    rules_path = _Path(__file__).resolve().parent.parent / "tool_rules.json"
    payload = request.get_json(force=True, silent=True) or {}
    rules = payload.get("rules", [])
    if not isinstance(rules, list):
        return jsonify({"ok": False, "error": "rules must be a list"}), 400
    rules_path.write_text(
        json.dumps(rules, indent=2, ensure_ascii=False),
        encoding="utf-8",
    )
    return jsonify({"ok": True, "saved": len(rules), "path": str(rules_path)})
'''

    m = re.search(r"if __name__ == ['\\\"]__main__['\\\"]:", text)
    if m:
        pos = m.start()
        text = text[:pos] + block + "\n" + text[pos:]
        print("[OK] Đã chèn block /api/tool_rules trước if __name__ == '__main__':")
    else:
        text = text.rstrip() + block + "\n"
        print("[WARN] Không thấy if __name__ == '__main__', append block ở cuối file.")

    app_path.write_text(text, encoding="utf-8")

PY

# 3) Kiểm tra syntax app.py
python3 -m py_compile "$APP" && echo "[OK] app.py compile ok"

echo "[DONE] patch_tool_rules_api_fix.sh hoàn thành."
