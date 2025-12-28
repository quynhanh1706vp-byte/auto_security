(function () {
  if (!window.VSP) window.VSP = {};

  function $(id) { return document.getElementById(id); }

  function setStatus(text, badgeClass) {
    var box = $("vsp-settings-run-status");
    if (!box) return;
    box.innerHTML = '';

    var badge = document.createElement("span");
    badge.className = "vsp-badge " + (badgeClass || "");
    badge.textContent = text;

    box.appendChild(badge);
  }

  async function fetchStatus() {
    try {
      var res = await fetch("/api/vsp/run_scan_status_v2");
      if (!res.ok) {
        setStatus("STATUS: API ERROR", "vsp-badge-warn");
        return;
      }
      var data = await res.json();
      if (!data.ok) {
        setStatus("STATUS: ERROR", "vsp-badge-warn");
        return;
      }

      var status = data.status || "IDLE";
      var started = data.started_run_id || "-";
      var done = data.last_done_run_id || "-";

      var box = $("vsp-settings-run-status");
      if (!box) return;

      var badgeClass = "";
      if (status === "IN_PROGRESS") badgeClass = "vsp-badge-info";
      else if (status === "DONE") badgeClass = "vsp-badge-ok";
      else badgeClass = "vsp-badge-muted";

      box.innerHTML = "";
      var title = document.createElement("div");
      title.className = "vsp-settings-run-status-title";
      title.textContent = "Run scan status";

      var badge = document.createElement("span");
      badge.className = "vsp-badge " + badgeClass;
      badge.textContent = status;

      var meta = document.createElement("div");
      meta.className = "vsp-settings-run-status-meta";
      meta.innerHTML =
        "<span>Started RUN: <code>" + started + "</code></span>" +
        "<span>Last DONE: <code>" + done + "</code></span>";

      box.appendChild(title);
      box.appendChild(badge);
      box.appendChild(meta);
    } catch (e) {
      console.error("VSP Settings – fetchStatus error:", e);
      setStatus("STATUS: JS ERROR", "vsp-badge-warn");
    }
  }

  async function handleRunClick() {
    var srcInput = $("vsp-settings-src");
    var profileSel = $("vsp-settings-profile");
    var src = (srcInput && srcInput.value) || "/home/test/Data/SECURITY_BUNDLE";
    var profile = (profileSel && profileSel.value) || "EXT+";

    setStatus("STARTING…", "vsp-badge-info");

    try {
      var res = await fetch("/api/vsp/run_scan", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          src: src,
          profile: profile
        })
      });
      var data = await res.json().catch(function () { return {}; });

      if (!res.ok || !data.ok) {
        console.error("VSP Settings – run_scan error:", data);
        setStatus("START FAILED", "vsp-badge-warn");
        return;
      }

      setStatus("IN PROGRESS…", "vsp-badge-info");
      // Gọi luôn status để update started_run_id / last_done_run_id
      setTimeout(fetchStatus, 1500);
    } catch (e) {
      console.error("VSP Settings – run_scan JS error:", e);
      setStatus("JS ERROR", "vsp-badge-warn");
    }
  }

  function initSettingsRunBlock() {
    var btn = $("vsp-settings-run-btn");
    if (btn && !btn._vspBound) {
      btn._vspBound = true;
      btn.addEventListener("click", handleRunClick);
    }

    var refresh = $("vsp-settings-run-refresh");
    if (refresh && !refresh._vspBound) {
      refresh._vspBound = true;
      refresh.addEventListener("click", function () {
        setStatus("REFRESH…", "vsp-badge-muted");
        fetchStatus();
      });
    }

    // Load status lần đầu khi mở trang
    fetchStatus();
  }

  // Cho main JS gọi lại khi switch tab (nếu cần)
  window.VSP.initSettingsRunBlock = initSettingsRunBlock;

  document.addEventListener("DOMContentLoaded", function () {
    initSettingsRunBlock();
  });
})();
