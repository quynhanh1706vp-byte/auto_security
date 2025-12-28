#!/usr/bin/env python3
from pathlib import Path
import sys

TPL = Path("/home/test/Data/SECURITY_BUNDLE/ui/templates/dashboard.html")

if not TPL.is_file():
    print(f"[ERR] Không tìm thấy template: {TPL}", file=sys.stderr)
    sys.exit(1)

txt = TPL.read_text(encoding="utf-8")

# 1) Gỡ block TOOL_CHART_CLEAN_V1 nếu có
start_old = "<!-- TOOL_CHART_CLEAN_V1_START"
end_old = "<!-- TOOL_CHART_CLEAN_V1_END -->"
while True:
    s = txt.find(start_old)
    if s == -1:
        break
    e = txt.find(end_old, s)
    if e == -1:
        txt = txt[:s]
        break
    txt = txt[:s] + txt[e + len(end_old):]
print("[i] Đã gỡ TOOL_CHART_CLEAN_V1 (nếu có).")

marker = "TOOL_CHART_FORCE_V2_START"
if marker in txt:
    print("[i] TOOL_CHART_FORCE_V2 đã tồn tại, không thêm nữa.")
else:
    block = f"""
  <!-- {marker} -->
  <script>
  (function () {{
    alert("[tool_chart_force_v2] script loaded — nếu bạn thấy popup này nghĩa là JS đã chạy.");

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
        if (headers[0].indexOf("tool") !== -1 &&
            headers[headers.length - 1].indexOf("total") !== -1) {{
          console.log("[tool_chart_force_v2] Chọn bảng:", headers);
          return t;
        }}
      }}
      console.warn("[tool_chart_force_v2] Không tìm thấy bảng Findings by tool.");
      return null;
    }}

    function buildToolChart() {{
      console.log("[tool_chart_force_v2] buildToolChart()");

      var mount = document.createElement("div");
      mount.id = "toolChartForceV2";
      mount.style.margin = "12px 24px";
      mount.style.padding = "12px 16px";
      mount.style.borderRadius = "12px";
      mount.style.border = "1px solid rgba(159,168,255,0.5)";
      mount.style.background = "rgba(12, 19, 40, 0.95)";
      mount.style.boxShadow = "0 10px 30px rgba(0,0,0,0.6)";

      // chèn lên gần đầu body để dễ thấy
      var body = document.body;
      if (body.firstChild) {{
        body.insertBefore(mount, body.firstChild.nextSibling);
      }} else {{
        body.appendChild(mount);
      }}

      var table = findFindingsByToolTable();
      if (!table) {{
        mount.textContent = "Không tìm thấy bảng Findings by tool để vẽ chart.";
        return;
      }}

      var rows = table.querySelectorAll("tbody tr");
      if (!rows.length) {{
        mount.textContent = "Bảng Findings by tool chưa có dữ liệu.";
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
        mount.textContent = "Không có dữ liệu tool để vẽ chart.";
        return;
      }}

      var maxTotal = data.reduce(function (m, r) {{
        return r.total > m ? r.total : m;
      }}, 0);

      mount.innerHTML = "";
      var title = document.createElement("div");
      title.textContent = "Findings by tool (force chart v2)";
      title.style.fontSize = "14px";
      title.style.letterSpacing = "0.08em";
      title.style.textTransform = "uppercase";
      title.style.opacity = "0.9";
      title.style.marginBottom = "8px";
      mount.appendChild(title);

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

      mount.appendChild(wrapper);
      console.log("[tool_chart_force_v2] Đã vẽ chart:", data);
    }}

    window.addEventListener("load", buildToolChart);
  }})();
  </script>
  <!-- TOOL_CHART_FORCE_V2_END -->
"""

    idx_body = txt.lower().rfind("</body>")
    if idx_body != -1:
        txt = txt[:idx_body] + block + txt[idx_body:]
    else:
        txt = txt + block

TPL.write_text(txt, encoding="utf-8")
print(f"[OK] Đã thêm TOOL_CHART_FORCE_V2 vào {TPL}")
