#!/usr/bin/env python3
from pathlib import Path
import sys

TPL = Path("/home/test/Data/SECURITY_BUNDLE/ui/templates/dashboard.html")

if not TPL.is_file():
    print(f"[ERR] Không tìm thấy template: {TPL}", file=sys.stderr)
    sys.exit(1)

txt = TPL.read_text(encoding="utf-8")

marker = "INLINE_TOOL_CHART_V2_START"
if marker in txt:
    print("[i] dashboard.html đã có inline tool chart v2, bỏ qua.")
    sys.exit(0)

# Mình không cố chèn đúng giữa card nữa, mà chỉ cần đảm bảo nó nằm cuối trang.
# Chart vẫn sẽ đọc bảng 'Findings by tool' hiện có để vẽ đúng số.
block = """
  <!-- INLINE_TOOL_CHART_V2_START -->
  <div id="toolChartInline" style="margin: 24px 24px 32px 24px;"></div>
  <script>
  (function () {
    function buildToolChart() {
      console.log("[inline_tool_chart_v2] buildToolChart()");

      var mount = document.getElementById("toolChartInline");
      if (!mount) {
        console.warn("[inline_tool_chart_v2] Không thấy #toolChartInline");
        return;
      }

      // Tìm card có tiêu đề 'Findings by tool'
      var candidates = Array.prototype.slice.call(
        document.querySelectorAll("h1,h2,h3,h4,h5,h6,div,span")
      );
      var card = null;
      for (var i = 0; i < candidates.length; i++) {
        var el = candidates[i];
        var text = (el.textContent || "").trim().toLowerCase();
        if (!text) continue;
        if (text === "findings by tool" || text.indexOf("findings by tool") !== -1) {
          card = el.closest(".card") || el.parentElement;
          break;
        }
      }
      if (!card) {
        console.warn("[inline_tool_chart_v2] Không tìm thấy card 'Findings by tool'.");
        return;
      }

      var table = card.querySelector("table");
      if (!table) {
        console.warn("[inline_tool_chart_v2] Không tìm thấy <table> trong card Findings by tool.");
        return;
      }

      var rows = table.querySelectorAll("tbody tr");
      if (!rows.length) {
        console.warn("[inline_tool_chart_v2] Bảng Findings by tool chưa có dữ liệu.");
        return;
      }

      // Đọc Tool + Total từ bảng
      var data = [];
      Array.prototype.forEach.call(rows, function (tr) {
        var cells = tr.querySelectorAll("td,th");
        if (cells.length < 2) return;
        var label = (cells[0].textContent || "").trim();
        if (!label) return;
        var totalCell = cells[cells.length - 1];
        var raw = (totalCell.textContent || "").replace(/[^0-9]/g, "");
        var total = raw ? parseInt(raw, 10) : 0;
        data.push({ label: label, total: total });
      });

      if (!data.length) {
        console.warn("[inline_tool_chart_v2] Không lấy được dữ liệu từ bảng.");
        return;
      }

      var maxTotal = data.reduce(function (m, r) {
        return r.total > m ? r.total : m;
      }, 0);

      // Vẽ chart
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

      data.forEach(function (row) {
        if (!row.total) return; // bỏ tool 0 findings

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
      });

      if (!wrapper.children.length) {
        mount.textContent = "Không có dữ liệu tool để vẽ chart.";
        return;
      }

      mount.appendChild(wrapper);
      console.log("[inline_tool_chart_v2] Đã vẽ chart từ bảng Findings by tool.");
    }

    window.addEventListener("load", buildToolChart);
    window.SECBUNDLE_buildToolChart_v2 = buildToolChart;
  })();
  </script>
  <!-- INLINE_TOOL_CHART_V2_END -->
"""

# nếu có </body> thì chèn trước đó, không thì append cuối file
idx_body = txt.lower().rfind("</body>")
if idx_body != -1:
    new_txt = txt[:idx_body] + block + txt[idx_body:]
else:
    new_txt = txt + block

backup = TPL.with_suffix(TPL.suffix + ".bak_chartv2")
backup.write_text(txt, encoding="utf-8")
TPL.write_text(new_txt, encoding="utf-8")

print(f"[OK] Đã chèn inline tool chart v2 vào {TPL}")
print(f"[i] Backup: {backup}")
