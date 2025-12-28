#!/usr/bin/env bash
set -euo pipefail

UI="/home/test/Data/SECURITY_BUNDLE/ui"
APP="$UI/app.py"
TPL="$UI/templates/datasource.html"
JS="$UI/static/js/datasource_tool_rules.js"

echo "[i] UI = $UI"

cd "$UI"

# 1) Patch app.py – thêm RULES_PATH + 2 API /api/tool_rules
python3 - <<'PY'
import pathlib, textwrap, re

ui = pathlib.Path("/home/test/Data/SECURITY_BUNDLE/ui")
app = ui / "app.py"

data = app.read_text(encoding="utf-8")
orig = data

# Đảm bảo có RULES_PATH
if "RULES_PATH =" not in data:
    m = re.search(r"^ROOT\s*=\s*Path\(.*\)\s*$", data, flags=re.MULTILINE)
    if m:
        insert = m.group(0) + '\nRULES_PATH = ROOT / "tool_rules.json"'
        data = data[:m.start()] + insert + data[m.end():]
        print("[OK] Đã chèn RULES_PATH sau ROOT trong app.py")
    else:
        # fallback: thêm ở đầu file
        head = 'RULES_PATH = Path(__file__).resolve().parent.parent / "tool_rules.json"\n'
        data = head + data
        print("[WARN] Không tìm thấy ROOT, tạo RULES_PATH ở đầu file")

# Thêm 2 route nếu chưa có
if "api_get_tool_rules" not in data:
    block = textwrap.dedent('''

    @app.route("/api/tool_rules", methods=["GET"])
    def api_get_tool_rules():
        """Trả về danh sách rule cho từng tool"""
        if RULES_PATH.exists():
            try:
                data = json.loads(RULES_PATH.read_text(encoding="utf-8"))
            except Exception:
                data = []
        else:
            data = []

        if not isinstance(data, list):
            data = []

        return jsonify({
            "ok": True,
            "path": str(RULES_PATH),
            "rules": data,
        })


    @app.route("/api/tool_rules", methods=["POST"])
    def api_save_tool_rules():
        """Lưu danh sách rule cho từng tool"""
        payload = request.get_json(force=True, silent=True) or {}
        rules = payload.get("rules", [])

        if not isinstance(rules, list):
            return jsonify({"ok": False, "error": "rules must be a list"}), 400

        RULES_PATH.write_text(
            json.dumps(rules, indent=2, ensure_ascii=False),
            encoding="utf-8",
        )
        return jsonify({"ok": True, "saved": len(rules), "path": str(RULES_PATH)})
    ''')
    marker = 'if __name__ == "__main__":'
    idx = data.rfind(marker)
    if idx != -1:
        data = data[:idx] + block + "\n\n" + data[idx:]
    else:
        data = data + block
    print("[OK] Đã chèn block /api/tool_rules vào app.py")
else:
    print("[INFO] app.py đã có api_get_tool_rules, bỏ qua thêm route")

if data != orig:
    app.write_text(data, encoding="utf-8")
PY

# 2) Patch templates/datasource.html – thêm UI block + script include
python3 - <<'PY'
import pathlib, textwrap, re

ui = pathlib.Path("/home/test/Data/SECURITY_BUNDLE/ui")
tpl = ui / "templates" / "datasource.html"

html = tpl.read_text(encoding="utf-8")
orig = html

