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
        Mô tả nguồn dữ liệu mà SECURITY BUNDLE UI sử dụng để hiển thị Dashboard, Run &amp; Report.
      </p>
    </div>
  </div>

  <!-- Card style giống SAMPLE FINDINGS -->
  <div class="card card-sample mt-4">
    <div class="card-header card-header-flex">
      <div>
        <div class="card-eyebrow">REFERENCE</div>
        <h2 class="card-title">DATA SOURCE – UI INPUT</h2>
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
              Chứa <code>app.py</code>, thư mục <code>templates/</code> và
              <code>static/</code> (CSS, JS, assets…).
            </td>
          </tr>

          <tr>
            <td class="col-key">SUMMARY</td>
            <td class="col-value">
              <code>summary_unified.json</code> hoặc <code>summary.json</code>
              trong mỗi thư mục RUN_*
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
              RUN mới nhất (theo tên thư mục) được dùng cho phần
              <strong>Last Run</strong> trên Dashboard.
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

          <tr>
            <td class="col-key">PORTAL DI CHUYỂN</td>
            <td class="col-value">
              Khi cần mang bundle sang máy khác để xem lại report:
              copy 2 thư mục
              <code>SECURITY_BUNDLE/out</code> và
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
</div>
{% endblock %}
HTML

echo "[DONE] Đã ghi lại templates/datasource.html với layout dạng bảng giống SAMPLE FINDINGS."
