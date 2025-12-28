#!/usr/bin/env bash
set -euo pipefail

TPL="/home/test/Data/SECURITY_BUNDLE/ui/templates/dashboard.html"

if [ ! -f "$TPL" ]; then
  echo "[ERR] Không tìm thấy template: $TPL" >&2
  exit 1
fi

# Nếu đã chèn rồi thì thôi
if grep -q "INLINE_TOOL_CHART_START" "$TPL"; then
  echo "[i] dashboard.html đã có inline tool chart, bỏ qua."
  exit 0
fi

echo "[i] Thêm inline tool chart script vào $TPL"

cat >> "$TPL" <<'HTML'

<!-- INLINE_TOOL_CHART_START -->
<script>
(function () {
  function buildToolChartFromTable() {
    console.log("[inline_tool_chart] buildToolChartFromTable()");

    var mount = document.getElementById("toolChart");
    if (!mount) {
      console.warn("[inline_tool_chart] Không tìm thấy #toolChart");
      return;
    }

    // Tìm block "Findings by tool"
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
      console.warn("[inline_tool_chart] Không tìm thấy card 'Findings by tool'.");
      return;
    }

    var table = card.querySelector("table");
    if (!table) {
      console.warn("[inline_tool_chart] Không tìm thấy <table> trong card Findings by tool.");
      return;
    }

    var rows = table.querySelectorAll("tbody tr");
    if (!rows.length) {
      console.warn("[inline_tool_chart] Bảng Findings by tool chưa có dữ liệu.");
      return;
    }

    // Đọc Tool + Total từ bảng
    var data = [];
    rows.forEach ? rows.forEach(handleRow) : Array.prototype.forEach.call(rows, handleRow);

    function handleRow(tr) {
      var cells = tr.querySelectorAll("td,th");
      if (cells.length < 2) return;
      var label = (cells[0].textContent || "").trim();
      if (!label) return;
      var totalCell = cells[cells.length - 1];
      var raw = (totalCell.textContent || "").replace(/[^0-9]/g, "");
      var total = raw ? parseInt(raw, 10) : 0;
      data.push({ label: label, total: total });
    }

    if (!data.length) {
      console.warn("[inline_tool_chart] Không lấy được dữ liệu từ bảng.");
      return;
    }

    var maxTotal = data.reduce(function (m, r) {
      return r.total > m ? r.total : m;
    }, 0);

    // Dọn mount & vẽ chart
    mount.innerHTML = "";
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
      labelEl.style.flex = "0 0 140px";
      labelEl.style.whiteSpace = "nowrap";
      labelEl.style.overflow = "hidden";
      labelEl.style.textOverflow = "ellipsis";
      labelEl.style.opacity = "0.9";
      labelEl.textContent = row.label;

      var barContainer = document.createElement("div");
      barContainer.style.position = "relative";
      barContainer.style.flex = "1";
      barContainer.style.height = "18px";
      barContainer.style.background = "rgba(255,255,255,0.05)";
      barContainer.style.borderRadius = "999px";
      barContainer.style.overflow = "hidden";

      var bar = document.createElement("div");
      bar.style.position = "absolute";
      bar.style.left = "0";
      bar.style.top = "0";
      bar.style.bottom = "0";
      bar.style.borderRadius = "999px";
      bar.style.background = "rgba(100, 181, 246, 0.9)";

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
    console.log("[inline_tool_chart] Đã vẽ chart từ bảng Findings by tool.");
  }

  window.addEventListener("load", buildToolChartFromTable);
  window.SECBUNDLE_buildToolChartFromTable = buildToolChartFromTable;
})();
</script>
<!-- INLINE_TOOL_CHART_END -->
HTML

echo "[OK] Đã chèn inline tool chart vào $TPL"