# Thêm section Tool rules nếu chưa có
if "Tool rules / Rule overrides" not in html:
    section = textwrap.dedent('''
    <!-- === Tool rules / Rule overrides (editable table) === -->
    <div class="sb-section" style="margin-top: 32px;">
      <div class="sb-section-header">
        <h2 class="sb-section-title">Tool rules / Rule overrides</h2>
        <p class="sb-section-subtitle">
          Quản lý rule cho từng tool: downgrade severity, bỏ qua false positive, thêm ghi chú.
          Dữ liệu sẽ được lưu vào <code>tool_rules.json</code> ở thư mục ROOT.
        </p>
      </div>

      <div class="sb-card">
        <div class="sb-card-header sb-card-header-flex">
          <div>
            <div class="sb-card-title">Danh sách rule theo tool</div>
            <div class="sb-card-subtitle">
              Mỗi dòng là một rule: chọn tool, pattern, action, severity mới và trạng thái bật/tắt.
            </div>
          </div>
          <div class="sb-card-actions">
            <button id="btn-add-rule" class="sb-btn sb-btn-secondary">+ Add rule</button>
            <button id="btn-reload-rules" class="sb-btn sb-btn-outline">Reload</button>
            <button id="btn-save-rules" class="sb-btn sb-btn-primary">Save</button>
          </div>
        </div>

        <div class="sb-card-body">
          <div id="tool-rules-path" class="sb-help-text" style="margin-bottom: 8px; font-size: 12px; opacity: 0.7;">
            Rules file: <code>tool_rules.json</code>
          </div>

          <div class="sb-table-wrapper">
            <table class="sb-table" id="tool-rules-table">
              <thead>
                <tr>
                  <th style="width: 120px;">Tool</th>
                  <th style="width: 180px;">Rule ID / Pattern</th>
                  <th style="width: 120px;">Action</th>
                  <th style="width: 120px;">New severity</th>
                  <th style="width: 80px;">Enabled</th>
                  <th>Note</th>
                  <th style="width: 40px;"></th>
                </tr>
              </thead>
              <tbody id="tool-rules-body">
                <!-- rows sẽ được JS fill -->
              </tbody>
            </table>
          </div>

          <div class="sb-help-text" style="margin-top: 8px; font-size: 12px; opacity: 0.8;">
            Gợi ý:
            <ul style="margin-top: 4px; padding-left: 18px;">
              <li><b>Tool</b>: tên tool, ví dụ <code>semgrep</code>, <code>bandit</code>, <code>trivy-fs</code>, <code>gitleaks</code>, <code>codeql</code>...</li>
              <li><b>Rule ID / Pattern</b>: mã rule hoặc pattern bạn dùng để match (ví dụ rule_id, id, code, hoặc substring trong message).</li>
              <li><b>Action</b>:
                <code>downgrade</code>, <code>upgrade</code>, <code>ignore</code>, <code>tag</code> (tuỳ bạn dùng ở phase unify).</li>
              <li><b>New severity</b>: critical / high / medium / low / info (nếu action liên quan severity).</li>
            </ul>
          </div>
        </div>
      </div>
    </div>
    ''')
    m = re.search(r"</main>", html, flags=re.IGNORECASE)
    if m:
        html = html[:m.start()] + section + "\n" + html[m.start():]
    else:
        html = html + section
    print("[OK] Đã chèn section Tool rules vào datasource.html")
else:
    print("[INFO] Section Tool rules đã tồn tại, bỏ qua")

# Thêm script include datasource_tool_rules.js nếu chưa có
script_line = "{{ url_for('static', filename='js/datasource_tool_rules.js') }}"
if script_line not in html:
    tag = f'    <script src="{script_line}?v=20251125"></script>'
    m = re.search(r"js/datasource_summary_tables\.js[^\"']*", html)
    if m:
        insert_pos = html.find("\n", m.end())
        if insert_pos == -1:
            insert_pos = m.end()
        html = html[:insert_pos] + "\n" + tag + html[insert_pos:]
        print("[OK] Đã chèn script sau datasource_summary_tables.js")
    else:
        m2 = re.search(r"</body>", html, flags=re.IGNORECASE)
        if m2:
            html = html[:m2.start()] + tag + "\n" + html[m2.start():]
        else:
            html = html + "\n" + tag + "\n"
        print("[OK] Đã chèn script datasource_tool_rules.js vào cuối template")
else:
    print("[INFO] Script datasource_tool_rules.js đã tồn tại")

if html != orig:
    tpl.write_text(html, encoding="utf-8")
PY

# 3) Tạo static/js/datasource_tool_rules.js
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
      const resp = await fetch("/api/tool_rules");
      if (!resp.ok) throw new Error("HTTP " + resp.status);
      const data = await resp.json();

      bodyEl.innerHTML = "";

      if (data.path && pathEl) {
        pathEl.innerHTML = "Rules file: <code>" + data.path + "</code>";
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
      const resp = await fetch("/api/tool_rules", {
        method: "POST",
        headers: {
          "Content-Type": "application/json"
        },
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

echo "[DONE] patch_datasource_tool_rules.sh hoàn thành."
