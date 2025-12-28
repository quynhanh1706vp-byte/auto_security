#!/usr/bin/env bash
set -euo pipefail

ROOT="/home/test/Data/SECURITY_BUNDLE/ui"
cd "$ROOT"

echo "[i] ROOT = $ROOT"

HTML='<!DOCTYPE html>
<html lang="vi">
<head>
  <meta charset="utf-8">
  <title>SECURITY BUNDLE – Data Source</title>
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

    .sb-page   { width:100vw; max-width:100vw; padding:12px 18px 20px; }
    .sb-layout { display:flex; align-items:flex-start; gap:16px; width:100%; }

    /* SIDEBAR */
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
    .sb-sidebar-nav {
      display:flex;
      flex-direction:column;
      gap:6px;
    }
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

    /* MAIN */
    .sb-main-wrapper {
      flex:1;
      display:flex;
      flex-direction:column;
      gap:10px;
    }
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
      border:0; /* Ẩn khung bo ngoài */
      box-shadow:var(--sb-shadow-soft);
      padding:16px 18px 18px;
      width:100%;
      max-width:100%;
    }
    .sb-card-header {
      display:flex;
      justify-content:space-between;
      align-items:baseline;
      margin-bottom:10px;
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
    .sb-card-body {
      font-size:13px;
      color:var(--sb-text-soft);
    }

    /* Bảng key/value trong Data Source */
    .ds-table {
      width:100%;
      border-collapse:collapse;
      margin-bottom:12px;
      font-size:13px;
    }
    .ds-table td {
      padding:4px 8px;
      vertical-align:top;
    }
    .ds-table td:first-child {
      width:140px;
      text-transform:uppercase;
      letter-spacing:.08em;
      font-size:11px;
      color:#e9fff7;
    }
    .ds-table tr:nth-child(odd) td {
      background:rgba(0,25,15,0.8);
    }
    .ds-table tr:nth-child(even) td {
      background:rgba(0,22,16,0.9);
    }
    .ds-table td:nth-child(2) {
      color:#f5fff9;
      white-space:nowrap;
    }
    .ds-table td:nth-child(3) {
      color:var(--sb-text-soft);
      font-size:12px;
    }

    .ds-section-title {
      margin-top:10px;
      margin-bottom:4px;
      font-size:12px;
      letter-spacing:.14em;
      text-transform:uppercase;
      color:#e9fff7;
    }
    .ds-text {
      font-size:12px;
      color:var(--sb-text-soft);
    }

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

      <!-- SIDEBAR -->
      <aside class="sb-sidebar">
        <div class="sb-sidebar-logo">
          SECURITY BUNDLE
          <span>Dashboard &amp; reports</span>
        </div>
        <nav class="sb-sidebar-nav">
          <a href="/"         class="sb-nav-link">Dashboard</a>
          <a href="/runs"     class="sb-nav-link">Runs &amp; Reports</a>
          <a href="/settings" class="sb-nav-link">Settings</a>
          <a href="/datasource" class="sb-nav-link sb-nav-link-active">Data Source</a>
        </nav>
      </aside>

      <!-- MAIN -->
      <div class="sb-main-wrapper">
        <header class="sb-header">
          <div class="sb-header-title">
            Data Source – UI input
            <span>Mô tả nguồn dữ liệu JSON mà SECURITY_BUNDLE UI đang sử dụng</span>
          </div>
        </header>

        <main>
          <section class="sb-card">
            <div class="sb-card-header">
              <h1>DATA SOURCE – UI INPUT</h1>
              <span class="sb-pill">Read only</span>
            </div>
            <div class="sb-card-body">
              <table class="ds-table">
                <tr>
                  <td>RUN ROOT</td>
                  <td>/home/test/Data/SECURITY_BUNDLE/out</td>
                  <td>Thư mục chứa các RUN_* (RUN_YYYYmmdd_HHmmSS).</td>
                </tr>
                <tr>
                  <td>UI ROOT</td>
                  <td>/home/test/Data/SECURITY_BUNDLE/ui</td>
                  <td>Nơi đặt templates/static/script UI.</td>
                </tr>
                <tr>
                  <td>JSON FINDINGS</td>
                  <td>findings_unified.json</td>
                  <td>File JSON chính, mỗi record gồm tool, severity, rule, location, message…</td>
                </tr>
                <tr>
                  <td>SUMMARY JSON</td>
                  <td>summary_unified.json</td>
                  <td>JSON tổng hợp theo RUN dùng cho Dashboard (cards, charts…).</td>
                </tr>
                <tr>
                  <td>REPORT HTML</td>
                  <td>
                    pm_style_report.html<br>
                    security_resilient.html<br>
                    simple_report.html
                  </td>
                  <td>Các template HTML dùng để generate report cho từng RUN. Tab Runs &amp; Reports sẽ link tới các file này.</td>
                </tr>
              </table>

              <div class="ds-section-title">Sample Findings – ví dụ render từ JSON</div>
              <div class="ds-text">
                UI sẽ đọc một phần dữ liệu từ <code>findings_unified.json</code> (ví dụ ~20–40 dòng đầu)
                để dựng bảng sample/top risk ở Dashboard &amp; Data Source view.
              </div>
            </div>
          </section>
        </main>
      </div>

    </div>
  </div>
</body>
</html>
'

for tpl in templates/datasource.html templates/data_source.html; do
  echo "[INFO] Ghi lại $tpl"
  printf "%s\n" "$HTML" > "$tpl"
done

echo "[DONE] Đã đồng bộ lại layout Data Source (sidebar + card phẳng, không khung bo ngoài)."
