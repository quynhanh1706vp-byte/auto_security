(function () {
  document.addEventListener('DOMContentLoaded', function () {
    console.log('[SB-RUNS] init v3-ultra');

    // Lấy tbody bảng đầu tiên trên trang (RUN HISTORY)
    var tbody = document.querySelector('table tbody');
    if (!tbody) {
      console.warn('[SB-RUNS] Không tìm thấy <table><tbody> nào trên trang /runs.');
      return;
    }

    fetch('/api/runs', { cache: 'no-store' })
      .then(function (res) {
        if (!res.ok) throw new Error('HTTP ' + res.status);
        return res.json();
      })
      .then(function (data) {
        console.log('[SB-RUNS] /api/runs data =', data);

        // Chuẩn hoá data -> runs[]
        var runs = [];
        if (Array.isArray(data)) {
          runs = data;
        } else if (data && Array.isArray(data.runs)) {
          runs = data.runs;
        } else if (data && Array.isArray(data.data)) {
          runs = data.data;
        } else {
          console.warn('[SB-RUNS] /api/runs không trả list hợp lệ.', data);
        }

        // Xoá placeholder
        tbody.innerHTML = '';

        if (!runs || runs.length === 0) {
          var tr = document.createElement('tr');
          var td = document.createElement('td');
          td.colSpan = 7;
          td.textContent = 'Không có dữ liệu RUN (API trả rỗng).';
          tr.appendChild(td);
          tbody.appendChild(tr);
          return;
        }

        console.log('[SB-RUNS] Số RUN:', runs.length);

        // Nếu total>0 nhưng C/H/M/L ==0 hết -> cố enrich từ summary_unified.json
        var enrichPromises = runs.map(function (run) {
          var total = Number(run.total || 0);
          var crit  = Number(run.crit ?? run.critical ?? 0);
          var high  = Number(run.high ?? 0);
          var med   = Number(run.medium ?? run.med ?? 0);
          var low   = Number(run.low ?? 0);

          run.total  = total;
          run.crit   = crit;
          run.high   = high;
          run.medium = med;
          run.low    = low;

          var hasSeverity = (crit + high + med + low) > 0;
          if (!total || hasSeverity) {
            return Promise.resolve();
          }

          var runId = run.run_id || run.run || run.id || '';
          if (!runId) return Promise.resolve();

          var url = '/out/' + encodeURIComponent(runId) + '/report/summary_unified.json';
          console.log('[SB-RUNS] Enrich từ', url);

          return fetch(url, { cache: 'no-store' })
            .then(function (res) {
              if (!res.ok) throw new Error('HTTP ' + res.status);
              return res.json();
            })
            .then(function (s) {
              run.total  = Number(s.total ?? s.total_findings ?? s.total_all ?? total);
              run.crit   = Number(s.critical ?? s.crit ?? 0);
              run.high   = Number(s.high ?? 0);
              run.medium = Number(s.medium ?? s.med ?? 0);
              run.low    = Number(s.low ?? 0);
            })
            .catch(function (err) {
              console.warn('[SB-RUNS] Không lấy được summary_unified cho', runId, err);
            });
        });

        Promise.all(enrichPromises).then(function () {
          renderRunsTable(tbody, runs);
        });
      })
      .catch(function (err) {
        console.warn('[SB-RUNS] Lỗi load /api/runs:', err);
        tbody.innerHTML = '';
        var tr = document.createElement('tr');
        var td = document.createElement('td');
        td.colSpan = 7;
        td.textContent = 'Lỗi khi tải dữ liệu RUN từ API – xem console để biết chi tiết.';
        tr.appendChild(td);
        tbody.appendChild(tr);
      });
  });

  function renderRunsTable(tbody, runs) {
    tbody.innerHTML = '';
    runs.forEach(function (run) {
      var runId   = run.run_id || run.run || run.id || '';
      var time    = run.time || run.mtime || '';
      var total   = run.total  ?? 0;
      var crit    = run.crit   ?? run.critical ?? 0;
      var high    = run.high   ?? 0;
      var med     = run.medium ?? run.med ?? 0;
      var low     = run.low    ?? 0;
      var mode    = run.mode || '-';
      var profile = run.profile || '';

      var tr = document.createElement('tr');

      function td(text, cls) {
        var el = document.createElement('td');
        if (cls) el.className = cls;
        el.textContent = text;
        return el;
      }

      tr.appendChild(td(runId));
      tr.appendChild(td(time));
      tr.appendChild(td(String(total), 'right'));
      tr.appendChild(td(String(crit) + '/' + String(high), 'right'));
      tr.appendChild(td(String(med), 'right'));
      tr.appendChild(td(String(low), 'right'));
      tr.appendChild(td(mode + (profile ? ' / ' + profile : '')));

      var tdReport = document.createElement('td');
      tdReport.className = 'right';
      var link = document.createElement('a');
      link.href = '/report/' + encodeURIComponent(runId) + '/html';
      link.textContent = 'Open report';
      tdReport.appendChild(link);
      tr.appendChild(tdReport);

      tbody.appendChild(tr);
    });
  }
})();


