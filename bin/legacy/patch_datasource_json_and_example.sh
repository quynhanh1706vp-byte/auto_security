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
    <div class="page-title-wrap">
      <h1 class="page-title">Data Source</h1>
      <p class="page-subtitle">
        Mô tả file JSON và report HTML mà SECURITY BUNDLE UI sử dụng để build Dashboard và Sample Findings.
      </p>
    </div>
  </div>

  <!-- CARD 1: JSON / REPORT INPUT -->
  <div class="card card-sample mt-4">
    <div class="card-header card-header-flex">
      <div>
        <div class="card-eyebrow">DATA SOURCE</div>
        <h2 class="card-title">JSON OUTPUT &amp; REPORT INPUT</h2>
      </div>
      <div class="card-chip">READ ONLY</div>
    </div>

    <div class="card-body">
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
              Mỗi lần scan sinh ra một thư mục
              <strong>RUN_YYYYmmdd_HHMMSS</strong>.
            </td>
          </tr>

          <tr>
            <td class="col-key">UI ROOT</td>
            <td class="col-value">/home/test/Data/SECURITY_BUNDLE/ui</td>
            <td class="col-note">
              Chứa <code>app.py</code>, thư mục <code>templates/</code>, <code>static/</code>.
            </td>
          </tr>

          <tr>
            <td class="col-key">JSON FINDINGS</td>
            <td class="col-value">
              <code>findings_unified.json</code> trong mỗi thư mục RUN_*
            </td>
            <td class="col-note">
              Đây là <strong>đầu vào chính</strong> cho bảng
              <strong>SAMPLE FINDINGS</strong> (các bản ghi TOOL / SEV / RULE / LOCATION / MESSAGE).
            </td>
          </tr>

          <tr>
            <td class="col-key">SUMMARY JSON</td>
            <td class="col-value">
              <code>summary_unified.json</code> (hoặc <code>summary.json</code>)
              trong mỗi RUN_*
            </td>
            <td class="col-note">
              UI dùng file này để build số liệu tổng hợp (cards, charts…).
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
              UI quét tất cả thư mục bắt đầu bằng <code>RUN_</code> trong
              <code>out/</code>.
            </td>
            <td class="col-note">
              RUN mới nhất được dùng cho phần <strong>Last Run</strong>
              và để load <code>findings_unified.json</code> mặc định.
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
              <code>bin/run_all_tools_v2.sh</code> (hoặc script CI/CD của bạn).
            </td>
          </tr>

          <tr>
            <td class="col-key">DỌN DẸP DEMO</td>
            <td class="col-value">
              Có thể dời <code>RUN_DEMO_*</code> sang
              <code>out_demo/</code> hoặc <code>out_archive/</code>.
            </td>
            <td class="col-note">
              Giúp UI chỉ hiển thị các lần scan thực tế (prod / staging / client).
            </td>
          </tr>
        </tbody>
      </table>
    </div>
  </div>

  <!-- CARD 2: SAMPLE FINDINGS PREVIEW IMAGE -->
  <div class="card mt-4">
    <div class="card-header card-header-flex">
      <div>
        <div class="card-eyebrow">VISUAL EXAMPLE</div>
        <h2 class="card-title">Sample Findings – ví dụ 20 / 40 rules</h2>
      </div>
      <div class="card-chip">FROM JSON</div>
    </div>

    <div class="card-body">
      <p class="card-text">
        Hình dưới đây minh họa cách UI render bảng
        <strong>SAMPLE FINDINGS</strong> từ file
        <code>findings_unified.json</code>:
        mỗi dòng là một bản ghi với các trường
        <code>tool</code>, <code>severity</code>, <code>rule</code>,
        <code>location</code>, <code>message</code>.
      </p>

      <div class="sample-image-frame">
        <img
          src="{{ url_for('static', filename='img/sample_findings_gitleaks.png') }}"
          alt="Sample findings table preview"
          class="sample-image"
        />
      </div>
    </div>
  </div>
</div>

<style>
  .card-eyebrow {
    font-size: 10px;
    letter-spacing: 0.12em;
    text-transform: uppercase;
    opacity: 0.7;
    margin-bottom: 4px;
  }
  .card-chip {
    border-radius: 999px;
    padding: 4px 10px;
    font-size: 11px;
    border: 1px solid rgba(255,255,255,0.16);
    opacity: 0.9;
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

echo "[DONE] Đã ghi lại templates/datasource.html với mô tả JSON + ảnh sample findings."
