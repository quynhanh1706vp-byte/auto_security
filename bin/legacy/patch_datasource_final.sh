#!/usr/bin/env bash
set -euo pipefail

ROOT="/home/test/Data/SECURITY_BUNDLE/ui"
TPL="$ROOT/templates/datasource.html"

echo "[i] ROOT = $ROOT"
echo "[i] TPL  = $TPL"

if [ ! -f "$TPL" ]; then
  echo "[ERR] Không tìm thấy $TPL"
  exit 1
fi

cat > "$TPL" <<'HTML'
{% extends "base.html" %}

{% block content %}
<div class="page">
  <div class="page-header">
    <h1 class="page-title">Data Source</h1>
    <p class="page-subtitle">
      Mô tả nguồn dữ liệu (đặc biệt là file JSON) mà SECURITY BUNDLE UI sử dụng để hiển thị Dashboard, Run &amp; Report.
    </p>
  </div>

  <div class="page-section-label">REFERENCE</div>

  <!-- CARD 1: DATA SOURCE – UI INPUT -->
  <div class="card card-sample mt-4">
    <div class="card-header">
      <h2 class="card-title">DATA SOURCE – UI INPUT</h2>
    </div>
    <div class="card-body">
      <div class="table-caption">READ ONLY</div>
      <table class="sample-table">
        <thead>
          <tr>
            <th>ITEM</th>
            <th>VALUE / PATH</th>
            <th>NOTE</th>
          </tr>
        </thead>
        <tbody>
          <tr>
            <td class="col-key">RUN ROOT</td>
            <td class="col-value">/home/test/Data/SECURITY_BUNDLE/out</td>
            <td class="col-note">
              Mỗi lần scan sinh ra một thư mục <strong>RUN_YYYYmmdd_HHMMSS</strong>.
            </td>
          </tr>

          <tr>
            <td class="col-key">UI ROOT</td>
            <td class="col-value">/home/test/Data/SECURITY_BUNDLE/ui</td>
            <td class="col-note">
              Chứa <code>app.py</code>, thư mục <code>templates/</code> và <code>static/</code> (CSS, JS, assets…).
            </td>
          </tr>

          <tr>
            <td class="col-key">JSON FINDINGS</td>
            <td class="col-value">
              <code>findings_unified.json</code> trong mỗi thư mục RUN_*
            </td>
            <td class="col-note">
              <strong>Đây là đầu vào chính</strong> cho bảng
              <strong>SAMPLE FINDINGS</strong>: mỗi record gồm
              <code>tool</code>, <code>severity</code>, <code>rule</code>,
              <code>location</code>, <code>message</code>.
              UI có thể lấy 20–40 record đầu để hiển thị ví dụ.
            </td>
          </tr>

          <tr>
            <td class="col-key">SUMMARY JSON</td>
            <td class="col-value">
              <code>summary_unified.json</code> (hoặc <code>summary.json</code>) trong mỗi RUN_*
            </td>
            <td class="col-note">
              UI dùng file này để build số liệu tổng hợp trên Dashboard (cards, charts…).
            </td>
          </tr>

          <tr>
            <td class="col-key">REPORT HTML</td>
            <td class="col-value">
              Thư mục <code>report/</code> trong mỗi RUN_* chứa:
              <ul class="mini-list">
                <li><code>security_resilient.html</code></li>
                <li><code>pm_style_report.html</code></li>
                <li><code>pm_style_report_print.html</code></li>
                <li><code>simple_report.html</code> (nếu có)</li>
              </ul>
            </td>
            <td class="col-note">
              Tab <strong>Run &amp; Report</strong> hiển thị link mở các file này.
            </td>
          </tr>

          <tr>
            <td class="col-key">CÁCH UI CHỌN RUN</td>
            <td class="col-value">
              UI quét tất cả thư mục bắt đầu bằng <code>RUN_</code> trong <code>out/</code>.
            </td>
            <td class="col-note">
              RUN mới nhất (theo tên thư mục) được dùng cho phần
              <strong>Last Run</strong> và làm default để đọc
              <code>findings_unified.json</code>, <code>summary_unified.json</code>.
            </td>
          </tr>

          <tr>
            <td class="col-key">YÊU CẦU TỐI THIỂU</td>
            <td class="col-value">
              Ít nhất 1 thư mục RUN_* hợp lệ trong
              <code>/home/test/Data/SECURITY_BUNDLE/out</code>.
            </td>
            <td class="col-note">
              Nếu chưa scan lần nào, hãy chạy
              <code>bin/run_all_tools_v2.sh</code> (hoặc script CI/CD tương đương).
            </td>
          </tr>

          <tr>
            <td class="col-key">DỌN DẸP DEMO</td>
            <td class="col-value">
              Có thể dời <code>RUN_DEMO_*</code> sang <code>out_demo/</code> hoặc <code>out_archive/</code>.
            </td>
            <td class="col-note">
              Giúp UI chỉ hiển thị các lần scan thực tế (prod / staging / client).
            </td>
          </tr>

          <tr>
            <td class="col-key">PORTAL DI CHUYỂN</td>
            <td class="col-value">
              Khi cần mang bundle sang máy khác để xem lại report:
              copy 2 thư mục <code>SECURITY_BUNDLE/out</code> và
              <code>SECURITY_BUNDLE/ui</code>.
            </td>
            <td class="col-note">
              Không bắt buộc phải chạy scan lại, chỉ cần start UI trên máy mới.
            </td>
          </tr>
        </tbody>
      </table>
    </div>
  </div>

  <!-- CARD 2: SAMPLE FINDINGS EXAMPLE IMAGE -->
  <div class="card mt-4">
    <div class="card-header">
      <h2 class="card-title">Sample Findings – ví dụ render từ JSON</h2>
    </div>
    <div class="card-body">
      <p class="card-text">
        Hình dưới đây minh hoạ cách UI đọc dữ liệu từ
        <code>findings_unified.json</code> (ví dụ lấy 20–40 bản ghi đầu)
        và render thành bảng <strong>SAMPLE FINDINGS</strong> với cột
        TOOL / SEV / RULE / LOCATION / MESSAGE.
      </p>
      <div class="sample-image-frame">
        <img
          src="{{ url_for('static', filename='img/sample_findings_gitleaks.png') }}"
          alt="Sample findings preview"
          class="sample-image"
        />
      </div>
    </div>
  </div>