// =========================================================
// VSP_RUNS_TABLE_ENHANCE_20251206
// - Gắn class .vsp-runs-table cho bảng RUN HISTORY
// - Đánh dấu ô severity để CSS có thể tô màu
// =========================================================
(function () {
  try {
    var table = document.querySelector("#tab-runs table");
    if (!table) {
      console.warn("[VSP][RUNS] Không tìm thấy bảng RUN HISTORY để enhance.");
      return;
    }
    table.classList.add("vsp-runs-table");

    // Gắn thêm data-role cho các cột severity (nếu header đã có)
    var headRow = table.tHead && table.tHead.rows[0];
    if (!headRow) return;

    var mapIdx = {};
    for (var i = 0; i < headRow.cells.length; i++) {
      var txt = (headRow.cells[i].textContent || "").trim().toUpperCase();
      if (txt === "CRI" || txt === "CRITICAL") mapIdx.CRITICAL = i;
      else if (txt === "HIGH") mapIdx.HIGH = i;
      else if (txt === "MED") mapIdx.MEDIUM = i;
      else if (txt === "LOW") mapIdx.LOW = i;
      else if (txt === "INFO") mapIdx.INFO = i;
      else if (txt === "TRACE") mapIdx.TRACE = i;
      else if (txt === "TOTAL") mapIdx.TOTAL = i;
    }

    var body = table.tBodies && table.tBodies[0];
    if (!body) return;

    for (var r = 0; r < body.rows.length; r++) {
      var row = body.rows[r];

      Object.keys(mapIdx).forEach(function (k) {
        var idx = mapIdx[k];
        if (idx == null) return;
        var cell = row.cells[idx];
        if (!cell) return;
        if (k === "TOTAL") {
          cell.classList.add("vsp-run-total");
        } else {
          cell.classList.add("vsp-run-sev-" + k.toLowerCase());
        }
      });

      // Run ID thường là cột đầu tiên
      var first = row.cells[0];
      if (first) {
        first.classList.add("vsp-run-id-cell");
      }
    }
  } catch (e) {
    console.warn("[VSP][RUNS] Enhance table error:", e);
  }
})();


