(function(){
  console.log("[VSP_GATE] floating CI gate card loaded");

  function insertCard(html) {
    var old = document.getElementById("vsp-floating-ci-gate");
    if (old) old.remove();

    var host = document.body;
    var div = document.createElement("div");
    div.id = "vsp-floating-ci-gate";
    div.style.position = "fixed";
    div.style.right = "24px";
    div.style.bottom = "24px";
    div.style.zIndex = "999";
    div.innerHTML = html;
    host.appendChild(div);
  }

  fetch("/api/vsp/dashboard_v3", { credentials: "same-origin" })
    .then(function(r){ if(!r.ok) throw new Error("HTTP "+r.status); return r.json(); })
    .then(function(d){
      var sev = d.by_severity || {};
      var html = [
        '<div class="vsp-ci-gate-card">',
        '  <div class="vsp-ci-gate-header">',
        '    <span>CI GATE – Latest Run</span>',
        '    <span class="vsp-ci-gate-badge">', (d.ci_gate_status && d.ci_gate_status.label) || 'FAILED', '</span>',
        '  </div>',
        '  <div class="vsp-ci-gate-body">',
        '    <div class="vsp-ci-gate-runid">', (d.latest_run_id || '—'), '</div>',
        '    <div class="vsp-ci-gate-total">Total findings: ', (d.total_findings || 0), '</div>',
        '    <div class="vsp-ci-gate-sev">',
        '      C:', (sev.CRITICAL||0), ' · ',
        '      H:', (sev.HIGH||0), ' · ',
        '      M:', (sev.MEDIUM||0), ' · ',
        '      L:', (sev.LOW||0), ' · ',
        '      I:', (sev.INFO||0), ' · ',
        '      T:', (sev.TRACE||0),
        '    </div>',
        '    <a href="#/runs" class="vsp-ci-gate-link">View in Runs</a>',
        '  </div>',
        '</div>'
      ].join('');
      insertCard(html);
    })
    .catch(function(err){
      console.error("[VSP_GATE] failed to load dashboard_v3 for gate card:", err);
    });

})();
