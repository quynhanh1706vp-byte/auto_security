#!/usr/bin/env bash
set -euo pipefail

ROOT="/home/test/Data/SECURITY_BUNDLE/ui"
APP="$ROOT/app.py"
TPL="$ROOT/templates/index.html"
JS="$ROOT/static/patch_dashboard_top_risks.js"

echo "[i] ROOT = $ROOT"
echo "[i] APP  = $APP"
echo "[i] TPL  = $TPL"
echo "[i] JS   = $JS"

if [ ! -f "$APP" ]; then
  echo "[ERR] Không tìm thấy $APP"
  exit 1
fi

if [ ! -f "$TPL" ]; then
  echo "[ERR] Không tìm thấy $TPL"
  exit 1
fi

mkdir -p "$(dirname "$JS")"

########################################
# 1) Tạo JS patch: fill TOP RISK FINDINGS
########################################
cat > "$JS" <<'JS'
(function () {
  function log(msg) {
    console.log('[DASH-TOP]', msg);
  }

  function findTopRiskTableBody() {
    // Tìm box có chữ "TOP RISK FINDINGS"
    var all = Array.prototype.slice.call(document.querySelectorAll('*'));
    var container = null;

    for (var i = 0; i < all.length; i++) {
      var el = all[i];
      var txt = (el.textContent || '').toUpperCase();
      if (txt.indexOf('TOP RISK FINDINGS') !== -1) {
        container = el;
        break;
      }
    }

    if (!container) {
      log('Không tìm thấy container "TOP RISK FINDINGS".');
      return null;
    }

    // Tìm table gần nhất bên dưới container
    var table = container.querySelector('table');
    if (!table) {
      // thử đi xuống vài cấp
      var descendants = container.getElementsByTagName('table');
      if (descendants && descendants.length > 0) {
        table = descendants[0];
      }
    }

    if (!table) {
      log('Không tìm thấy <table> bên trong TOP RISK FINDINGS container.');
      return null;
    }

    var tbody = table.querySelector('tbody') || table;
    return tbody;
  }

  function renderTopRisks(data) {
    if (!data || !data.top_risks) {
      log('Không có top_risks trong JSON.');
      return;
    }

    var tbody = findTopRiskTableBody();
    if (!tbody) return;

    // Xoá các dòng cũ
    while (tbody.firstChild) {
      tbody.removeChild(tbody.firstChild);
    }

    var list = data.top_risks;
    if (!list.length) {
      var tr = document.createElement('tr');
      var td = document.createElement('td');
      td.colSpan = 4;
      td.textContent = 'Chưa có dữ liệu để tổng hợp rủi ro.';
      tr.appendChild(td);
      tbody.appendChild(tr);
      return;
    }

    list.forEach(function (item) {
      var tr = document.createElement('tr');

      function cell(text) {
        var td = document.createElement('td');
        td.textContent = text || '';
        return td;
      }

      tr.appendChild(cell(item.severity || ''));
      tr.appendChild(cell(item.tool || ''));
      tr.appendChild(cell(item.rule || ''));
      tr.appendChild(cell(item.location || ''));

      tbody.appendChild(tr);
    });
  }

  function fetchAndRender() {
    fetch('/api/top_risks', { method: 'GET' })
      .then(function (res) { return res.json(); })
      .then(function (data) {
        log('Nhận dữ liệu top_risks:', data);
        renderTopRisks(data);
      })
      .catch(function (err) {
        console.error('[DASH-TOP] Lỗi fetch /api/top_risks:', err);
      });
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', fetchAndRender);
  } else {
    fetchAndRender();
  }
})();
JS

echo "[OK] Đã ghi $JS"

########################################
# 2) Hook JS vào templates/index.html
########################################
python3 - "$TPL" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
data = path.read_text(encoding="utf-8")

snippet = "patch_dashboard_top_risks.js"
if snippet in data:
    print("[INFO] templates/index.html đã include patch_dashboard_top_risks.js, bỏ qua.")
    raise SystemExit(0)

insert = '    <script src="{{ url_for(\'static\', filename=\'patch_dashboard_top_risks.js\') }}"></script>\\n</body>'

if "</body>" not in data:
    print("[ERR] Không tìm thấy </body> trong templates/index.html")
    raise SystemExit(1)

