#!/usr/bin/env bash
set -euo pipefail

ROOT="/home/test/Data/SECURITY_BUNDLE/ui"
cd "$ROOT"

TPL="templates/index.html"
JS="static/patch_dashboard_top_risks.js"
APP="app.py"

echo "[i] ROOT = $ROOT"
echo "[i] TPL  = $TPL"
echo "[i] JS   = $JS"
echo "[i] APP  = $APP"

########################################
# 1) Ghi lại JS patch TOP RISK FINDINGS
########################################
cat > "$JS" <<'JS'
(function () {
  function log(msg) {
    console.log('[TOP-RISKS]', msg);
  }

  async function fetchTopRisks() {
    try {
      const resp = await fetch('/api/top_risks_v3');
      if (!resp.ok) {
        log('HTTP error ' + resp.status);
        return [];
      }
      const data = await resp.json();
      if (!data) return [];
      if (Array.isArray(data)) return data;
      if (Array.isArray(data.items)) return data.items;
      return [];
    } catch (e) {
      log('Error fetching top risks: ' + e);
      return [];
    }
  }

  function findTableBody() {
    // Tìm heading chứa text "TOP RISK FINDINGS"
    const candidates = Array.from(
      document.querySelectorAll('h1,h2,h3,h4,h5,h6,div,span')
    );
    const heading = candidates.find(function (el) {
      return (
        el.textContent &&
        el.textContent.toUpperCase().includes('TOP RISK FINDINGS')
      );
    });

    if (!heading) {
      log('Không tìm thấy heading TOP RISK FINDINGS');
      return null;
    }

    // Đi xuống phía dưới để tìm bảng gần nhất
    let container = heading.parentElement;
    for (let depth = 0; depth < 5 && container; depth++) {
      const tbl = container.querySelector('table');
      if (tbl) {
        return tbl.tBodies[0] || tbl.createTBody();
      }
      container = container.nextElementSibling || container.parentElement;
    }

    log('Không tìm thấy bảng TOP RISK FINDINGS');
    return null;
  }

  function render(rows) {
    const tbody = findTableBody();
    if (!tbody) return;

    // Xoá placeholder cũ
    tbody.innerHTML = '';

    if (!rows.length) {
      const tr = document.createElement('tr');
      const td = document.createElement('td');
      td.colSpan = 4;
      td.textContent = 'Chưa có dữ liệu top risk.';
      tr.appendChild(td);
      tbody.appendChild(tr);
      return;
    }

    rows.forEach(function (r) {
      const tr = document.createElement('tr');

      function cell(text) {
        const td = document.createElement('td');
        td.textContent = text || '';
        return td;
      }

      tr.appendChild(cell(r.severity || ''));
      tr.appendChild(cell(r.tool || ''));
      tr.appendChild(cell(r.rule || ''));
      tr.appendChild(cell(r.location || ''));
      tbody.appendChild(tr);
    });
  }

  async function init() {
    // Chỉ chạy trên trang Dashboard (/ hoặc /dashboard)
    const path = window.location.pathname;
    if (!(path === '/' || path === '/dashboard' || path === '/index')) {
      return;
    }

    const rows = await fetchTopRisks();
    render(rows);
  }

  if (document.readyState === 'complete' || document.readyState === 'interactive') {
    setTimeout(init, 0);
  } else {
    document.addEventListener('DOMContentLoaded', init);
  }
})();
JS

echo "[OK] Đã ghi $JS"

########################################
# 2) Thêm route /api/top_risks_v3 vào app.py
########################################
python3 - "$APP" <<'PY'
import sys
from pathlib import Path

app_path = Path(sys.argv[1])
data = app_path.read_text(encoding="utf-8")

if "/api/top_risks_v3" in data:
    print("[INFO] app.py đã có /api/top_risks_v3, bỏ qua.")
    raise SystemExit(0)

block = '''
@app.route("/api/top_risks_v3", methods=["GET"])
def api_top_risks_v3():
    """
    Trả về top 10 findings CRITICAL/HIGH của RUN_* mới nhất
    (dựa trên file findings_unified.json trong thư mục report/).
    """
    import json
    from pathlib import Path
    from flask import jsonify

    root = Path(__file__).resolve().parent.parent  # .../SECURITY_BUNDLE
    out_dir = root / "out"

    run_dirs = sorted(
        [p for p in out_dir.iterdir() if p.is_dir() and p.name.startswith("RUN_")]
    )
    if not run_dirs:
        return jsonify({"items": []})

    last = run_dirs[-1]
    findings_file = last / "report" / "findings_unified.json"
    if not findings_file.is_file():
        return jsonify({"items": []})

    try:
        raw = json.loads(findings_file.read_text(encoding="utf-8"))
    except Exception:
        return jsonify({"items": []})

    if isinstance(raw, dict) and "findings" in raw:
        findings = raw["findings"]
    else:
        findings = raw

    sev_weight = {
        "CRITICAL": 4, "Critical": 4,
        "HIGH": 3, "High": 3,
        "MEDIUM": 2, "Medium": 2,
        "LOW": 1, "Low": 1,
        "INFO": 0, "Information": 0,
    }

    rows = []
    for f in findings:
        sev = str(f.get("severity", "")).strip()
        if not sev:
            continue
        # Chuẩn hoá và lọc CRITICAL / HIGH
        sev_norm = sev.upper()
        w = sev_weight.get(sev, sev_weight.get(sev_norm, -1))
        if w < 3:
            continue

        rows.append({
            "severity": sev_norm,
            "tool": (f.get("tool") or "").strip(),
            "rule": str(f.get("rule") or f.get("id") or ""),
            "location": (f.get("location") or f.get("path") or ""),
        })

    rows.sort(key=lambda r: sev_weight.get(r["severity"], 0), reverse=True)
    rows = rows[:10]

    return jsonify({"items": rows})
'''

needle = '\nif __name__ == "__main__":'
if needle in data:
    new_data = data.replace(needle, '\n' + block + needle)
else:
    new_data = data + '\n' + block + '\n'

app_path.write_text(new_data, encoding="utf-8")
print("[OK] Đã chèn route /api/top_risks_v3 vào app.py")
PY

echo "[DONE] patch_dashboard_top_risks_v3.sh hoàn thành."
