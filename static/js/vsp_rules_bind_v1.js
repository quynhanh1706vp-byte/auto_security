(function () {
  function onReady(fn) {
    if (document.readyState === "loading") {
      document.addEventListener("DOMContentLoaded", fn);
    } else {
      fn();
    }
  }

  function $(id) {
    return document.getElementById(id);
  }

  async function loadRuleOverrides() {
    console.log("[VSP_RULES] init loadRuleOverrides()");

    var table = $("vsp-rules-table");
    if (!table) {
      console.log("[VSP_RULES] Không thấy #vsp-rules-table trong DOM, bỏ qua.");
      return;
    }

    var tbody = table.querySelector("tbody");
    if (!tbody) return;

    var url = "/api/vsp/rule_overrides/get";

    try {
      var resp = await fetch(url, { credentials: "same-origin" });
      console.log("[VSP_RULES] fetch " + url + " ->", resp.status);

      if (!resp.ok) {
        console.warn("[VSP_RULES] Backend rule overrides lỗi HTTP:", resp.status);
        return;
      }

      var data = await resp.json();
      console.log("[VSP_RULES] Loaded overrides JSON:", data);

      var items = data.items || [];

      // Bảng rules
      tbody.innerHTML = "";
      if (!Array.isArray(items) || !items.length) {
        var trEmpty = document.createElement("tr");
        trEmpty.className = "vsp-rules-row-placeholder";
        trEmpty.innerHTML =
          '<td colspan="5"><span class="vsp-muted">' +
          "Không có rule override nào trong cấu hình hiện tại." +
          "</span></td>";
        tbody.appendChild(trEmpty);
      } else {
        items.forEach(function (r) {
          var tr = document.createElement("tr");
          var ruleId = r.rule_id || r.id || "";
          var tool = r.tool || "";
          var match = r.match || r.when || "";
          var action = r.action || r.effect || "";
          var notes = r.notes || r.comment || "";

          tr.innerHTML =
            "<td>" + ruleId + "</td>" +
            "<td>" + tool + "</td>" +
            "<td>" + match + "</td>" +
            "<td>" + action + "</td>" +
            "<td>" + notes + "</td>";
          tbody.appendChild(tr);
        });
      }

      // KPI
      var total = (typeof data.total === "number") ? data.total : items.length;
      var active = (typeof data.active === "number") ? data.active : items.filter(function (r) {
        return r.enabled !== false && r.disabled !== true;
      }).length;
      var disabled = (typeof data.disabled === "number") ? data.disabled : (total - active);

      if ($("vsp-rules-total")) $("vsp-rules-total").textContent = String(total);
      if ($("vsp-rules-active")) $("vsp-rules-active").textContent = String(active);
      if ($("vsp-rules-disabled")) $("vsp-rules-disabled").textContent = String(disabled);

      // Profile / config path
      if ($("vsp-rules-profile-label") && data.profile) {
        $("vsp-rules-profile-label").textContent = data.profile;
      }
      if ($("vsp-rules-config-path") && data.config_path) {
        $("vsp-rules-config-path").textContent = data.config_path;
      }

      // raw JSON preview
      if ($("vsp-rules-raw-json")) {
        var raw = data.raw || data;
        $("vsp-rules-raw-json").textContent = JSON.stringify(raw, null, 2);
      }
    } catch (err) {
      console.warn("[VSP_RULES] Lỗi khi load rule overrides:", err);
    }
  }

  onReady(loadRuleOverrides);
})();
