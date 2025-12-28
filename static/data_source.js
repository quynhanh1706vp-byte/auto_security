let dataSourcePage = 1;
const DATA_SOURCE_PAGE_SIZE = 50;

function renderDataSourceError(msg) {
  const tbody = document.querySelector("#data-source-table tbody");
  const pager = document.querySelector("#data-source-pager");

  if (tbody) {
    tbody.innerHTML = "";
    const tr = document.createElement("tr");
    const td = document.createElement("td");
    td.colSpan = 6;
    td.textContent = msg;
    td.style.opacity = "0.7";
    tr.appendChild(td);
    tbody.appendChild(tr);
  }

  if (pager) {
    pager.innerHTML = "";
  }
}

async function loadDataSource(page = 1) {
  try {
    const res = await fetch(`/api/data_source?page=${page}&page_size=${DATA_SOURCE_PAGE_SIZE}`);
    const data = await res.json();

    const total = data.total || 0;
    const error = data.error;

    // === Không có dữ liệu hoặc lỗi → show message, không để trắng ===
    if (error || total === 0) {
      const msg = error
        ? `Data source: ${error}`
        : "Chưa có log nào cho RUN hiện tại. Hãy chạy một lần scan trước.";
      renderDataSourceError(msg);
      return;
    }

    dataSourcePage = data.page || 1;
    const totalPages = data.total_pages || 1;

    const tbody = document.querySelector("#data-source-table tbody");
    if (!tbody) {
      console.warn("Không tìm thấy #data-source-table tbody");
      return;
    }
    tbody.innerHTML = "";

    (data.rows || []).forEach(row => {
      const tr = document.createElement("tr");

      const tdTool = document.createElement("td");
      tdTool.textContent = row.tool || "";
      tr.appendChild(tdTool);

      const tdRule = document.createElement("td");
      tdRule.textContent = row.rule || "";
      tr.appendChild(tdRule);

      const tdFile = document.createElement("td");
      tdFile.textContent = row.file || "";
      tr.appendChild(tdFile);

      const tdLine = document.createElement("td");
      tdLine.textContent = row.line || "";
      tr.appendChild(tdLine);

      const tdMessage = document.createElement("td");
      tdMessage.textContent = row.message || "";
      tr.appendChild(tdMessage);

      const tdFix = document.createElement("td");
      tdFix.textContent = row.fix || "";
      tr.appendChild(tdFix);

      tbody.appendChild(tr);
    });

    const pager = document.querySelector("#data-source-pager");
    if (!pager) return;

    pager.innerHTML = `
      <button class="pager-btn" id="ds-prev" ${dataSourcePage <= 1 ? "disabled" : ""}>
        ◀ Prev
      </button>
      <span class="pager-text">
        Page ${dataSourcePage} / ${totalPages} &nbsp; • &nbsp; Total: ${total}
      </span>
      <button class="pager-btn" id="ds-next" ${dataSourcePage >= totalPages ? "disabled" : ""}>
        Next ▶
      </button>
    `;

    const prevBtn = document.querySelector("#ds-prev");
    const nextBtn = document.querySelector("#ds-next");

    if (prevBtn) {
      prevBtn.addEventListener("click", () => {
        if (dataSourcePage > 1) {
          loadDataSource(dataSourcePage - 1);
        }
      });
    }

    if (nextBtn) {
      nextBtn.addEventListener("click", () => {
        if (dataSourcePage < totalPages) {
          loadDataSource(dataSourcePage + 1);
        }
      });
    }
  } catch (err) {
    console.error("loadDataSource error:", err);
    renderDataSourceError("Không tải được dữ liệu Data Source (xem console/log để biết chi tiết).");
  }
}

document.addEventListener("DOMContentLoaded", () => {
  if (document.querySelector("#data-source-table")) {
    loadDataSource(1);
  }
});


// PATCH_HIDE_8_7_AND_HELP
(function () {
  function hideStuff() {
    try {
      var nodes = document.querySelectorAll('*');
      var patterns = [
        'Mỗi dòng tương ứng với 1 tool',
        'tool_config.json'
      ];
      nodes.forEach(function (el) {
        if (!el || !el.textContent) return;
        var txt = el.textContent.trim();

        // Ẩn badge 
        if (txt === '') {
          if (el.parentElement) el.parentElement.style.display = 'none';
          else el.style.display = 'none';
          return;
        }

        // Ẩn đoạn mô tả Settings – Tool config
        for (var i = 0; i < patterns.length; i++) {
          if (txt.indexOf(patterns[i]) !== -1) {
            if (el.parentElement) el.parentElement.style.display = 'none';
            else el.style.display = 'none';
            break;
          }
        }
      });
    } catch (e) {
      console.log('PATCH_HIDE_8_7_AND_HELP error', e);
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
