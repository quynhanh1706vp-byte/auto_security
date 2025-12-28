#!/usr/bin/env bash
set -euo pipefail

ROOT="/home/test/Data/SECURITY_BUNDLE/ui"
TPL="$ROOT/templates/settings.html"

echo "[i] ROOT = $ROOT"
echo "[i] TPL  = $TPL"

cat > "$TPL" <<'HTML'
<!DOCTYPE html>
<html lang="vi">
<head>
  <meta charset="utf-8">
  <title>SECURITY BUNDLE – Settings</title>
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <link rel="stylesheet" href="/static/css/security_resilient.css">
  <style>
    :root {
      --sb-bg: #02050a;
      --sb-border-subtle: rgba(0, 255, 180, 0.16);
      --sb-text-main: #f5fff9;
      --sb-text-soft: #7da4a0;
      --sb-shadow-soft: 0 14px 32px rgba(0, 0, 0, 0.8);
    }
    * { box-sizing: border-box; }
    html, body { margin:0; padding:0; width:100%; height:100%; }
    body {
      font-family: system-ui,-apple-system,BlinkMacSystemFont,"SF Pro Text","Segoe UI",sans-serif;
      color: var(--sb-text-main);
      background:
        radial-gradient(circle at top left, rgba(25,189,148,0.32) 0, transparent 45%),
        radial-gradient(circle at bottom right, rgba(0,102,204,0.42) 0, #02050a 60%);
      min-height: 100vh;
      overflow-x: hidden;
    }
    .sb-page { width:100vw; max-width:100vw; padding:12px 18px 20px; }
    .sb-layout { display:flex; align-items:flex-start; gap:16px; width:100%; }

    .sb-sidebar {
      width:190px;
      min-height:520px;
      background:linear-gradient(180deg,rgba(7,40,34,0.95),rgba(3,15,15,0.98));
      border-radius:0;
      border:1px solid rgba(54,211,168,0.45);
      box-shadow:var(--sb-shadow-soft);
      padding:10px 10px 12px;
    }
    .sb-sidebar-logo {
      font-size:12px;
      letter-spacing:.14em;
      text-transform:uppercase;
      color:var(--sb-text-soft);
      border-bottom:1px solid rgba(54,211,168,0.4);
      padding-bottom:8px;
      margin-bottom:8px;
    }
    .sb-sidebar-logo span {
      display:block;
      font-size:11px;
      opacity:.75;
      margin-top:2px;
    }
    .sb-sidebar-nav { display:flex; flex-direction:column; gap:6px; }
    .sb-nav-link {
      display:block;
      padding:6px 8px;
      font-size:12px;
      text-decoration:none;
      color:var(--sb-text-soft);
      text-transform:uppercase;
      letter-spacing:.12em;
      border-radius:0;
      border:1px solid transparent;
    }
    .sb-nav-link:hover {
      border-color:rgba(54,211,168,0.4);
      color:#f6fff9;
      background:rgba(5,18,18,0.9);
    }
    .sb-nav-link-active {
      border-color:rgba(54,211,168,0.9);
      color:#eafff7;
      background:rgba(5,32,26,0.98);
    }

    .sb-main-wrapper { flex:1; display:flex; flex-direction:column; gap:10px; }
    .sb-header {
      display:flex;
      justify-content:space-between;
      align-items:center;
      gap:12px;
      margin-bottom:4px;
    }
    .sb-header-title {
      padding:8px 14px;
      border-radius:0;
      background:linear-gradient(90deg,rgba(54,211,168,0.3),transparent 70%);
      border:1px solid rgba(54,211,168,0.5);
      font-size:13px;
      letter-spacing:.08em;
      text-transform:uppercase;
      color:var(--sb-text-soft);
      box-shadow:var(--sb-shadow-soft);
    }
    .sb-header-title span {
      display:block;
      font-size:11px;
      opacity:.75;
    }

    .sb-card {
      border-radius:0;
      background:linear-gradient(135deg,rgba(9,33,40,0.9),rgba(4,11,15,0.95));
      border:1px solid var(--sb-border-subtle);
      box-shadow:var(--sb-shadow-soft);
      padding:12px 14px 14px;
      width:100%;
    }
    .sb-card-header {
      display:flex;
      justify-content:space-between;
      align-items:baseline;
      margin-bottom:8px;
      gap:10px;
    }
    .sb-card-header h1 {
      font-size:13px;
      letter-spacing:.16em;
      text-transform:uppercase;
      margin:0;
      color:#e9fff7;
    }
    .sb-pill {
      font-size:11px;
      padding:3px 7px;
      border-radius:0;
      background:rgba(7,43,34,0.9);
      border:1px solid rgba(54,211,168,0.3);
      color:var(--sb-text-soft);
      text-transform:uppercase;
      letter-spacing:.12em;
    }

    .sb-card-body { font-size:13px; color:var(--sb-text-soft); }
    table.sb-tool-table {
      width:100%;
      border-collapse:collapse;
      font-size:12px;
    }
    table.sb-tool-table th,
    table.sb-tool-table td {
      padding:5px 4px;
      text-align:left;
      vertical-align:top;
    }
    table.sb-tool-table thead tr {
      border-bottom:1px solid rgba(54,211,168,0.35);
    }
    table.sb-tool-table th {
      font-size:11px;
      text-transform:uppercase;
      letter-spacing:.12em;
      color:rgba(207,255,237,0.85);
    }
    table.sb-tool-table tbody tr:nth-child(even) {
      background:rgba(1,29,21,0.85);
    }
    .sb-chip-mode {
      display:inline-flex;
      align-items:center;
      gap:4px;
      padding:1px 6px;
      border-radius:0;
      border:1px solid rgba(54,211,168,0.4);
      background:rgba(0,0,0,0.6);
      font-size:11px;
      color:var(--sb-text-soft);
      margin-right:3px;
    }
    .sb-note { margin-top:8px; font-size:12px; }

    @media (max-width:1100px){
      .sb-layout{flex-direction:column;}
      .sb-sidebar{
        width:100%;
        min-height:auto;
        display:flex;
        align-items:center;
      }
      .sb-sidebar-nav{
        flex-direction:row;
        margin-left:12px;
      }
    }
  </style>
</head>
<body>
  <div class="sb-page">
    <div class="sb-layout">
      <aside class="sb-sidebar">
        <div class="sb-sidebar-logo">
          SECURITY BUNDLE
          <span>Dashboard &amp; reports</span>
        </div>
        <nav class="sb-sidebar-nav">
          <a href="/"            class="sb-nav-link">Dashboard</a>
          <a href="/runs"        class="sb-nav-link">Runs &amp; Reports</a>
          <a href="/settings"    class="sb-nav-link sb-nav-link-active">Settings</a>
          <a href="/data_source" class="sb-nav-link">Data Source</a>
        </nav>
      </aside>

      <div class="sb-main-wrapper">
        <header class="sb-header">
          <div class="sb-header-title">
            Settings – Tool config
            <span>Cấu hình &amp; giải thích từng tool trong SECURITY_BUNDLE (view read-only)</span>
          </div>
        </header>

        <main>
          <section class="sb-card">
            <div class="sb-card-header">
              <h1>Cấu hình tool – tool_config.json (READ-ONLY)</h1>
              <span class="sb-pill">Danh sách tool &amp; modes</span>
            </div>
            <div class="sb-card-body">
              <table class="sb-tool-table">
                <thead>
                  <tr>
                    <th>Tool</th>
                    <th>Enabled</th>
                    <th>Level</th>
                    <th>Modes</th>
                    <th>Chú thích</th>
                  </tr>
                </thead>
                <tbody>
                  <tr>
                    <td>Trivy_FS</td>
                    <td>[x]</td>
                    <td>aggr</td>
                    <td>
                      <span class="sb-chip-mode">Offline</span>
                      <span class="sb-chip-mode">Online</span>
                      <span class="sb-chip-mode">CI/CD</span>
                    </td>
                    <td>File System scan: quét vuln/misconfig/secrets trong thư mục SRC.</td>
                  </tr>
                  <tr>
                    <td>Trivy_IaC</td>
                    <td>[x]</td>
                    <td>aggr</td>
                    <td>
                      <span class="sb-chip-mode">Offline</span>
                      <span class="sb-chip-mode">CI/CD</span>
                    </td>
                    <td>Scan Infrastructure as Code (Terraform, K8s, …) tìm misconfiguration.</td>
                  </tr>
                  <tr>
                    <td>Grype</td>
                    <td>[x]</td>
                    <td>fast</td>
                    <td>
                      <span class="sb-chip-mode">Offline</span>
                      <span class="sb-chip-mode">CI/CD</span>
                    </td>
                    <td>Vulnerability scanner cho container image / filesystem (dựa trên Syft SBOM).</td>
                  </tr>
                  <tr>
                    <td>Syft_SBOM</td>
                    <td>[x]</td>
                    <td>fast</td>
                    <td><span class="sb-chip-mode">Offline</span></td>
                    <td>Tạo SBOM cho dependencies, dùng cho Grype và báo cáo.</td>
                  </tr>
                  <tr>
                    <td>Gitleaks</td>
                    <td>[x]</td>
                    <td>aggr</td>
                    <td>
                      <span class="sb-chip-mode">Offline</span>
                      <span class="sb-chip-mode">CI/CD</span>
                    </td>
                    <td>Secret scanner – API key, password, token trong code/git.</td>
                  </tr>
                  <tr>
                    <td>Bandit</td>
                    <td>[x]</td>
                    <td>fast</td>
                    <td>
                      <span class="sb-chip-mode">Offline</span>
                      <span class="sb-chip-mode">CI/CD</span>
                    </td>
                    <td>Static analyzer cho Python, tìm bug &amp; vuln pattern phổ biến.</td>
                  </tr>
                  <tr>
                    <td>KICS</td>
                    <td>[x]</td>
                    <td>fast</td>
                    <td><span class="sb-chip-mode">Offline</span></td>
                    <td>Keeping Infrastructure as Code Secure – scan Terraform / K8s / CloudFormation.</td>
                  </tr>
                  <tr>
                    <td>CodeQL</td>
                    <td>[x]</td>
                    <td>aggr</td>
                    <td><span class="sb-chip-mode">Offline</span></td>
                    <td>Semantic code analysis dựa trên CodeQL DB &amp; query; dùng cho deep analysis / build dài.</td>
                  </tr>
                </tbody>
              </table>

              <p class="sb-note">
                Tab này đang ở chế độ giải thích (view only).  
                Cấu hình thực tế cho CLI / CI/CD vẫn được đọc từ file
                <code>ui/tool_config.json</code> khi chạy bundle.
              </p>
            </div>
          </section>
        </main>
      </div>
    </div>
  </div>
</body>
</html>
HTML

echo "[OK] Đã ghi lại templates/settings.html với layout mới (đồng bộ Dashboard)."
