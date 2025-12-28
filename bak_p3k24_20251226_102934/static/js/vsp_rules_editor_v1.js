(function () {
  console.log("[VSP_RULES_EDITOR] vsp_rules_editor_v1.js loaded (v4)");

  var WRAPPER_ID = "vsp-rules-editor-root";

  // ==== helper: show/hide editor theo tab ====
  function setEditorVisibility() {
    var root = document.getElementById(WRAPPER_ID);
    if (!root) return;
    if (location.hash === "#rules") {
      root.style.display = "";
    } else {
      root.style.display = "none";
    }
  }

  // ==== tìm đúng pane Rules ====
  function findRulesPane() {
    var pane =
      document.getElementById("vsp-tab-rules-main") ||
      document.querySelector("[data-vsp-pane='rules']") ||
      document.querySelector("#vsp-tab-rules") ||
      document.querySelector(".vsp-pane-rules");

    if (pane) {
      console.log("[VSP_RULES_EDITOR] Found rules pane (by id/class).");
      return pane;
    }

    // Fallback: block có text RULE OVERRIDES (chỉ chạy khi đang ở #rules)
    var nodes = Array.from(document.querySelectorAll("section, div, main"));
    var marker = nodes.find(function (el) {
      var t = (el.textContent || "").toUpperCase();
      return t.includes("RULE OVERRIDES") && !t.includes("RUN SCAN NOW");
    });

    if (marker) {
      pane =
        marker.closest(".vsp-pane") ||
        marker.closest("section") ||
        marker.closest("div");
      if (pane) {
        console.log("[VSP_RULES_EDITOR] Found rules pane via text marker.");
        return pane;
      }
    }

    console.warn("[VSP_RULES_EDITOR] Không thấy pane Rules.");
    return null;
  }

  async function fetchOverrides() {
    const resp = await fetch("/api/vsp/rule_overrides_ui_v1");
    if (!resp.ok) throw new Error("HTTP " + resp.status);
    return await resp.json();
  }

  async function saveOverrides(jsonText) {
    let obj;
    try {
      obj = JSON.parse(jsonText);
    } catch (e) {
      alert("JSON không hợp lệ: " + e.message);
      throw e;
    }
    const resp = await fetch("/api/vsp/rule_overrides_save_v1", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(obj),
    });
    const data = await resp.json();
    if (!resp.ok || !data.ok) {
      throw new Error(data.error || resp.statusText);
    }
    return data;
  }

  async function initEditor() {
    if (location.hash !== "#rules") {
      setEditorVisibility();
      return;
    }

    var pane = findRulesPane();
    if (!pane) return;

    // Nếu đã có wrapper thì chỉ bật visible rồi thoát
    var existing = document.getElementById(WRAPPER_ID);
    if (existing) {
      setEditorVisibility();
      return;
    }

    let data;
    try {
      data = await fetchOverrides();
    } catch (e) {
      console.error("[VSP_RULES_EDITOR] Lỗi fetch overrides:", e);
      return;
    }

    var items = (data && data.items) || data.overrides || [];

    var root = document.createElement("div");
    root.id = WRAPPER_ID;
    root.className = "vsp-grid vsp-grid-2";
    root.style.marginTop = "24px";
    root.style.gap = "24px";

    var left = document.createElement("div");
    left.className = "vsp-card";
    left.innerHTML = `
      <div class="vsp-card-title">Rule list / summary</div>
      <p class="vsp-card-subtitle">Tóm tắt overrides (severity mới, tool, scope,...)</p>
      <div class="vsp-table-wrapper" style="max-height:360px; overflow:auto;">
        <table class="vsp-table" id="vsp-rules-table">
          <thead>
            <tr>
              <th>#</th>
              <th>Rule ID / Query ID</th>
              <th>New severity</th>
              <th>Tool</th>
              <th>Note</th>
            </tr>
          </thead>
          <tbody></tbody>
        </table>
      </div>
    `;

    var right = document.createElement("div");
    right.className = "vsp-card";
    right.innerHTML = `
      <div class="vsp-card-title">Rule Overrides JSON</div>
      <p class="vsp-card-subtitle">Chỉnh JSON trực tiếp. Save sẽ ghi out/vsp_rule_overrides_v1.json</p>
      <textarea id="vsp-rules-json-editor" style="width:100%; min-height:260px; font-family:monospace; font-size:12px;"></textarea>
      <div style="margin-top:12px; display:flex; gap:8px;">
        <button id="vsp-rules-format" class="vsp-btn-secondary">Format JSON</button>
        <button id="vsp-rules-save" class="vsp-btn-primary">Save (apply)</button>
      </div>
      <p id="vsp-rules-status" style="margin-top:8px; font-size:12px; opacity:0.8;"></p>
    `;

    root.appendChild(left);
    root.appendChild(right);
    pane.appendChild(root);

    // Fill table
    var tbody = left.querySelector("tbody");
    if (tbody && Array.isArray(items)) {
      items.forEach(function (item, idx) {
        var tr = document.createElement("tr");
        var ruleId = item.rule_id || item.query_id || item.id || "";
        var sev = item.new_severity || item.severity || "";
        var tool = item.tool || item.engine || "";
        var note = item.note || item.reason || "";
        tr.innerHTML = `
          <td>${idx + 1}</td>
          <td>${ruleId}</td>
          <td>${sev}</td>
          <td>${tool}</td>
          <td>${note}</td>
        `;
        tbody.appendChild(tr);
      });
    }

    // JSON editor
    var editor = document.getElementById("vsp-rules-json-editor");
    var status = document.getElementById("vsp-rules-status");
    if (editor) {
      editor.value = JSON.stringify(data, null, 2);
    }

    var formatBtn = document.getElementById("vsp-rules-format");
    var saveBtn = document.getElementById("vsp-rules-save");

    if (formatBtn && editor) {
      formatBtn.addEventListener("click", function () {
        try {
          var obj = JSON.parse(editor.value);
          editor.value = JSON.stringify(obj, null, 2);
          status.textContent = "Đã format JSON.";
        } catch (e) {
          alert("JSON không hợp lệ: " + e.message);
        }
      });
    }

    if (saveBtn && editor) {
      saveBtn.addEventListener("click", async function () {
        saveBtn.disabled = true;
        saveBtn.textContent = "Saving...";
        status.textContent = "";
        try {
          var res = await saveOverrides(editor.value);
          status.textContent = "Đã lưu: " + res.path;
        } catch (e) {
          console.error(e);
          status.textContent = "Save failed: " + e.message;
          alert("Save failed: " + e.message);
        } finally {
          saveBtn.disabled = false;
          saveBtn.textContent = "Save (apply)";
        }
      });
    }

    setEditorVisibility();
  }

  // ==== wiring ====
  document.addEventListener("DOMContentLoaded", function () {
    setEditorVisibility();
    if (location.hash === "#rules") {
      setTimeout(initEditor, 200);
    }
  });

  window.addEventListener("hashchange", function () {
    setEditorVisibility();
    if (location.hash === "#rules") {
      setTimeout(initEditor, 200);
    }
  });
})();
