#!/usr/bin/env bash
set -euo pipefail

ROOT="/home/test/Data/SECURITY_BUNDLE"
UI="$ROOT/ui"
OUT="$ROOT/out"

SYNC="$UI/bin/sb_sync_summary_to_static.sh"
JS="$UI/static/sb_fill_toprisk_and_runs.js"
TPL="$UI/templates/index.html"

echo "[i] ROOT = $ROOT"
echo "[i] UI   = $UI"
echo "[i] OUT  = $OUT"

########################################
# 1) Script sync summary_unified -> static
########################################
cat > "$SYNC" <<'SH_EOF'
#!/usr/bin/env bash
set -euo pipefail

ROOT="/home/test/Data/SECURITY_BUNDLE"
OUT="$ROOT/out"
UI="$ROOT/ui"
STATIC_SUMMARY="$UI/static/summary_unified_latest.json"

echo "[i] ROOT  = $ROOT"
echo "[i] OUT   = $OUT"
echo "[i] DEST  = $STATIC_SUMMARY"

latest=$(ls -1d "$OUT"/RUN_* 2>/dev/null | sort | tail -n 1 || true)

if [ -z "$latest" ]; then
  echo "[ERR] Không tìm thấy thư mục RUN_* trong $OUT"
  exit 1
fi

SRC="$latest/report/summary_unified.json"

echo "[i] Latest RUN = $(basename "$latest")"
echo "[i] SRC summary = $SRC"

if [ ! -f "$SRC" ]; then
  echo "[ERR] Không thấy $SRC"
  exit 1
fi

cp "$SRC" "$STATIC_SUMMARY"
echo "[DONE] Đã copy $SRC -> $STATIC_SUMMARY"
SH_EOF

chmod +x "$SYNC"
echo "[OK] Đã tạo $SYNC"

########################################
# 2) JS: đọc summary_unified_latest và đổ 2 bảng
########################################
cat > "$JS" <<'JS_EOF';
document.addEventListener('DOMContentLoaded', function () {
  const tbRisk = document.querySelector('.sb-table-toprisk tbody');
  const tbRuns = document.querySelector('.sb-table-runs tbody');

  if (!tbRisk && !tbRuns) {
    console.warn('[SB-SUMMARY] Không tìm thấy tbody top_risks / runs.');
    return;
  }

  fetch('/static/summary_unified_latest.json', { cache: 'no-store' })
    .then(function (res) {
      if (!res.ok) throw new Error('HTTP ' + res.status);
      return res.json();
    })
    .then(function (summary) {
      console.log('[SB-SUMMARY] Đã load summary_unified_latest.json');

      // --------- TOP RISK FINDINGS ----------
      if (tbRisk) {
        var top = summary.top_risks || summary.topRisks ||
                  summary.top_findings || summary.topFindings || [];

        // clear placeholder
        while (tbRisk.firstChild) tbRisk.removeChild(tbRisk.firstChild);

        if (!Array.isArray(top) || top.length === 0) {
          var tr = document.createElement('tr');
          var td = document.createElement('td');
          td.colSpan = 4;
          td.className = 'muted';
          td.textContent = 'Chưa có dữ liệu top risk.';
          tr.appendChild(td);
          tbRisk.appendChild(tr);
        } else {
          top.forEach(function (f) {
            if (typeof f !== 'object' || !f) return;
            var tr = document.createElement('tr');

            function td(text) {
              var cell = document.createElement('td');
              cell.textContent = text || '';
              return cell;
            }

            var sev  = f.severity || f.SEVERITY || '';
            var tool = f.tool || f.scanner || f.SCAN_TOOL || '';
            var rule = f.rule || f.id || f.rule_id || '';
            var loc  = f.location || f.file || f.path || '';

            tr.appendChild(td(sev));
            tr.appendChild(td(tool));
            tr.appendChild(td(rule));
            tr.appendChild(td(loc));

            tbRisk.appendChild(tr);
          });
        }
      }

      // --------- TREND – LAST RUNS ----------
      if (tbRuns) {
        var runs = summary.runs || summary.trend_last_runs ||
                   summary.trendRuns || [];

        while (tbRuns.firstChild) tbRuns.removeChild(tbRuns.firstChild);

        if (!Array.isArray(runs) || runs.length === 0) {
          var tr = document.createElement('tr');
          var td = document.createElement('td');
          td.colSpan = 4;
          td.className = 'muted';
          td.textContent = 'Chưa có lịch sử RUN.';
          tr.appendChild(td);
          tbRuns.appendChild(tr);
        } else {
          runs.forEach(function (r) {
            if (typeof r !== 'object' || !r) return;
            var tr = document.createElement('tr');

            function td(text, cls) {
              var cell = document.createElement('td');
              if (cls) cell.className = cls;
              cell.textContent = text || '';
              return cell;
            }

            var name = r.name || r.run || r.id || '';
            var time = r.time || r.timestamp || '';
            var total = r.total || r.findings || 0;
            var ch = r.crit_high || r.critHigh || r.crit_high_str || '';

            tr.appendChild(td(name));
            tr.appendChild(td(time));
            tr.appendChild(td(String(total), 'right'));
            tr.appendChild(td(ch, 'right'));

            tbRuns.appendChild(tr);
          });
        }
      }
    })
    .catch(function (err) {
      console.warn('[SB-SUMMARY] Lỗi load summary_unified_latest.json:', err);
    });
});
JS_EOF

echo "[OK] Đã ghi $JS"

########################################
# 3) Chèn script vào index.html
########################################
if [ ! -f "$TPL" ]; then
  echo "[ERR] Không tìm thấy $TPL"
  exit 1
fi

python3 - "$TPL" <<'PY'
from pathlib import Path

path = Path("templates/index.html")
data = path.read_text(encoding="utf-8")

if "sb_fill_toprisk_and_runs.js" in data:
    print("[INFO] index.html đã include sb_fill_toprisk_and_runs.js – bỏ qua.")
else:
    snippet = '  <script src="{{ url_for(\'static\', filename=\'sb_fill_toprisk_and_runs.js\') }}"></script>\\n</body>'
    if "</body>" not in data:
        print("[ERR] Không thấy </body> trong index.html")
    else:
        data = data.replace("</body>", snippet)
        path.write_text(data, encoding="utf-8")
        print("[OK] Đã chèn script sb_fill_toprisk_and_runs.js trước </body>.")
PY

echo "[DONE] patch_ui_summary_to_static.sh hoàn thành."
