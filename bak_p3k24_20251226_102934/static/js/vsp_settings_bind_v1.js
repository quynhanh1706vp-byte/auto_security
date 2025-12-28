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

  async function loadSettings() {
    console.log("[VSP_SETTINGS] init loadSettings()");

    // Nếu tab 4 không có trong DOM thì thôi, tránh lỗi khi dùng template khác
    var profileEl = $("vsp-settings-profile-label");
    if (!profileEl) {
      console.log("[VSP_SETTINGS] Không thấy #vsp-settings-profile-label trong DOM, bỏ qua.");
      return;
    }

    try {
      var resp = await fetch("/api/vsp/settings/get", { credentials: "same-origin" });
      console.log("[VSP_SETTINGS] fetch /api/vsp/settings/get →", resp.status);
      if (!resp.ok) {
        throw new Error("HTTP " + resp.status);
      }

      var data = await resp.json();
      console.log("[VSP_SETTINGS] Loaded settings JSON:", data);

      // ==== Raw JSON preview ====
      var rawPre = $("vsp-settings-raw-json");
      if (rawPre) {
        try {
          rawPre.textContent = JSON.stringify(data, null, 2);
        } catch (e) {
          rawPre.textContent = String(e);
        }
      }

      var envPre = $("vsp-settings-env-json");
      if (envPre && data && data.env) {
        try {
          envPre.textContent = JSON.stringify(data.env, null, 2);
        } catch (e) {
          envPre.textContent = String(e);
        }
      }

      // ==== Profile / root_dir / security_score ====
      if (data && data.env) {
        if (data.env.profile && profileEl) {
          profileEl.textContent = data.env.profile;
        }
        var rootEl = $("vsp-settings-root-dir");
        if (rootEl && data.env.root_dir) {
          rootEl.textContent = data.env.root_dir;
        }
      }

      var scoreEl = $("vsp-settings-security-score");
      var score =
        (data && data.security_score !== undefined ? data.security_score : null) ||
        (data && data.env && data.env.security_score !== undefined ? data.env.security_score : null);

      if (scoreEl && score !== null && score !== undefined) {
        scoreEl.textContent = String(score);
      }

      // ==== Tools table ====
      if (data && data.tools) {
        var table = $("vsp-settings-tools-table");
        if (table) {
          var tbody = table.querySelector("tbody");
          if (tbody) {
            tbody.innerHTML = "";

            Object.entries(data.tools).forEach(function (entry) {
              var toolId = entry[0];
              var cfg = entry[1] || {};

              var label = cfg.label || cfg.name || "";
              var enabled =
                typeof cfg.enabled === "boolean"
                  ? (cfg.enabled ? "ON" : "OFF")
                  : "—";
              var notes =
                cfg.notes || cfg.comment || cfg.description || "";

              var tr = document.createElement("tr");
              tr.innerHTML =
                '<td><code>' + toolId + "</code></td>" +
                "<td>" + label + "</td>" +
                "<td>" + enabled + "</td>" +
                "<td>" + notes + "</td>";

              tbody.appendChild(tr);
            });

            if (!Object.keys(data.tools).length) {
              var trEmpty = document.createElement("tr");
              trEmpty.className = "vsp-settings-row-placeholder";
              trEmpty.innerHTML =
                '<td colspan="4"><span class="vsp-muted">' +
                "Không có tool nào trong cấu hình hiện tại." +
                "</span></td>";
              tbody.appendChild(trEmpty);
            }
          }
        }
      }
    } catch (err) {
      console.warn("[VSP_SETTINGS] Lỗi khi load /api/vsp/settings/get:", err);
    }
  }

  onReady(loadSettings);
})();
