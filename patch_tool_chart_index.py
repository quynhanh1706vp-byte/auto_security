#!/usr/bin/env python3
from pathlib import Path
import sys

TPL = Path("/home/test/Data/SECURITY_BUNDLE/ui/templates/index.html")

if not TPL.is_file():
    print(f"[ERR] Không tìm thấy template: {TPL}", file=sys.stderr)
    sys.exit(1)

txt = TPL.read_text(encoding="utf-8")

marker = "TOOL_CHART_INDEX_V1_START"
if marker in txt:
    print("[i] TOOL_CHART_INDEX_V1 đã tồn tại trong index.html, bỏ qua.")
    sys.exit(0)

block = f"""
  <!-- {marker} -->
  <script>
  (function () {{
    function findFindingsByToolTable() {{
      var tables = document.querySelectorAll("table");
      for (var i = 0; i < tables.length; i++) {{
        var t = tables[i];
        var headerRow = t.querySelector("thead tr") || t.querySelector("tr");
        if (!headerRow) continue;
        var cells = headerRow.querySelectorAll("th,td");
        if (!cells.length) continue;

        var headers = [];
        for (var j = 0; j < cells.length; j++) {{
          headers.push((cells[j].textContent || "").trim().toLowerCase());
        }}
        if (!headers.length) continue;

        // Bảng Findings by tool: cột đầu 'tool', cột cuối 'total'
        if (headers[0].indexOf("tool") !== -1 &&
            headers[headers.length - 1].indexOf("total") !== -1) {{
          console.log("[tool_chart_index] Chọn bảng theo headers:", headers);
          return t;
        }}
      }
      console.warn("[tool_chart_index] Không tìm thấy bảng Findings by tool (theo header).");
      return null;
    }}

    function buildToolChartIndex() {{
      console.log("[tool_chart_index] buildToolChartIndex()");

      var table = findFindingsByToolTable();
      if (!table) return;

      var rows = table.querySelectorAll("tbody tr");
      if (!rows.length) {{
        console.warn("[tool_chart_index] Bảng Findings by tool chưa có dữ liệu.");
        return;
      }}

      var data = [];
      Array.prototype.forEach.call(rows, function (tr) {{
        var cells = tr.querySelectorAll("td,th");
        if (cells.length < 2) return;
        var label = (cells[0].textContent || "").trim();
        if (!label) return;
        var totalCell = cells[cells.length - 1];
        var raw = (totalCell.textContent || "").replace(/[^0-9]/g, "");
        var total = raw ? parseInt(raw, 10) : 0;
        data.push({{ label: label, total: total }});
      }});

      if (!data.length) {{
        console.warn("[tool_chart_index] Không lấy được dữ liệu từ bảng.");
        return;
      }}

      var maxTotal = data.reduce(function (m, r) {{
        return r.total > m ? r.total : m;
      }}, 0);

      // Tạo khối chart nằm ngay phía dưới bảng
      var chart = document.createElement("div");
      chart.id = "toolChartIndex";
      chart.style.marginTop = "16px";
      chart.style.padding = "12px 16px";
      chart.style.borderRadius = "12px";
      chart.style.border = "1px solid rgba(159,168,255,0.35)";
      chart.style.background = "rgba(6,10,24,0.95)";

      var title = document.createElement("div");
      title.textContent = "Findings by tool (chart)";
      title.style.fontSize = "13px";
      title.style.letterSpacing = "0.08em";
      title.style.textTransform = "uppercase";
      title.style.opacity = "0.85";
      title.style.marginBottom = "8px";
      chart.appendChild(title);

      var wrapper = document.createElement("div");
      wrapper.style.padding = "4px 0";

      data.forEach(function (row) {{
        if (!row.total) return;

        var line = document.createElement("div");
        line.style.display = "flex";
        line.style.alignItems = "center";
        line.style.marginBottom = "6px";
        line.style.gap = "8px";

        var labelEl = document.createElement("div");
        labelEl.style.flex = "0 0 180px";
        labelEl.style.whiteSpace = "nowrap";
        labelEl.style.overflow = "hidden";
        labelEl.style.textOverflow = "ellipsis";
        labelEl.style.opacity = "0.9";
        labelEl.style.fontSize = "12px";
        labelEl.textContent = row.label;

        var barContainer = document.createElement("div");
        barContainer.style.position = "relative";
        barContainer.style.flex = "1";
        barContainer.style.height = "18px";
        barContainer.style.background = "rgba(255,255,255,0.06)";
        barContainer.style.borderRadius = "999px";
        barContainer.style.overflow = "hidden";

        var bar = document.createElement("div");
        bar.style.position = "absolute";
        bar.style.left = "0";
        bar.style.top = "0";
        bar.style.bottom = "0";
        bar.style.borderRadius = "999px";
        bar.style.background = "linear-gradient(90deg, #64b5f6, #7986cb)";

        var pct = maxTotal > 0 ? (row.total * 100 / maxTotal) : 0;
        bar.style.width = pct.toFixed(1) + "%";

        var value = document.createElement("span");
        value.style.position = "absolute";
        value.style.right = "8px";
        value.style.top = "50%";
        value.style.transform = "translateY(-50%)";
        value.style.fontSize = "11px";
        value.style.opacity = "0.9";
        value.textContent = String(row.total);

        barContainer.appendChild(bar);
        barContainer.appendChild(value);

        line.appendChild(labelEl);
        line.appendChild(barContainer);

        wrapper.appendChild(line);
      }});

      if (!wrapper.children.length) {{
        chart.textContent = "Không có dữ liệu tool để vẽ chart.";
      }} else {{
        chart.appendChild(wrapper);
      }}

      // chèn chart ngay sau bảng
      if (table.parentElement) {{
        if (table.nextSibling) {{
          table.parentElement.insertBefore(chart, table.nextSibling);
        }} else {{
          table.parentElement.appendChild(chart);
        }}
      }} else {{
        document.body.appendChild(chart);
      }}

      console.log("[tool_chart_index] Đã vẽ chart:", data);
    }}

    window.addEventListener("load", buildToolChartIndex);
    window.SECBUNDLE_buildToolChartIndex = buildToolChartIndex;
  }})();
  </script>
  <!-- TOOL_CHART_INDEX_V1_END -->
"""

# chèn block trước </body> (nếu có) hoặc cuối file
idx_body = txt.lower().rfind("</body>")
if idx_body != -1:
    txt = txt[:idx_body] + block + txt[idx_body:]
else:
    txt = txt + block

backup = TPL.with_suffix(TPL.suffix + ".bak_tool_chart_index")
TPL.write_text(txt, encoding="utf-8")

print(f"[OK] Đã chèn TOOL_CHART_INDEX_V1 vào {TPL}")
print(f"[i] Backup: {backup}")
