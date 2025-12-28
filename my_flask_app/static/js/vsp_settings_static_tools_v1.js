(function () {
  function findToolStackBody() {
    // Tìm card có title chứa "TOOL STACK"
    var cards = document.querySelectorAll('.vsp-card, .sb-card, .card');
    for (var i = 0; i < cards.length; i++) {
      var title = cards[i].querySelector('.vsp-card-title, .card-title, h3, h4, .sb-card-title');
      if (!title) continue;
      var txt = (title.textContent || '').trim().toUpperCase();
      if (txt.indexOf('TOOL STACK') !== -1) {
        var body = cards[i].querySelector('.vsp-card-body, .sb-card-body, .card-body, .sb-card-content');
        return body || cards[i];
      }
    }
    return null;
  }

  function renderToolStack() {
    try {
      var body = findToolStackBody();
      if (!body) {
        if (window.console && console.warn) {
          console.warn('[VSP][SETTINGS] Không tìm thấy card TOOL STACK – ENABLED TOOLS');
        }
        return;
      }

      var html = ''
        + '<table class="vsp-table vsp-table-compact">'
        + '  <thead>'
        + '    <tr>'
        + '      <th>#</th>'
        + '      <th>TOOL</th>'
        + '      <th>TYPE</th>'
        + '      <th>PROFILE</th>'
        + '      <th>MODE</th>'
        + '    </tr>'
        + '  </thead>'
        + '  <tbody>'
        + '    <tr><td>1</td><td>gitleaks</td><td>Secrets scan</td><td>EXT+</td><td>Source code / config</td></tr>'
        + '    <tr><td>2</td><td>semgrep</td><td>SAST</td><td>EXT+</td><td>C#, JS, … rules</td></tr>'
        + '    <tr><td>3</td><td>kics</td><td>IaC scan</td><td>EXT+</td><td>Terraform / Docker / K8s</td></tr>'
        + '    <tr><td>4</td><td>codeql</td><td>Deep SAST</td><td>EXT+</td><td>C#/JS advanced queries</td></tr>'
        + '    <tr><td>5</td><td>bandit</td><td>Python SAST</td><td>EXT+</td><td>Python security checks</td></tr>'
        + '    <tr><td>6</td><td>trivy-fs</td><td>FS / image</td><td>EXT+</td><td>File system & image scan</td></tr>'
        + '    <tr><td>7</td><td>syft</td><td>SBOM</td><td>EXT+</td><td>Generate SBOM</td></tr>'
        + '    <tr><td>8</td><td>grype</td><td>Vuln on SBOM</td><td>EXT+</td><td>Match SBOM with CVE</td></tr>'
        + '  </tbody>'
        + '</table>';

      body.innerHTML = html;

      if (window.console && console.log) {
        console.log('[VSP][SETTINGS] Đã render static TOOL STACK cho Settings tab.');
      }
    } catch (e) {
      if (window.console && console.error) {
        console.error('[VSP][SETTINGS] Lỗi render static tool stack:', e);
      }
    }
  }

  document.addEventListener('DOMContentLoaded', function () {
    renderToolStack();
    setTimeout(renderToolStack, 500);
    setTimeout(renderToolStack, 1500);
  });
})();
