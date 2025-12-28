#!/usr/bin/env bash
set -euo pipefail

ROOT="/home/test/Data/SECURITY_BUNDLE/ui"
BASE="$ROOT/templates/base.html"

echo "[i] ROOT = $ROOT"
echo "[i] BASE = $BASE"

if [ ! -f "$BASE" ]; then
  echo "[ERR] Không tìm thấy templates/base.html"
  exit 1
fi

python3 - "$BASE" <<'PY'
import sys, pathlib

path = pathlib.Path(sys.argv[1])
html = path.read_text()

marker = "<!-- PATCH_TOOL_NOTES_INLINE -->"

if marker not in html:
    print("[ERR] Không tìm thấy marker PATCH_TOOL_NOTES_INLINE trong base.html")
    sys.exit(1)

start = html.index(marker)
script_open = html.find("<script>", start)
script_close = html.find("</script>", script_open)
if script_open == -1 or script_close == -1:
    print("[ERR] Không tìm thấy cặp <script>...</script> sau marker")
    sys.exit(1)

new_js = """<!-- PATCH_TOOL_NOTES_INLINE -->
<script>
(function () {
  function log(msg) {
    console.log('[TOOL-NOTES-V2]', msg);
  }

  function norm(name) {
    return (name || '')
      .toLowerCase()
      .replace(/\\s+/g, '')
      .replace(/[^a-z0-9]/g, '');
  }

  const NOTES = {
    'trivyfs':
      'Hoạt động bình thường – Trivy_FS: phiên bản Trivy cho File System scan (Aquasecurity). ' +
      'Scan vulnerabilities, misconfigs, secrets trong filesystem/code. Mode "fast": scan nhanh, ưu tiên tốc độ; ' +
      'mode "aggr": quét sâu hơn. Output JSON hoặc CycloneDX (SBOM).',

    'trivyiac':
      'Hoạt động bình thường – Trivy_IaC: scanner cho Infrastructure as Code (Terraform, Kubernetes, …). ' +
      'Kiểm tra misconfigurations trong IaC. "fast": nhanh, không deep dive; "aggr": kiểm tra kỹ hơn. ' +
      'Hỗ trợ cả local (Offline) và remote (Online).',

    'grype':
      'Hoạt động bình thường – Grype (Anchore): vulnerability scanner cho container images/filesystems. ' +
      'Thường kết hợp với Syft (SBOM). "aggr": aggressive scan, kiểm tra sâu với nhiều DB (CVE, …). Output JSON/CD.',

    'syftsbom':
      'Hoạt động bình thường – Syft_SBOM (Anchore): generate Software Bill of Materials (SBOM) cho dependencies. ' +
      '"fast": tạo SBOM nhanh. Hỗ trợ CycloneDX/SPDX. Offline: local files; Online: remote images.',

    'syft':
      'Hoạt động bình thường – Syft: bản Syft cơ bản để catalog packages và sinh SBOM. ' +
      'Chủ yếu output JSON/CD. Thường chạy Offline trên source hoặc image local.',

    'gitleaks':
      'Hoạt động bình thường – Gitleaks: secret scanner (API keys, passwords, tokens trong code/git). ' +
      '"fast": scan nhanh qua repo; "aggr": quét kỹ hơn theo chuẩn ISO. Thường chạy Offline trên repository local.',

    'bandit':
      'Hoạt động bình thường – Bandit (PyCQA): Python static analyzer, tìm vulnerabilities trong Python code. ' +
      'Mode "aggr": full scan với rules mạnh hơn. Chủ yếu chạy Offline; có thể tích hợp Online/CI/CD.',

    'kics':
      'Hoạt động bình thường – KICS (Checkmarx): Keeping Infrastructure as Code Secure. ' +
      'Scan misconfigurations trong Terraform, CloudFormation, … "fast": quét nhanh; "aggr": kiểm tra sâu hơn. ' +
      'Thường chạy Offline trên file IaC.',

    'codeql':
      'Hoạt động bình thường – CodeQL (GitHub): semantic code analysis, query code như data để tìm vulnerabilities (đa ngôn ngữ). ' +
      'Mode "aggr": deep analysis, phù hợp chuẩn ISO. Offline: build DB & query local; Online: có thể tích hợp GitHub Advanced Security.'
  };

  const LABEL_TO_KEY = {
    'Trivy_FS': 'trivyfs',
    'Trivy_IaC': 'trivyiac',
    'Grype': 'grype',
    'Syft_SBOM': 'syftsbom',
    'Gitleaks': 'gitleaks',
    'Bandit': 'bandit',
    'KICS': 'kics',
    'CodeQL': 'codeql'
  };

  function applyNotesOnce() {
    let changed = false;

    Object.keys(LABEL_TO_KEY).forEach(function(label) {
      const key = LABEL_TO_KEY[label];
      const note = NOTES[key] || '';
      if (!note) return;

      const candidates = Array.from(
        document.querySelectorAll('span,div,td,th,label')
      ).filter(function(el) {
        return (el.textContent || '').trim() === label;
      });

      candidates.forEach(function(el) {
        const row = el.closest('tr, .tool-row, .table-row, .row, .flex, .grid, li');
        if (!row) return;

        const inputs = row.querySelectorAll('input, textarea');
        if (!inputs.length) return;

        const noteInput = inputs[inputs.length - 1];
        if (!noteInput || noteInput.dataset.fixedNote === '1') return;

        if ('value' in noteInput) {
          noteInput.value = note;
        } else {
          noteInput.textContent = note;
        }
        noteInput.readOnly = true;
        noteInput.dataset.fixedNote = '1';
        changed = true;
      });
    });

    if (changed) {
      log('Đã áp dụng ghi chú cố định cho các tool (V2).');
    }
    return changed;
  }

  function schedulePatch() {
    let tries = 0;
    const maxTries = 40;

    function tick() {
      const ok = applyNotesOnce();
      tries++;
      if (ok || tries >= maxTries) {
        clearInterval(timer);
        if (!ok) log('Stop TOOL-NOTES-V2 sau ' + tries + ' lần, không tìm được row.');
      }
    }

    const timer = setInterval(tick, 1000);
    tick();
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', schedulePatch);
  } else {
    schedulePatch();
  }
})();
</script>"""

before = html[:start]
after = html[script_close+len("</script>"):]
html_new = before + new_js + after
path.write_text(html_new)

print(f"[OK] Đã thay inline script TOOL_NOTES bằng V2 trong {path}")
PY

echo "[DONE] patch_tool_notes_layout_v2.sh hoàn thành."
