#!/usr/bin/env bash
set -e

HTML="SECURITY_BUNDLE_FULL_5_PAGES.html"

python3 - << 'PY'
import re, textwrap, pathlib

path = pathlib.Path("SECURITY_BUNDLE_FULL_5_PAGES.html")
html = path.read_text(encoding="utf-8")

new_block = textwrap.dedent("""\
    <!-- 2. RUNS & REPORTS -->
    <section id="runs" class="hidden">
      <h2 class="text-4xl font-bold mb-2">Runs &amp; Reports</h2>
      <p class="text-slate-400 mb-6">
        Lịch sử các lần scan gần nhất – dùng Export để tải kết quả chi tiết cho từng RUN.
      </p>
      <div class="card p-6 overflow-x-auto">
        <table class="w-full text-sm">
          <thead class="border-b-2 border-slate-700">
            <tr>
              <th class="py-3 text-left">Run</th>
              <th class="py-3 text-left">Thời gian</th>
              <th class="py-3 text-left">SRC</th>
              <th class="py-3 text-left">Profile / Findings</th>
              <th class="py-3 text-right">Export</th>
            </tr>
          </thead>
          <tbody class="divide-y divide-slate-800">
            <tr class="hover:bg-slate-800/60">
              <td class="py-3 font-mono text-lime-300">RUN_20251126_032236</td>
              <td class="py-3 text-slate-300">2025-11-26 03:22</td>
              <td class="py-3 text-slate-300">/home/test/Data/Khach</td>
              <td class="py-3">
                <div class="font-semibold text-lime-400">9,071 findings</div>
                <div class="text-xs text-slate-400">PROFILE = AGGR / EXT</div>
              </td>
              <td class="py-3 text-right space-x-2">
                <a href="#" class="inline-block px-3 py-1 rounded-full text-xs font-semibold bg-lime-400 text-black">CSV</a>
                <a href="#" class="inline-block px-3 py-1 rounded-full text-xs font-semibold bg-lime-400 text-black">PDF</a>
                <a href="#" class="inline-block px-3 py-1 rounded-full text-xs font-semibold bg-lime-400 text-black">HTML</a>
              </td>
            </tr>
            <tr class="hover:bg-slate-800/60">
              <td class="py-3 font-mono text-lime-300">RUN_20251125_210538</td>
              <td class="py-3 text-slate-300">2025-11-25 21:05</td>
              <td class="py-3 text-slate-300">/home/test/Data/CODE_20112025_P</td>
              <td class="py-3">
                <div class="font-semibold text-lime-400">5,236 findings</div>
                <div class="text-xs text-slate-400">PROFILE = STD</div>
              </td>
              <td class="py-3 text-right space-x-2">
                <a href="#" class="inline-block px-3 py-1 rounded-full text-xs font-semibold bg-lime-400 text-black">CSV</a>
                <a href="#" class="inline-block px-3 py-1 rounded-full text-xs font-semibold bg-lime-400 text-black">PDF</a>
                <a href="#" class="inline-block px-3 py-1 rounded-full text-xs font-semibold bg-lime-400 text-black">HTML</a>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </section>

    <!-- 3. DATA SOURCE -->
    <section id="datasource" class="hidden">
      <h2 class="text-4xl font-bold mb-2">Data Source</h2>
      <p class="text-slate-400 mb-6">
        Tổng hợp theo tool và một vài findings tiêu biểu từ <code>summary_unified.json</code> và <code>findings.json</code>.
      </p>
      <div class="card">
        <div class="flex border-b border-slate-700">
          <button id="tab-summary" class="tab-active px-8 py-5 font-semibold">
            Summary by Tool
          </button>
          <button id="tab-samples" class="px-8 py-5 hover:bg-slate-800 font-semibold">
            Sample Findings
          </button>
        </div>
        <div class="p-8">
          <!-- SUMMARY TABLE (giữ format tổng hợp) -->
          <div id="summary-content">
            <table class="w-full text-lg">
              <thead class="border-b-2 border-slate-700 pb-4">
                <tr>
                  <th class="text-left">Tool</th>
                  <th class="text-left">Critical</th>
                  <th class="text-left">High</th>
                  <th class="text-left">Medium</th>
                  <th class="text-left">Low</th>
                  <th class="text-right">Total</th>
                </tr>
              </thead>
              <tbody class="divide-y divide-slate-700">
                <tr>
                  <td class="py-4">Semgrep</td>
                  <td class="py-4">0</td>
                  <td class="py-4 text-orange-400">346</td>
                  <td class="py-4">8,651</td>
                  <td class="py-4">0</td>
                  <td class="py-4 text-right text-lime-400 font-bold">8,997</td>
                </tr>
                <tr>
                  <td class="py-4">Gitleaks</td>
                  <td class="py-4">0</td>
                  <td class="py-4 text-orange-400">26</td>
                  <td class="py-4">0</td>
                  <td class="py-4">0</td>
                  <td class="py-4 text-right">26</td>
                </tr>
                <tr>
                  <td class="py-4">Grype</td>
                  <td class="py-4">0</td>
                  <td class="py-4">1</td>
                  <td class="py-4">1</td>
                  <td class="py-4">0</td>
                  <td class="py-4 text-right">2</td>
                </tr>
                <tr>
                  <td class="py-4">Trivy FS</td>
                  <td class="py-4">0</td>
                  <td class="py-4">3</td>
                  <td class="py-4">8</td>
                  <td class="py-4">12</td>
                  <td class="py-4 text-right">23</td>
                </tr>
              </tbody>
            </table>
          </div>

          <!-- SAMPLE FINDINGS TABLE -->
          <div id="samples-content" class="hidden">
            <table class="w-full text-sm">
              <thead class="border-b border-slate-700">
                <tr>
                  <th class="py-2 text-left">Severity</th>
                  <th class="py-2 text-left">Tool</th>
                  <th class="py-2 text-left">Rule / ID</th>
                  <th class="py-2 text-left">Location</th>
                </tr>
              </thead>
              <tbody class="divide-y divide-slate-800">
                <tr class="hover:bg-slate-800/60">
                  <td class="py-2 font-semibold text-red-400">CRITICAL</td>
                  <td class="py-2">semgrep</td>
                  <td class="py-2">generic.audit.exec</td>
                  <td class="py-2">utils/helper.py:89 → <code>subprocess.call(cmd, shell=True)</code></td>
                </tr>
                <tr class="hover:bg-slate-800/60">
                  <td class="py-2 font-semibold text-orange-400">HIGH</td>
                  <td class="py-2">gitleaks</td>
                  <td class="py-2">generic_credential</td>
                  <td class="py-2">config/.env (AWS_ACCESS_KEY_ID)</td>
                </tr>
                <tr class="hover:bg-slate-800/60">
                  <td class="py-2 font-semibold text-yellow-300">MEDIUM</td>
                  <td class="py-2">trivy_fs</td>
                  <td class="py-2">http_over_plain_text</td>
                  <td class="py-2">docker-compose.yml:34 (service api → http://backend:8080)</td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>
      </div>
    </section>
""")

pattern = r'<!-- 2\. RUNS & REPORTS -->[\\s\\S]*?<!-- 4\. SETTINGS -->'
replacement = new_block + "\\n\\n    <!-- 4. SETTINGS -->"

new_html, n = re.subn(pattern, replacement, html)
if n == 0:
    raise SystemExit("Không tìm thấy block từ RUNS & REPORTS tới SETTINGS để thay.")

path.write_text(new_html, encoding="utf-8")
print("[OK] Đã patch Runs & Reports + Data Source trong SECURITY_BUNDLE_FULL_5_PAGES.html")
PY
