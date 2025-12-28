(function () {
  // Lấy by_tool từ các biến global nếu backend có set sẵn
  function getByToolFromGlobals() {
    if (window.SUMMARY && window.SUMMARY.by_tool) {
      console.log("[tool_chart_auto] Dùng SUMMARY.by_tool từ global.");
      return window.SUMMARY.by_tool;
    }
    if (window.SECBUNDLE_LAST_SUMMARY && window.SECBUNDLE_LAST_SUMMARY.by_tool) {
      console.log("[tool_chart_auto] Dùng SECBUNDLE_LAST_SUMMARY.by_tool từ global.");
      return window.SECBUNDLE_LAST_SUMMARY.by_tool;
    }
    return null;
  }

  // Đọc từ bảng "Findings by tool" nếu không có JSON global
  function getByToolFromTable() {
    console.log("[tool_chart_auto] Thử đọc by_tool từ bảng 'Findings by tool'...");

    const candidates = Array.prototype.slice.call(
      document.querySelectorAll("h1,h2,h3,h4,h5,h6,div,span")
    );

    let card = null;
    for (const el of candidates) {
      const text = (el.textContent || "").trim().toLowerCase();
      if (!text) continue;
      if (text === "findings by tool" || text.indexOf("findings by tool") !== -1) {
        card = el.closest(".card") || el.parentElement;
        break;
      }
    }

    if (!card) {
      console.warn("[tool_chart_auto] Không tìm thấy block 'Findings by tool' theo text.");
      return null;
    }

    const table = card.querySelector("table");
    if (!table) {
      console.warn("[tool_chart_auto] Không tìm thấy <table> trong card Findings by tool.");
      return null;
    }

    const rows = table.querySelectorAll("tbody tr");
    if (!rows.length) {
      console.warn("[tool_chart_auto] Bảng Findings by tool chưa có dữ liệu (0 dòng).");
      return null;
    }

    const byTool = {};

    rows.forEach(function (tr) {
      const cells = tr.querySelectorAll("td,th");
      if (cells.length < 2) return;
      const label = (cells[0].textContent || "").trim();
      if (!label) return;

      const totalCell = cells[cells.length - 1];
      const raw = (totalCell.textContent || "").replace(/[^0-9]/g, "");
      const total = raw ? parseInt(raw, 10) : 0;

      byTool[label] = { total: total };
    });

    console.log("[tool_chart_auto] Đọc by_tool từ bảng:", byTool);
    return byTool;
  }

  function autoRenderToolChart() {
    if (typeof window.SECBUNDLE_renderToolChart !== "function") {
      console.warn("[tool_chart_auto] Chưa có SECBUNDLE_renderToolChart (tool_chart.js chưa load?).");
      return;
    }

    let byTool = getByToolFromGlobals();
    if (!byTool) {
      byTool = getByToolFromTable();
    }

    if (!byTool) {
      console.warn("[tool_chart_auto] Không lấy được dữ liệu by_tool để vẽ chart.");
      return;
    }

    console.log("[tool_chart_auto] Gọi SECBUNDLE_renderToolChart với by_tool:", byTool);
    window.SECBUNDLE_renderToolChart(byTool);
  }

  // Vẽ sau khi toàn bộ trang load xong (bảng đã render)
  window.addEventListener("load", function () {
    console.log("[tool_chart_auto] window.load → autoRenderToolChart()");
    autoRenderToolChart();
  });

  // Cho phép chỗ khác gọi lại sau khi reload RUN / upload JSON
  window.SECBUNDLE_autoToolChart = autoRenderToolChart;
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
