#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"

echo "[i] ROOT = $ROOT"

python3 - <<'PY'
import os, io, sys

root = os.path.abspath(".")
print("[PY] Scan trong:", root)

needle = "Danh sách RUN trong thư mục out/"
candidates = []

# Tìm file nào có chứa câu "Danh sách RUN trong thư mục out/"
for dirpath, dirnames, filenames in os.walk(root):
    for fname in filenames:
        if not fname.lower().endswith((".html", ".htm", ".py")):
            continue
        fpath = os.path.join(dirpath, fname)
        try:
            with io.open(fpath, "r", encoding="utf-8") as f:
                data = f.read()
        except Exception as e:
            print(f"[PY] Bỏ qua {fpath} (không đọc được): {e}")
            continue

        if needle in data:
            print(f"[PY] FOUND run-page candidate: {fpath}")
            candidates.append((fpath, data))

if not candidates:
    print("[PY][ERR] Không tìm thấy file nào chứa 'Danh sách RUN trong thư mục out/'.")
    sys.exit(1)

# Lấy candidate đầu tiên (đa số sẽ chỉ có 1)
path, data = candidates[0]
print("[PY] Chọn file:", path)

marker = "PATCH_RUNS_PM_LINKS_V2"
if marker in data:
    print("[PY] File đã được patch trước đó (có marker), bỏ qua.")
    sys.exit(0)

snippet_js = """
<script>
// PATCH_RUNS_PM_LINKS_V2
(function () {
  function norm(t) {
    return (t || '').replace(/\\s+/g, ' ').trim();
  }

  function findRunsTable() {
    var tables = Array.from(document.querySelectorAll('table'));
    for (var i = 0; i < tables.length; i++) {
      var t = tables[i];
      var headers = Array.from(t.querySelectorAll('thead th, thead td'));
      var hasRun = false;
      var hasDetail = false;
      headers.forEach(function (h) {
        var txt = norm(h.textContent || '').toUpperCase();
        if (txt === 'RUN') hasRun = true;
        if (txt === 'CHI TIẾT' || txt === 'CHI TIET') hasDetail = true;
      });
      if (hasRun && hasDetail) return t;
    }
    return null;
  }

  function patch() {
    var table = findRunsTable();
    if (!table) {
      console.log('[RUNS-PM] Không tìm thấy bảng RUN.');
      return;
    }

    var headRow = table.tHead && table.tHead.rows[0];
    if (!headRow) return;

    var headCells = Array.from(headRow.cells);
    var idxRun = -1;
    var idxDetail = -1;

    headCells.forEach(function (c, i) {
      var txt = norm(c.textContent || '').toUpperCase();
      if (txt === 'RUN') idxRun = i;
      if (txt === 'CHI TIẾT' || txt === 'CHI TIET') idxDetail = i;
    });

    if (idxRun === -1 || idxDetail === -1) {
      console.log('[RUNS-PM] Không xác định được cột RUN / CHI TIẾT.');
      return;
    }

    var body = table.tBodies[0];
    if (!body) return;

    var patched = 0;

    Array.from(body.rows).forEach(function (row) {
      var cells = Array.from(row.cells);
      if (cells.length <= Math.max(idxRun, idxDetail)) return;

      var runId = norm(cells[idxRun].textContent || '');
      if (!runId || !/^RUN_/.test(runId)) return;

      var cell = cells[idxDetail];
      if (!cell || cell.getAttribute('data-pm-links-added') === '1') return;

      cell.setAttribute('data-pm-links-added', '1');

      function makeLink(label, fmt) {
        var a = document.createElement('a');
        a.textContent = label;
        a.href = '/pm_report/' + encodeURIComponent(runId) + '/' + fmt;
        a.target = '_blank';
        a.style.marginLeft = '4px';
        return a;
      }

      // Giữ "Xem chi tiết" cũ, thêm PM phía sau
      cell.appendChild(document.createTextNode(' | '));
      cell.appendChild(makeLink('PM HTML', 'html'));
      cell.appendChild(document.createTextNode(' / '));
      cell.appendChild(makeLink('PM PDF', 'pdf'));

      patched++;
    });

    console.log('[RUNS-PM] Đã thêm PM HTML/PDF cho ' + patched + ' dòng.');
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', patch);
  } else {
    patch();
  }
})();
</script>
</body>"""

if "</body>" in data:
    new_data = data.replace("</body>", snippet_js)
    with open(path, "w", encoding="utf-8") as f:
        f.write(new_data)
    print("[PY] Đã patch xong, chèn JS trước </body> trong", path)
else:
    # Không có </body>, append ở cuối file
    with open(path, "a", encoding="utf-8") as f:
        f.write(snippet_js.replace("</body>", ""))
    print("[PY] File không có </body>, đã append JS ở cuối file", path)
PY

echo "[DONE] patch_runs_add_pm_js_auto.sh hoàn thành."
