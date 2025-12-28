(function () {
  console.log("[VSP_SETTINGS] vsp_settings_advanced_v1.js loaded (CLEAN v3)");

  var injected = false;
  var WRAPPER_ID = "vsp-settings-run-dast-wrapper";

  function showToast(msg) {
    alert(msg); // toast later
  }

  function findSettingsPane() {
    var pane =
      document.getElementById("vsp-tab-settings-main") ||
      document.querySelector("[data-vsp-pane='settings']") ||
      document.querySelector("#vsp-tab-settings") ||
      document.querySelector(".vsp-pane-settings");

    if (pane) {
      console.log("[VSP_SETTINGS] Found settings pane (by id/class).");
      return pane;
    }

    // fallback nhẹ theo text (chỉ dùng lúc đang ở tab Settings)
    var all = Array.from(document.querySelectorAll("section,div,main"));
    var marker = all.find(function (el) {
      var t = (el.textContent || "").toUpperCase();
      return t.includes("SETTINGS") && t.includes("SETTINGS_UI_V1");
    });
    if (marker) {
      pane = marker.closest(".vsp-pane") || marker.closest("section") || marker.closest("div");
      if (pane) {
        console.log("[VSP_SETTINGS] Found settings pane via text marker.");
        return pane;
      }
    }

    console.warn("[VSP_SETTINGS] Chưa tìm được settings pane – sẽ thử lại.");
    return null;
  }

  function setWrapperVisibility() {
    var wrapper = document.getElementById(WRAPPER_ID);
    if (!wrapper) return;
    if (location.hash === "#settings") {
      wrapper.style.display = "";
    } else {
      wrapper.style.display = "none";
    }
  }

  async function callApiRun(target, profile) {
    const resp = await fetch("/api/vsp/run", {
      method: "POST",
      headers: {"Content-Type": "application/json"},
      body: JSON.stringify({
        mode: "local",
        profile: profile || "FULL_EXT",
        target_type: "path",
        target: target
      })
    });
    const data = await resp.json();
    if (!resp.ok || !data.ok) {
      throw new Error(data.error || resp.statusText);
    }
    return data;
  }

  async function callApiDast(url) {
    const resp = await fetch("/api/vsp/dast/scan", {
      method: "POST",
      headers: {"Content-Type": "application/json"},
      body: JSON.stringify({url: url})
    });
    const data = await resp.json();
    if (!resp.ok || !data.ok) {
      throw new Error(data.error || resp.statusText);
    }
    return data;
  }

  function injectSettingsExtras() {
    if (injected) return;
    if (location.hash !== "#settings") return;

    var pane = findSettingsPane();
    if (!pane) return;

    if (document.getElementById(WRAPPER_ID)) {
      injected = true;
      setWrapperVisibility();
      return;
    }

    injected = true;
// VSP_SETTINGS_DISABLE_RUNDAST_V1
return;
    console.log("[VSP_SETTINGS] Injecting RUN/DAST block into Settings pane.");

    const wrapper = document.createElement("div");
    wrapper.id = WRAPPER_ID;
    wrapper.innerHTML = `
      <div class="vsp-grid vsp-grid-2" style="margin-top:24px; gap:24px;">
        <div class="vsp-card">
          <div class="vsp-card-title">RUN SCAN NOW (LOCAL)</div>
          <div class="vsp-card-subtitle">Gọi /api/vsp/run → run_vsp_full_ext.sh hoặc VSP_CI_OUTER</div>
          <div class="vsp-form-row">
            <label>Target path</label>
            <input id="vsp-settings-target-path" type="text" placeholder="/path/to/project" style="width:100%;">
          </div>
          <div class="vsp-form-row" style="margin-top:8px;">
            <label>Profile</label>
            <select id="vsp-settings-profile">
              <option value="FULL_EXT">FULL_EXT</option>
              <option value="QUICK">QUICK</option>
            </select>
          </div>
          <div style="margin-top:12px;">
            <button id="vsp-settings-run-local" class="vsp-btn-primary">Run scan now (LOCAL)</button>
          </div>
          <p style="margin-top:8px; font-size:12px; opacity:0.7;">
            Nút này chỉ trigger RUN; trạng thái & gate xem trong tab Dashboard / Runs & Reports.
          </p>
        </div>

        <div class="vsp-card">
          <div class="vsp-card-title">DAST – Scan URL/Domain</div>
          <div class="vsp-card-subtitle">Gọi /api/vsp/dast/scan (engine ZAP/Nessus… tùy cấu hình)</div>
          <div class="vsp-form-row">
            <label>Target URL</label>
            <input id="vsp-dast-url" type="text" placeholder="https://example.com" style="width:100%;">
          </div>
          <div style="margin-top:12px;">
            <button id="vsp-dast-start" class="vsp-btn-primary">Start DAST (stub/real)</button>
          </div>
          <p style="margin-top:8px; font-size:12px; opacity:0.7;">
            Đây là DAST engine riêng (ZAP/Nessus/...),
            không phải engine AATE/ANY-URL UI test.
          </p>
        </div>
      </div>
    `;
    pane.appendChild(wrapper);
    setWrapperVisibility();

    const runBtn = document.getElementById("vsp-settings-run-local");
    const targetInput = document.getElementById("vsp-settings-target-path");
    const profileSelect = document.getElementById("vsp-settings-profile");
    const dastBtn = document.getElementById("vsp-dast-start");
    const dastUrlInput = document.getElementById("vsp-dast-url");

    if (runBtn) {
      runBtn.addEventListener("click", async function () {
        const target = (targetInput && targetInput.value.trim()) || "";
        const profile = profileSelect ? profileSelect.value : "FULL_EXT";
        if (!target) {
          showToast("Bạn chưa nhập target path.");
          return;
        }
        runBtn.disabled = true;
        runBtn.innerText = "Running...";
        try {
          const data = await callApiRun(target, profile);
          showToast("Đã gửi RUN: RUN_ID=" + data.run_id);
        } catch (err) {
          console.error(err);
          showToast("RUN thất bại: " + err.message);
        } finally {
          runBtn.disabled = false;
          runBtn.innerText = "Run scan now (LOCAL)";
        }
      });
    }

    if (dastBtn) {
      dastBtn.addEventListener("click", async function () {
        const url = (dastUrlInput && dastUrlInput.value.trim()) || "";
        if (!url) {
          showToast("Bạn chưa nhập URL DAST.");
          return;
        }
        dastBtn.disabled = true;
        dastBtn.innerText = "Starting...";
        try {
          const data = await callApiDast(url);
          showToast("Đã gửi DAST: RUN_ID=" + data.run_id);
        } catch (err) {
          console.error(err);
          showToast("DAST thất bại: " + err.message);
        } finally {
          dastBtn.disabled = false;
          dastBtn.innerText = "Start DAST (stub/real)";
        }
      });
    }
  }

  function scheduleInjectOnSettings() {
    // chỉ chạy khi đang ở tab settings
    if (location.hash !== "#settings") {
      setWrapperVisibility();
      return;
    }
    var attempts = 0;
    var timer = setInterval(function () {
      if (location.hash !== "#settings") {
        clearInterval(timer);
        setWrapperVisibility();
        return;
      }
      attempts += 1;
      injectSettingsExtras();
      setWrapperVisibility();
      if (injected || attempts >= 20) {
        clearInterval(timer);
      }
    }, 100);
  }

  document.addEventListener("DOMContentLoaded", function () {
    scheduleInjectOnSettings();
  });

  window.addEventListener("hashchange", function () {
    scheduleInjectOnSettings();
  });
})();
