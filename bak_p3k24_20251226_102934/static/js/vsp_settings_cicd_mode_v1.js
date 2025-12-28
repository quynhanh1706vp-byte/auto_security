(function(){
  console.log("[VSP_SETTINGS] cicd mode loaded");

  document.addEventListener("DOMContentLoaded", function(){
    const sel = document.getElementById("sel-cicd-mode");
    if (!sel) return;

    fetch("/api/vsp/settings_ui_v1")
      .then(r => r.json())
      .then(cfg => {
        if (cfg.settings && cfg.settings.cicd_mode)
          sel.value = cfg.settings.cicd_mode;
      });

    sel.onchange = function(){
      fetch("/api/vsp/settings_update", {
        method:"POST",
        headers: {"Content-Type":"application/json"},
        body: JSON.stringify({ cicd_mode: sel.value })
      });
    };
  });
})();
