#!/usr/bin/env bash
set -euo pipefail

APP="/home/test/Data/SECURITY_BUNDLE/ui/app.py"
JS="/home/test/Data/SECURITY_BUNDLE/ui/static/js/datasource_tool_rules.js"

echo "[i] APP = $APP"

python3 - <<'PY'
from pathlib import Path
import re

app_path = Path("/home/test/Data/SECURITY_BUNDLE/ui/app.py")
text = app_path.read_text(encoding="utf-8")
orig = text

# 1) Xoá tất cả block /api/tool_rules và /api/tool_rules_v2 cũ
patterns = [
    r'\n@app\.route\("/api/tool_rules_v2"[\s\S]*?(?=\n@app\.route|\nif __name__ ==|$)',
    r'\n@app\.route\("/api/tool_rules"[\s\S]*?(?=\n@app\.route|\nif __name__ ==|$)',
]

for pat in patterns:
    new_text, n = re.subn(pat, "\n", text)
    if n:
        print(f"[OK] Removed {n} old block(s) matching {pat}")
    text = new_text

# 2) Thêm block API mới, an toàn
block = '''

# === Tool rules API (reset clean) ===
@app.route("/api/tool_rules", methods=["GET", "POST"])
def api_tool_rules():
    from pathlib import Path as _Path
    import json
    from flask import request, jsonify

    rules_path = _Path(__file__).resolve().parent.parent / "tool_rules.json"

    if request.method == "GET":
        # GET luôn trả 200, kể cả khi có lỗi -> tránh HTTP 500
        try:
            if rules_path.exists():
                raw = rules_path.read_text(encoding="utf-8")
                data = json.loads(raw) if raw.strip() else []
            else:
                data = []
        except Exception as e:
            # Lỗi đọc / parse: trả list rỗng + thông tin lỗi, nhưng HTTP 200
            return jsonify({
                "ok": False,
                "error": "load_failed: " + str(e),
                "path": str(rules_path),
                "rules": []
            }), 200

        if not isinstance(data, list):
            data = []

        return jsonify({
            "ok": True,
            "path": str(rules_path),
            "rules": data
        }), 200

    # POST: lưu rules
    payload = request.get_json(silent=True) or {}
    rules = payload.get("rules", [])
    if not isinstance(rules, list):
        return jsonify({
            "ok": False,
            "error": "rules must be a list"
        }), 400

    try:
        rules_path.write_text(
            json.dumps(rules, indent=2, ensure_ascii=False),
            encoding="utf-8",
        )
    except Exception as e:
        return jsonify({
            "ok": False,
            "error": "save_failed: " + str(e),
            "path": str(rules_path)
        }), 200

    return jsonify({
        "ok": True,
        "path": str(rules_path),
        "saved": len(rules)
    }), 200
'''

# chèn block mới trước if __name__ == '__main__'
m = re.search(r"if __name__ == ['\\\"]__main__['\\\"]:", text)
if m:
    pos = m.start()
    text = text[:pos] + block + "\n" + text[pos:]
    print("[OK] Inserted new api_tool_rules() before main block.")
else:
    text = text.rstrip() + block + "\n"
    print("[WARN] No main block found, appended api_tool_rules() at end of file.")

if text != orig:
    app_path.write_text(text, encoding="utf-8")
PY

# 3) Ghi lại JS cho chắc: luôn dùng /api/tool_rules
cat > "$JS" <<'JS'
(function () {
  const bodyEl = document.getElementById("tool-rules-body");
  if (!bodyEl) {
    return;
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

  const ACTION_OPTIONS = ["", "ignore", "downgrade", "upgrade", "tag"];
  const SEVERITY_OPTIONS = ["", "critical", "high", "medium", "low", "info"];

  function createSelect(options, value) {
    const sel = document.createElement("select");
    sel.className = "sb-input sb-input-sm";
    options.forEach(function (opt) {
      const o = document.createElement("option");
      o.value = opt;
      o.textContent = opt || "--";
      if (opt === value) o.selected = true;
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
    return rows
      .map(function (tr) {
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
      })
      .filter(function (r) {
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
        rules.forEach(addRuleRow);
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
        throw new Error(data.error || "HTTP " + resp.status);
      }
      alert(
        "Đã lưu " +
          (data.saved || rules.length) +
          " rule(s) vào " +
          (data.path || "tool_rules.json")
      );
    } catch (err) {
      console.error("Save tool_rules failed:", err);
      alert("Không lưu được tool_rules: " + err);
    }
  }

  if (btnAdd) btnAdd.addEventListener("click", function () { addRuleRow({}); });
  if (btnSave) btnSave.addEventListener("click", function () { saveRules(); });
  if (btnReload) btnReload.addEventListener("click", function () { loadRules(); });

  document.addEventListener("DOMContentLoaded", function () {
    loadRules();
  });
})();
JS

echo "[OK] Đã ghi lại JS datasource_tool_rules.js"

# 4) Kiểm tra syntax app.py
python3 -m py_compile "$APP" && echo "[OK] app.py compile ok"

echo "[DONE] patch_tool_rules_api_reset.sh hoàn thành."
