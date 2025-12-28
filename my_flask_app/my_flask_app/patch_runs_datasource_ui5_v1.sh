#!/usr/bin/env bash
set -e

HTML="SECURITY_BUNDLE_FULL_5_PAGES.html"

python3 - <<'PY'
import re, textwrap, pathlib

path = pathlib.Path("SECURITY_BUNDLE_FULL_5_PAGES.html")
html = path.read_text(encoding="utf-8")

# ---------- New Runs & Reports section ----------
run_section = textwrap.dedent("""\
<section id="tab-runs" class="sb-tab">
  <div class="sb-main">
    <div class="sb-main-header">
      <div class="sb-main-title">Runs &amp; Reports</div>
      <div class="sb-main-subtitle">
        History of recent scans – click Export to download artifacts.
      </div>
    </div>

    <div class="sb-card sb-card-table">
      <table class="sb-table sb-table-runs">
        <thead>
          <tr>
            <th class="text-left">Run</th>
            <th class="text-left">Time</th>
            <th class="text-left">SRC</th>
            <th class="text-left">Total / Profile</th>
            <th class="text-right">Export</th>
          </tr>
        </thead>
        <tbody>
          <tr>
            <td>RUN_20251126_032236</td>
            <td>2025-11-26 03:22</td>
            <td>/home/test/Data/Khach</td>
            <td>9,071 findings · EXT Aggressive</td>
            <td class="text-right">
              <a href="#" class="sb-pill-button sb-pill-success">CSV</a>
              <a href="#" class="sb-pill-button sb-pill-success">PDF</a>
              <a href="#" class="sb-pill-button sb-pill-success">HTML</a>
            </td>
          </tr>
          <tr>
            <td>RUN_20251125_091500</td>
            <td>2025-11-25 09:15</td>
            <td>/home/test/Data/Khach</td>
            <td>5,236 findings · STD</td>
            <td class="text-right">
              <a href="#" class="sb-pill-button sb-pill-success">CSV</a>
              <a href="#" class="sb-pill-button sb-pill-success">PDF</a>
              <a href="#" class="sb-pill-button sb-pill-success">HTML</a>
            </td>
          </tr>
        </tbody>
      </table>
    </div>
  </div>
</section>
""")

# ---------- New Data Source + Sample Findings table ----------
data_section = textwrap.dedent("""\
<section id="tab-data" class="sb-tab">
  <div class="sb-main">
    <div class="sb-main-header">
      <div class="sb-main-title">Data Source</div>
      <div class="sb-main-subtitle">
        Summary by tool and top sample findings from <code>findings.json</code>.
      </div>
    </div>

    <div class="sb-card sb-card-tabs">
      <div class="sb-tabs-header">
        <button class="sb-tab-btn sb-tab-btn-active" data-tab="ds-summary">
          Summary Table
        </button>
        <button class="sb-tab-btn" data-tab="ds-samples">
          Sample Findings
        </button>
      </div>

      <div class="sb-tabs-body">
        <!-- SUMMARY TABLE: giữ chỗ, sẽ đổ data thật sau -->
        <div id="ds-summary" class="sb-tab-pane sb-tab-pane-active">
          <table class="sb-table sb-table-compact">
            <thead>
              <tr>
                <th class="text-left">Tool</th>
                <th class="text-left">Critical</th>
                <th class="text-left">High</th>
                <th class="text-left">Medium</th>
                <th class="text-left">Low</th>
                <th class="text-right">Total</th>
              </tr>
            </thead>
            <tbody>
              <tr>
                <td>Bandit</td>
                <td>12</td>
                <td>45</td>
                <td>23</td>
                <td>8</td>
                <td class="text-right">88</td>
              </tr>
              <tr>
                <td>Semgrep</td>
                <td>8</td>
                <td>32</td>
                <td>67</td>
                <td>21</td>
                <td class="text-right">128</td>
              </tr>
            </tbody>
          </table>
        </div>

        <!-- SAMPLE FINDINGS TABLE -->
        <div id="ds-samples" class="sb-tab-pane">
          <table class="sb-table sb-table-compact">
            <thead>
              <tr>
                <th class="text-left">Severity</th>
                <th class="text-left">Tool</th>
                <th class="text-left">Rule / ID</th>
                <th class="text-left">Location</th>
              </tr>
            </thead>
            <tbody>
              <tr>
                <td class="sb-sev-critical">CRITICAL</td>
                <td>semgrep</td>
                <td>generic_exec_command</td>
                <td>src/runner.py:76 → <code>os.system(user_input)</code></td>
              </tr>
              <tr>
                <td class="sb-sev-high">HIGH</td>
                <td>gitleaks</td>
                <td>generic_credential</td>
                <td>config/.env (GITLAB_TOKEN)</td>
              </tr>
              <tr>
                <td class="sb-sev-medium">MEDIUM</td>
                <td>trivy_fs</td>
                <td>http_over_plain_text</td>
                <td>docker-compose.yml:34 (PLAINTEXT HTTP)</td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>
    </div>
  </div>
</section>
""")

new_html, n1 = re.subn(r'<section id="tab-runs"[\\s\\S]*?</section>', run_section, html, count=1)
new_html, n2 = re.subn(r'<section id="tab-data"[\\s\\S]*?</section>', data_section, new_html, count=1)

if n1 == 0:
    raise SystemExit("Không tìm thấy <section id=\"tab-runs\"> để thay.")
if n2 == 0:
    raise SystemExit("Không tìm thấy <section id=\"tab-data\"> để thay.")

path.write_text(new_html, encoding="utf-8")
print("[OK] Đã patch tab Runs & Reports + Data Source trong SECURITY_BUNDLE_FULL_5_PAGES.html")
PY
