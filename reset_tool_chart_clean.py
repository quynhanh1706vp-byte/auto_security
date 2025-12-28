#!/usr/bin/env python3
from pathlib import Path
import sys

TPL = Path("/home/test/Data/SECURITY_BUNDLE/ui/templates/dashboard.html")

if not TPL.is_file():
    print(f"[ERR] Không tìm thấy template: {TPL}", file=sys.stderr)
    sys.exit(1)

txt = TPL.read_text(encoding="utf-8")

# 1) Gỡ toàn bộ các block thử nghiệm cũ
blocks = [
    ("<!-- INLINE_TOOL_CHART_V2_START", "<!-- INLINE_TOOL_CHART_V2_END"),
    ("<!-- INLINE_TOOL_CHART_V3_START", "<!-- INLINE_TOOL_CHART_V3_END"),
    ("<!-- INLINE_TOOL_CHART_START", "<!-- INLINE_TOOL_CHART_END"),
    ("<!-- INLINE_IFRAME_TOOL_CHART_START", "<!-- INLINE_IFRAME_TOOL_CHART_END"),
]

changed = False
for start, end in blocks:
    while True:
        s = txt.find(start)
        if s == -1:
            break
        e = txt.find(end, s)
        if e == -1:
            # không thấy END, cắt tới hết file luôn cho an toàn
            txt = txt[:s]
            changed = True
            break
        txt = txt[:s] + txt[e + len(end) :]
        changed = True

if changed:
    print("[i] Đã xoá các block tool chart cũ trong dashboard.html")

# 2) Thêm block mới sạch ở cuối <body> / cuối file
marker = "TOOL_CHART_CLEAN_V1_START"
if marker in txt:
    print("[i] Block TOOL_CHART_CLEAN_V1 đã tồn tại, không thêm nữa.")
else:
    block = f"""
  <!-- {marker} -->
  <div id="toolChartInline" style="margin: 24px 24px 32px 24px;"></div>
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
        // cột đầu có 'tool' và cột cuối có 'total'
        if (headers[0].indexOf("tool") !== -1 &&
            headers[headers.length - 1].indexOf("total") !== -1) {{
          console.log("[tool_chart_clean] Chọn bảng theo headers:", headers);
          return t;
        }}
      }}
      console.warn("[tool_chart_clean] Không tìm thấy bảng Findings by tool (theo header).");
      return null;
    }}

    function buildToolChart() {{
      console.log("[tool_chart_clean] buildToolChart()");

      var mount = document.getElementById("toolChartInline");
      if (!mount) {{
        console.warn("[tool_chart_clean] Không thấy #toolChartInline");
        return;
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
      title.textContent = "Findings by tool (chart)";
      title.style.fontSize = "13px";
      title.style.letterSpacing = "0.08em";
      title.style.textTransform = "uppercase";
      title.style.opacity = "0.8";
      title.style.marginBottom = "8px";
      mount.appendChild(title);

      var wrapper = document.createElement("div");
      wrapper.style.padding = "8px 0";

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
        barContainer.style.background = "rgba(255,255,255,0.04)";
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
        mount.textContent = "Không có dữ liệu tool để vẽ chart.";
        return;
      }}

      mount.appendChild(wrapper);
      console.log("[tool_chart_clean] Đã vẽ chart từ bảng Findings by tool.");
    }}

    window.addEventListener("load", buildToolChart);
    window.SECBUNDLE_buildToolChart_clean = buildToolChart;
  }})();
  </script>
  <!-- TOOL_CHART_CLEAN_V1_END -->
"""

    idx_body = txt.lower().rfind("</body>")
    if idx_body != -1:
        txt = txt[:idx_body] + block + txt[idx_body:]
    else:
        txt = txt + block

backup = TPL.with_suffix(TPL.suffix + ".bak_tool_chart_clean")
TPL.write_text(txt, encoding="utf-8")

print(f"[OK] Đã reset & thêm TOOL_CHART_CLEAN_V1 vào {TPL}")
print(f"[i] Backup: {backup}")