// =========================================================
// VSP_RUNS_TABLE_PAGER_20251206
// - Phân trang bảng RUN HISTORY (10 / 20 / 50 / 100)
// =========================================================
(function () {
  if (window.VSP_RUNS_PAGER_INIT) return;
  window.VSP_RUNS_PAGER_INIT = true;

  try {
    var table = document.querySelector("#tab-runs table");
    if (!table || !table.tBodies || !table.tBodies[0]) {
      console.warn("[VSP][RUNS] Không tìm thấy bảng RUN HISTORY để phân trang.");
      return;
    }
    var tbody = table.tBodies[0];
    var allRows = Array.prototype.slice.call(tbody.rows || []);
    if (!allRows.length) return;

    // Tạo container pager dưới bảng
    var cardBody = table.parentElement;
    if (!cardBody) return;

    var pager = document.createElement("div");
    pager.className = "vsp-runs-pager";
    pager.innerHTML = [
      '<div class="vsp-runs-page-size">',
      'Rows per page:',
      ' <button type="button" data-size="10">10</button>',
      ' <button type="button" data-size="20">20</button>',
      ' <button type="button" data-size="50">50</button>',
      ' <button type="button" data-size="100">100</button>',
      "</div>",
      '<div class="vsp-runs-page-nav">',
      ' <button type="button" data-act="prev">&#171; Prev</button>',
      ' <span class="vsp-runs-page-label"></span>',
      ' <button type="button" data-act="next">Next &#187;</button>',
      "</div>"
    ].join("");
    cardBody.appendChild(pager);

    var pageSize = 20;
    var currentPage = 1;

    function pageCount() {
      return Math.max(1, Math.ceil(allRows.length / pageSize));
    }

    function renderPage() {
      var totalPages = pageCount();
      if (currentPage > totalPages) currentPage = totalPages;
      if (currentPage < 1) currentPage = 1;

      // Xóa tbody hiện tại và append lại đúng range
      while (tbody.firstChild) tbody.removeChild(tbody.firstChild);
      var start = (currentPage - 1) * pageSize;
      var end = start + pageSize;
      var slice = allRows.slice(start, end);
      slice.forEach(function (tr) { tbody.appendChild(tr); });

      var label = pager.querySelector(".vsp-runs-page-label");
      if (label) {
        label.textContent = "Page " + currentPage + " / " + totalPages +
          " \u2014 " + allRows.length + " runs";
      }

      var btnPrev = pager.querySelector('button[data-act="prev"]');
      var btnNext = pager.querySelector('button[data-act="next"]');
      if (btnPrev) btnPrev.disabled = (currentPage <= 1);
      if (btnNext) btnNext.disabled = (currentPage >= totalPages);
    }

    pager.addEventListener("click", function (e) {
      var t = e.target;
      if (!(t instanceof HTMLElement)) return;

      var size = t.getAttribute("data-size");
      if (size) {
        pageSize = parseInt(size, 10) || 10;
        currentPage = 1;
        renderPage();
        return;
      }

      var act = t.getAttribute("data-act");
      if (act === "prev") {
        currentPage -= 1;
        renderPage();
      } else if (act === "next") {
        currentPage += 1;
        renderPage();
      }
    });

    // Khởi tạo mặc định 20 dòng / trang
    renderPage();

  } catch (e) {
    console.warn("[VSP][RUNS] Pager error:", e);
  }
})();


// =========================================================
// VSP_RUNS_TIMESTAMP_FROM_RUNID_20251206
// - Suy timestamp human-readable từ RUN_ID cho bảng RUN HISTORY
//   Ví dụ: RUN_VSP_FULL_EXT_20251205_213813
//   -> 2025-12-05 21:38:13
// =========================================================
(function () {
  try {
    var table = document.querySelector("#tab-runs table");
    if (!table || !table.tBodies || !table.tBodies[0]) {
      console.warn("[VSP][RUNS] Không tìm thấy bảng RUN HISTORY để set timestamp.");
      return;
    }
    var thead = table.tHead;
    if (!thead || !thead.rows || !thead.rows[0]) return;

    var headRow = thead.rows[0];
    var idxRun = null, idxTs = null, idxSrc = null, idxUrl = null;

    for (var i = 0; i < headRow.cells.length; i++) {
      var txt = (headRow.cells[i].textContent || "").trim().toUpperCase();
      if (txt === "RUN ID") idxRun = i;
      else if (txt === "TIMESTAMP") idxTs = i;
      else if (txt === "SRC") idxSrc = i;
      else if (txt === "URL") idxUrl = i;
    }

    if (idxTs == null) {
      console.warn("[VSP][RUNS] Không có cột TIMESTAMP trong header, bỏ qua.");
      return;
    }
    if (idxRun == null) idxRun = 0;

    var tbody = table.tBodies[0];
    var rows = Array.prototype.slice.call(tbody.rows || []);

    function formatFromRunId(runId) {
      if (!runId) return "-";
      var m = /(\d{4})(\d{2})(\d{2})_(\d{2})(\d{2})(\d{2})$/.exec(runId);
      if (!m) return "-";
      var y = m[1], mo = m[2], d = m[3];
      var hh = m[4], mm = m[5], ss = m[6];
      return y + "-" + mo + "-" + d + " " + hh + ":" + mm + ":" + ss;
    }

    rows.forEach(function (row) {
      var runCell = row.cells[idxRun];
      var tsCell  = row.cells[idxTs];
      if (!runCell || !tsCell) return;

      var runId = (runCell.textContent || "").trim();
      var curTs = (tsCell.textContent || "").trim();

      if (!curTs || curTs === "-" || curTs === "—") {
        var formatted = formatFromRunId(runId);
        if (formatted !== "-") {
          tsCell.textContent = formatted;
        }
      }
      // SRC / URL: dùng đúng giá trị backend trả về; nếu backend thêm meta
      // thì sẽ hiện luôn, FE không cần sửa gì.
    });
  } catch (e) {
    console.warn("[VSP][RUNS] Timestamp-from-runid enhance error:", e);
  }
})();
