from pathlib import Path

p = Path("app.py")
text = p.read_text(encoding="utf-8")

# 1) Thêm CSS cho pill severity (CRITICAL/HIGH/MEDIUM/LOW)
css_old = """
    .severity-legend {
      display: flex;
      gap: 8px;
      margin-top: 6px;
      font-size: 11px;
      color: var(--text-soft);
    }
    .sev-dot {
      width: 8px;
      height: 8px;
      border-radius: 999px;
      display: inline-block;
      margin-right: 4px;
    }
    .sev-critical { background: #f97373; }
    .sev-high { background: #fb923c; }
    .sev-medium { background: #facc15; }
    .sev-low { background: #4ade80; }
"""

css_new = css_old + """
    .sev-pill {
      display: inline-flex;
      align-items: center;
      padding: 1px 7px;
      border-radius: 999px;
      font-size: 11px;
      font-weight: 500;
      border: 1px solid transparent;
    }
    .sev-pill-critical {
      background: rgba(248,113,113,0.18);
      border-color: rgba(248,113,113,0.75);
      color: #fecaca;
    }
    .sev-pill-high {
      background: rgba(251,146,60,0.18);
      border-color: rgba(251,146,60,0.75);
      color: #fed7aa;
    }
    .sev-pill-medium {
      background: rgba(250,204,21,0.18);
      border-color: rgba(250,204,21,0.75);
      color: #fef9c3;
    }
    .sev-pill-low {
      background: rgba(74,222,128,0.18);
      border-color: rgba(74,222,128,0.75);
      color: #bbf7d0;
    }
"""

if css_old not in text:
    print("[WARN] Không tìm thấy block CSS severity-legend, bỏ qua bước 1.")
else:
    text = text.replace(css_old, css_new)
    print("[OK] Đã thêm CSS sev-pill.")

# 2) Đổ màu bảng Severity buckets trong Data source
table_old = """
            <tbody>
              {% for sev in severity_order %}
              <tr>
                <td>{{ sev }}</td>
                <td>{{ sev_buckets[sev] }}</td>
              </tr>
              {% endfor %}
            </tbody>
"""

table_new = """
            <tbody>
              {% for sev in severity_order %}
              <tr>
                <td>
                  <span class="sev-pill sev-pill-{{ sev|lower }}">
                    {{ sev }}
                  </span>
                </td>
                <td>{{ sev_buckets[sev] }}</td>
              </tr>
              {% endfor %}
            </tbody>
"""

if table_old not in text:
    print("[WARN] Không tìm thấy bảng Severity buckets, bỏ qua bước 2.")
else:
    text = text.replace(table_old, table_new)
    print("[OK] Đã chỉnh bảng Severity buckets có màu.")

# 3) Đổ màu cột Sev trong SAMPLE FINDINGS
sev_cell_old = "<td>{{ f.severity }}</td>"
sev_cell_new = '<td><span class="sev-pill sev-pill-{{ f.severity|lower }}">{{ f.severity }}</span></td>'

if sev_cell_old not in text:
    print("[WARN] Không tìm thấy cột severity trong SAMPLE FINDINGS, bỏ qua bước 3.")
else:
    text = text.replace(sev_cell_old, sev_cell_new)
    print("[OK] Đã tô màu cột Sev trong SAMPLE FINDINGS.")

p.write_text(text, encoding="utf-8")
print("[DONE] patch_datasource_colors.py hoàn tất.")
