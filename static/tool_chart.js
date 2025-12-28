// tool_chart.js
// Vẽ biểu đồ bar đơn giản cho "Findings by tool"
// mount vào element có id="toolChart"

(function () {
  function renderToolChart(byTool) {
    const mount = document.getElementById("toolChart");
    if (!mount) {
      console.warn("[tool_chart] Không tìm thấy #toolChart");
      return;
    }

    mount.innerHTML = "";

    if (!byTool || typeof byTool !== "object") {
      mount.textContent = "Không có dữ liệu tool.";
      return;
    }

    if (typeof window.SECBUNDLE_normalizeTools !== "function") {
      console.warn("[tool_chart] Thiếu SECBUNDLE_normalizeTools (tool_config.js)");
      mount.textContent = "Thiếu cấu hình tool (tool_config.js).";
      return;
    }

    const rows = window.SECBUNDLE_normalizeTools(byTool)
      .filter(function (row) {
        return row.enabled && row.total > 0;
      });

    if (!rows.length) {
      mount.textContent = "Không có findings nào cho các tool bật.";
      return;
    }

    const maxTotal = rows.reduce(function (m, r) {
      return r.total > m ? r.total : m;
    }, 0);

    const wrapper = document.createElement("div");
    wrapper.className = "tool-chart-wrapper";

    rows.forEach(function (row) {
      const line = document.createElement("div");
      line.className = "tool-chart-line";

      const label = document.createElement("div");
      label.className = "tool-chart-label";
      label.textContent = row.label;

      const barContainer = document.createElement("div");
      barContainer.className = "tool-chart-bar-container";

      const bar = document.createElement("div");
      bar.className = "tool-chart-bar";

      const pct = maxTotal > 0 ? (row.total * 100 / maxTotal) : 0;
      bar.style.width = pct.toFixed(1) + "%";

      const value = document.createElement("span");
      value.className = "tool-chart-value";
      value.textContent = row.total.toString();

      barContainer.appendChild(bar);
      barContainer.appendChild(value);

      line.appendChild(label);
      line.appendChild(barContainer);

      wrapper.appendChild(line);
    });

    mount.appendChild(wrapper);
  }

  // Một chút CSS inline nhẹ để khỏi sửa file css riêng
  function injectStyles() {
    const id = "tool-chart-inline-style";
    if (document.getElementById(id)) return;
    const style = document.createElement("style");
    style.id = id;
    style.textContent = `
      #toolChart {
        padding: 8px 0;
        font-size: 12px;
      }
      .tool-chart-line {
        display: flex;
        align-items: center;
        margin-bottom: 6px;
        gap: 8px;
      }
      .tool-chart-label {
        flex: 0 0 140px;
        white-space: nowrap;
        overflow: hidden;
        text-overflow: ellipsis;
        opacity: 0.9;
      }
      .tool-chart-bar-container {
        position: relative;
        flex: 1;
        height: 18px;
        background: rgba(255,255,255,0.04);
        border-radius: 999px;
        overflow: hidden;
      }
      .tool-chart-bar {
        position: absolute;
        left: 0;
        top: 0;
        bottom: 0;
        border-radius: 999px;
        background: rgba(100, 181, 246, 0.9); /* xanh nhẹ, hợp theme dark */
      }
      .tool-chart-value {
        position: absolute;
        right: 8px;
        top: 50%;
        transform: translateY(-50%);
        font-size: 11px;
        opacity: 0.9;
      }
    `;
    document.head.appendChild(style);
  }

  injectStyles();

  // Expose global để dashboard gọi
  window.SECBUNDLE_renderToolChart = renderToolChart;
})();


// PATCH_GLOBAL_HIDE_8_7_AND_HELP
(function () {
  function hideStuff() {
    try {
      var nodes = document.querySelectorAll('*');
      nodes.forEach(function (el) {
        if (!el || !el.textContent) return;
        var txt = el.textContent;

        // 1) Ẩn đoạn help tiếng Việt ở SETTINGS – TOOL CONFIG
        if (txt.indexOf('Mỗi dòng tương ứng với 1 tool') !== -1 ||
            txt.indexOf('/home/test/Data/SECURITY_BUNDLE/ui/static/tool_config.json') !== -1) {
          if (el.parentElement) {
            el.parentElement.style.display = 'none';
          } else {
            el.style.display = 'none';
          }
          return;
        }

        // 2) Xóa riêng phần "8/7" trong header Crit/High
        if (txt.indexOf('Crit/High:') !== -1 && txt.indexOf('8/7') !== -1) {
          var html = el.innerHTML || '';
          html = html.split('8/7').join('');      // bỏ mọi "8/7"
          html = html.replace(/\s{2,}/g, ' ');    // gom bớt khoảng trắng
          el.innerHTML = html.trim();
        }
      });
    } catch (e) {
      console.log('PATCH_GLOBAL_HIDE_8_7_AND_HELP error', e);
    }
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', hideStuff);
  } else {
    hideStuff();
  }

  var obs = new MutationObserver(function () {
    hideStuff();
  });
  if (document.body) {
    obs.observe(document.body, { childList: true, subtree: true });
  }
})();
