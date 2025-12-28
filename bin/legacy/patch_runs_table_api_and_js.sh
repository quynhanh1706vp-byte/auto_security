#!/usr/bin/env bash
set -euo pipefail

ROOT="/home/test/Data/SECURITY_BUNDLE/ui"
cd "$ROOT"
APP="app.py"

echo "[i] ROOT = $ROOT"
echo "[i] APP  = $APP"

python3 - "$APP" <<'PY'
from pathlib import Path
import textwrap

app_path = Path("app.py")
txt = app_path.read_text(encoding="utf-8")
orig = txt

# Thêm import jsonify nếu thiếu
if "from flask import " in txt and "jsonify" not in txt:
    txt = txt.replace("from flask import ", "from flask import jsonify, ", 1)

# Thêm route /api/runs_table nếu chưa có
if "/api/runs_table" not in txt:
    block = textwrap.dedent("""
    @app.route('/api/runs_table')
    def api_runs_table():
        \"\"\"Trả JSON list các *_RUN_* trong out/ cho tab Runs & Reports.\"\"\"
        from pathlib import Path
        import json, datetime
        root = Path('/home/test/Data/SECURITY_BUNDLE')
        out_dir = root / 'out'
        rows = []
        if out_dir.is_dir():
            for p in sorted(out_dir.glob('*_RUN_*')):
                if not p.is_dir():
                    continue
                report_dir = p / 'report'
                summary = report_dir / 'summary_unified.json'
                total = crit = high = 0
                mode = '-'
                src = '-'
                if summary.is_file():
                    try:
                        data = json.loads(summary.read_text(encoding='utf-8'))
                        total = int(data.get('total', 0))
                        crit = int(data.get('critical', 0))
                        high = int(data.get('high', 0))
                        src = data.get('src_folder') or data.get('src') or '-'
                        mode = data.get('mode') or '-'
                    except Exception:
                        pass
                mtime = datetime.datetime.fromtimestamp(p.stat().st_mtime)
                rows.append({
                    "run": p.name,
                    "time": mtime.strftime('%Y-%m-%d %H:%M:%S'),
                    "src": src,
                    "total": total,
                    "crit": crit,
                    "high": high,
                    "mode": mode,
                })
            rows.sort(key=lambda r: r["time"], reverse=True)
        return jsonify(rows)
    """)
    txt = txt + "\n" + block

if txt != orig:
    app_path.write_text(txt, encoding="utf-8")
    print("[OK] app.py updated với /api/runs_table")
else:
    print("[INFO] app.py đã có /api/runs_table hoặc không cần đổi")
PY

########################################
# Tạo JS client fill table
########################################
cat > static/js/runs_table_fill.js <<'JS'
document.addEventListener('DOMContentLoaded', () => {
  const tbody = document.querySelector('#runs-tbody');
  if (!tbody) return;

  fetch('/api/runs_table')
    .then(r => r.json())
    .then(rows => {
      tbody.innerHTML = '';
      if (!rows || !rows.length) {
        const tr = document.createElement('tr');
        const td = document.createElement('td');
        td.colSpan = 7;
        td.textContent = 'Chưa có RUN nào trong out/. Hãy chạy scan trước.';
        td.style.textAlign = 'center';
        td.style.opacity = '0.75';
        tr.appendChild(td);
        tbody.appendChild(tr);
        return;
      }
      for (const r of rows) {
        const tr = document.createElement('tr');

        const tdRun = document.createElement('td');
        tdRun.textContent = r.run;
        tr.appendChild(tdRun);

        const tdTime = document.createElement('td');
        tdTime.textContent = r.time || '-';
        tr.appendChild(tdTime);

        const tdSrc = document.createElement('td');
        tdSrc.textContent = r.src || '-';
        tr.appendChild(tdSrc);

        const tdTotal = document.createElement('td');
        tdTotal.textContent = r.total ?? '-';
        tr.appendChild(tdTotal);

        const tdCritHigh = document.createElement('td');
        tdCritHigh.textContent = (r.crit ?? 0) + ' / ' + (r.high ?? 0);
        tr.appendChild(tdCritHigh);

        const tdMode = document.createElement('td');
        tdMode.textContent = r.mode || '-';
        tr.appendChild(tdMode);

        const tdReports = document.createElement('td');
        tdReports.innerHTML =
          '<a href="/pm_report/' + encodeURIComponent(r.run) + '/html" target="_blank">HTML</a>' +
          ' \u00b7 ' +
          '<a href="/pm_report/' + encodeURIComponent(r.run) + '/pdf" target="_blank">PDF</a>';
        tr.appendChild(tdReports);

        tbody.appendChild(tr);
      }
    })
    .catch(err => {
      console.error('ERR runs_table_fill:', err);
    });
});
JS

########################################
# Patch runs.html: thêm id cho tbody + include JS
########################################
TPL="templates/runs.html"
python3 - "$TPL" <<'PY'
from pathlib import Path

path = Path("templates/runs.html")
data = path.read_text(encoding='utf-8')
orig = data

# Đổi tbody đầu tiên thành tbody có id
if '<tbody>' in data and 'id="runs-tbody"' not in data:
    data = data.replace('<tbody>', '<tbody id="runs-tbody">', 1)

# Chèn script nếu chưa có
if 'runs_table_fill.js' not in data:
    marker = '</body>'
    snippet = "  <script src=\"{{ url_for('static', filename='js/runs_table_fill.js') }}\"></script>\n"
    if marker in data:
        data = data.replace(marker, snippet + marker, 1)

if data != orig:
    path.write_text(data, encoding='utf-8')
    print("[OK] runs.html patched (tbody id + script)")
else:
    print("[INFO] runs.html đã có patch cần thiết")
PY

echo "[DONE] patch_runs_table_api_and_js.sh hoàn thành."