new_data = data.replace("</body>", insert)
path.write_text(new_data, encoding="utf-8")
print("[OK] Đã chèn script patch_dashboard_top_risks.js trước </body>.")
PY

########################################
# 3) Thêm API /api/top_risks vào app.py
########################################
python3 - "$APP" <<'PY'
from pathlib import Path
import sys, textwrap

path = Path(sys.argv[1])
data = path.read_text(encoding="utf-8")

if "/api/top_risks" in data:
    print("[INFO] app.py đã có /api/top_risks, bỏ qua.")
    raise SystemExit(0)

block = '''
@app.route("/api/top_risks", methods=["GET"])
def api_top_risks():
    """
    Trả về top 10 findings có severity CRITICAL/HIGH + thống kê bucket.
    Dùng findings_unified.json của RUN_* mới nhất.
    """
    import json, os
    from pathlib import Path
    from collections import Counter

    ROOT = Path(__file__).resolve().parent.parent  # /home/test/Data/SECURITY_BUNDLE
    out_dir = ROOT / "out"

    result = {
        "run": None,
        "total": 0,
        "buckets": {},
        "top_risks": [],
    }

    if not out_dir.is_dir():
        return result

    latest_run = None
    for name in sorted(os.listdir(out_dir)):
        if name.startswith("RUN_2"):  # chỉ lấy RUN_YYYYmmdd_...
            latest_run = name

    if not latest_run:
        return result

    run_dir = out_dir / latest_run
    report_dir = run_dir / "report"
    findings_path = report_dir / "findings_unified.json"

    result["run"] = latest_run

    if not findings_path.is_file():
        return result

    try:
        with findings_path.open("r", encoding="utf-8") as f:
            data = json.load(f)
    except Exception:
        return result

    if isinstance(data, dict) and "findings" in data:
        findings = data["findings"]
    elif isinstance(data, list):
        findings = data
    else:
        return result

    def norm_sev(raw):
        if not raw:
            return "INFO"
        s = str(raw).upper()
        if s.startswith("CRIT"):
            return "CRITICAL"
        if s.startswith("HI"):
            return "HIGH"
        if s.startswith("MED"):
            return "MEDIUM"
        if s.startswith("LO"):
            return "LOW"
        if s.startswith("INFO") or s.startswith("INFORMATIONAL"):
            return "INFO"
        return "INFO"

    sev_counter = Counter()
    total = 0
    top_candidates = []

    for f in findings:
        sev = (
            f.get("severity")
            or f.get("sev")
            or f.get("severity_norm")
            or f.get("severity_normalized")
            or f.get("level")
            or "INFO"
        )
        s = norm_sev(sev)
        sev_counter[s] += 1
        total += 1

        if s in ("CRITICAL", "HIGH"):
            tool = f.get("tool") or f.get("source") or f.get("engine") or "?"
            rule = f.get("rule_id") or f.get("id") or f.get("check_id") or "?"
            location = (
                f.get("location")
                or f.get("path")
                or f.get("file")
                or ""
            )
            # thêm line nếu có
            line = f.get("line") or f.get("start_line") or None
            if line:
                location = f"{location}:{line}" if location else str(line)

            top_candidates.append({
                "severity": s,
                "tool": tool,
                "rule": rule,
                "location": location,
            })

    # đảm bảo đủ bucket
    for k in ["CRITICAL", "HIGH", "MEDIUM", "LOW", "INFO"]:
        sev_counter.setdefault(k, 0)

    result["total"] = total
    result["buckets"] = dict(sev_counter)

    # sort CRITICAL trước HIGH, giới hạn 10
    weight = {"CRITICAL": 2, "HIGH": 1}
    top_candidates.sort(
        key=lambda x: (weight.get(x["severity"], 0), x.get("tool") or ""),
        reverse=True,
    )
    result["top_risks"] = top_candidates[:10]

    return result
'''

# Cố gắng chèn trước block if __name__ == "__main__", nếu có
marker = 'if __name__ == "__main__":'
if marker in data:
    new_data = data.replace(marker, textwrap.dedent(block) + "\n\n" + marker, 1)
else:
    new_data = data.rstrip() + "\n\n" + textwrap.dedent(block) + "\n"

path.write_text(new_data, encoding="utf-8")
print("[OK] Đã thêm route /api/top_risks vào app.py")
PY

echo "[DONE] patch_dashboard_top_risks.sh hoàn thành."
