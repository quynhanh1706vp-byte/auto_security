(function(){
  console.log("[VSP_SETTINGS] run-local handler loaded");

  document.addEventListener("DOMContentLoaded", function(){
    const btn = document.getElementById("btn-run-local");
    if (!btn) return;

    btn.onclick = function(){
      fetch("/api/vsp/run", {method:"POST"})
      .then(r => r.json())
      .then(x => {
        alert("Run started: " + x.run_id);
      })
      .catch(e => alert("Error: "+e));
    };
  });
})();
