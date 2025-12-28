/**
 * JS trigger FULL SCAN from UI.
 */

(function () {
  console.log("[VSP_RUN_FULL] vsp_run_full_scan_v1.js loaded.");

  var btn = document.getElementById("vsp-btn-run-full-scan");
  if (!btn) {
    console.warn("[VSP_RUN_FULL] Button #vsp-btn-run-full-scan not found");
    return;
  }

  btn.addEventListener("click", function (e) {
    e.preventDefault();

    var payload = {
      profile: "FULL_EXT",
      source_root: null,
      target_url: null
    };

    fetch("/api/vsp/run_full_scan", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(payload)
    })
      .then(function (res) {
        if (!res.ok) throw new Error("HTTP " + res.status);
        return res.json();
      })
      .then(function (data) {
        console.log("[VSP_RUN_FULL] Scan started:", data);
        alert("FULL SCAN STARTED\nPID: " + data.pid + "\nCMD: " + data.cmd);
      })
      .catch(function (err) {
        console.error("[VSP_RUN_FULL] ERROR:", err);
        alert("Failed to start FULL scan: " + err);
      });
  });
})();