</div>

<style>
  .page-section-label {
    font-size: 11px;
    letter-spacing: 0.14em;
    text-transform: uppercase;
    opacity: 0.7;
    margin-top: 8px;
    margin-bottom: 4px;
  }
  .table-caption {
    font-size: 11px;
    letter-spacing: 0.12em;
    text-transform: uppercase;
    opacity: 0.7;
    margin-bottom: 6px;
  }
  .sample-table {
    width: 100%;
    border-collapse: collapse;
    font-size: 13px;
  }
  .sample-table thead tr {
    text-align: left;
    font-size: 11px;
    text-transform: uppercase;
    letter-spacing: 0.08em;
  }
  .sample-table th,
  .sample-table td {
    padding: 6px 10px;
    border-bottom: 1px solid rgba(255,255,255,0.04);
    vertical-align: top;
  }
  .sample-table .col-key {
    white-space: nowrap;
    font-weight: 600;
  }
  .sample-table .col-value code {
    font-size: 12px;
  }
  .mini-list {
    margin: 4px 0 0 0;
    padding-left: 18px;
  }
  .sample-image-frame {
    margin-top: 10px;
    border-radius: 8px;
    overflow: hidden;
    border: 1px solid rgba(255,255,255,0.08);
  }
  .sample-image {
    width: 100%;
    display: block;
  }
</style>
{% endblock %}
HTML

echo "[DONE] Đã ghi lại templates/datasource.html (version FINAL: JSON input + sample image)."
