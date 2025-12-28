(function () {
  function log(msg) {
    console.log('[TOOL-NOTES]', msg);
  }

  function norm(name) {
    return (name || '')
      .toLowerCase()
      .replace(/\s+/g, '')
      .replace(/[^a-z0-9]/g, '');
  }

  const NOTES = {
    // Trivy_FS
    'trivyfs':
      'Hoạt động bình thường – Trivy_FS: phiên bản Trivy cho File System scan (Aquasecurity). ' +
      'Scan vulnerabilities, misconfigs, secrets trong filesystem/code. Mode "fast": scan nhanh, ưu tiên tốc độ; ' +
      'mode "aggr": quét sâu hơn. Output JSON hoặc CycloneDX (SBOM).',

    // Trivy_IaC
    'trivyiac':
      'Hoạt động bình thường – Trivy_IaC: scanner cho Infrastructure as Code (Terraform, Kubernetes, …). ' +
      'Kiểm tra misconfigurations trong IaC. "fast": nhanh, không deep dive; "aggr": kiểm tra kỹ hơn. ' +
      'Hỗ trợ cả local (Offline) và remote (Online).',

    // Grype
    'grype':
      'Hoạt động bình thường – Grype (Anchore): vulnerability scanner cho container images/filesystems. ' +
      'Thường kết hợp với Syft (SBOM). "aggr": aggressive scan, kiểm tra sâu với nhiều DB (CVE, …). Output JSON/CD.',

    // Syft_SBOM
    'syftsbom':
      'Hoạt động bình thường – Syft_SBOM (Anchore): generate Software Bill of Materials (SBOM) cho dependencies. ' +
      '"fast": tạo SBOM nhanh. Hỗ trợ CycloneDX/SPDX. Offline: local files; Online: remote images.',

    // Syft (nếu có hàng riêng)
    'syft':
      'Hoạt động bình thường – Syft: bản Syft cơ bản để catalog packages và sinh SBOM. ' +
      'Chủ yếu output JSON/CD. Thường chạy Offline trên source hoặc image local.',

    // Gitleaks
    'gitleaks':
      'Hoạt động bình thường – Gitleaks: secret scanner (API keys, passwords, tokens trong code/git). ' +
      '"fast": scan nhanh qua repo; "aggr": quét kỹ hơn theo chuẩn ISO. Thường chạy Offline trên repository local.',

    // Bandit
    'bandit':
      'Hoạt động bình thường – Bandit (PyCQA): Python static analyzer, tìm vulnerabilities trong Python code. ' +
      'Mode "aggr": full scan với rules mạnh hơn. Chủ yếu chạy Offline; có thể tích hợp Online/CI/CD.',

    // KICS
    'kics':
      'Hoạt động bình thường – KICS (Checkmarx): Keeping Infrastructure as Code Secure. ' +
      'Scan misconfigurations trong Terraform, CloudFormation, … "fast": quét nhanh; "aggr": kiểm tra sâu hơn. ' +
      'Thường chạy Offline trên file IaC.',

    // CodeQL
    'codeql':
      'Hoạt động bình thường – CodeQL (GitHub): semantic code analysis, query code như data để tìm vulnerabilities (đa ngôn ngữ). ' +
      'Mode "aggr": deep analysis, phù hợp chuẩn ISO. Offline: build DB & query local; Online: có thể tích hợp GitHub Advanced Security.'
  };

  function findToolTable() {
    // ưu tiên section có chữ "Danh sách tool & cấu hình"
    const labelNodes = Array.from(
      document.querySelectorAll('h1,h2,h3,h4,div,span')
    ).filter(el =>
      (el.textContent || '').includes('Danh sách tool & cấu hình')
    );

    for (const el of labelNodes) {
      const t = el.closest('section,div,main,article,card')?.querySelector('table');
      if (t) return t;
    }

    // fallback: table có header "TOOL" và "ENABLED"
    const tables = Array.from(document.querySelectorAll('table'));
    for (const t of tables) {
      const headers = Array.from(t.querySelectorAll('th')).map(th =>
        (th.textContent || '').trim().toUpperCase()
      );
      if (headers.includes('TOOL') && headers.includes('ENABLED')) {
        return t;
      }
    }

    return null;
  }

  function applyNotesOnce() {
    const table = findToolTable();
    if (!table) {
      return false;
    }

    let changed = false;
    const rows = Array.from(table.querySelectorAll('tr'));
    rows.forEach(row => {
      if (row.querySelector('th')) return;
      const cells = row.children;
      if (!cells || cells.length === 0) return;

      const toolName = cells[0].textContent.trim();
      const key = norm(toolName);
      const note = NOTES[key];
      if (!note) return;

      const noteCell = cells[cells.length - 1];
      if (!noteCell) return;

      const input = noteCell.querySelector('input, textarea');
      if (input) {
        if (input.dataset.fixedNote === '1') return;
        input.value = note;
        input.setAttribute('readonly', 'readonly');
        input.dataset.fixedNote = '1';
      } else {
        if (noteCell.dataset.fixedNote === '1') return;
        noteCell.textContent = note;
        noteCell.dataset.fixedNote = '1';
      }

      changed = true;
    });

    if (changed) {
      log('Đã áp dụng ghi chú cố định cho các tool.');
    }
    return changed;
  }

  function schedulePatch() {
    let tries = 0;
    const maxTries = 20; // ~20 giây

    function tick() {
      const ok = applyNotesOnce();
      tries++;
      if (ok || tries >= maxTries) {
        clearInterval(timer);
        if (!ok) log('Dừng patch_tool_notes.js sau ' + tries + ' lần thử.');
      }
    }

    const timer = setInterval(tick, 1000);
    tick(); // chạy ngay 1 lần
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', schedulePatch);
  } else {
    schedulePatch();
  }
})();
