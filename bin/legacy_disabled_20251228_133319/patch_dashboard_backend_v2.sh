#!/usr/bin/env bash
set -euo pipefail

APP="/home/test/Data/SECURITY_BUNDLE/ui/app.py"

echo "[i] APP = $APP"

if [ ! -f "$APP" ]; then
  echo "[ERR] Không tìm thấy app.py"
  exit 1
fi

python3 - "$APP" <<'PY'
import sys, textwrap, os

path = sys.argv[1]
with open(path, "r", encoding="utf-8") as f:
    data = f.read()

marker = '@app.route("/")'
idx = data.find(marker)
if idx == -1:
    print("[ERR] Không tìm thấy @app.route(\"/\") trong app.py")
    sys.exit(1)

# Tìm đến route tiếp theo để cắt block cũ
next_idx = data.find('@app.route(', idx + 1)
if next_idx == -1:
    next_idx = len(data)

before = data[:idx]

new_block = r'''
@app.route("/")
def index():
    """
    Dashboard v2:
    - Quét toàn bộ out/RUN_* để tính:
      + Tổng findings theo lần quét mới nhất
      + Phân bố CRITICAL/HIGH/MEDIUM/LOW
      + Bảng TREND - LAST RUNS
      + TOP RISK (tối đa 10 findings severity CRIT/HIGH của run mới nhất)
    """
    import json, os
    from pathlib import Path
    from datetime import datetime

    ROOT = Path("/home/test/Data/SECURITY_BUNDLE")
    OUT_DIR = ROOT / "out"

    runs = []
    last_run_detail = None
    top_risks = []

    if OUT_DIR.is_dir():
        run_dirs = sorted([p for p in OUT_DIR.iterdir()
                           if p.is_dir() and p.name.startswith("RUN_")])
    else:
        run_dirs = []

    def load_findings(run_path: Path):
        # Thử các vị trí thường gặp
        candidates = [
            run_path / "report" / "findings_unified.json",
            run_path / "findings_unified.json",
        ]
        for c in candidates:
            if c.is_file():
                try:
                    with open(c, "r", encoding="utf-8") as f:
                        data = json.load(f)
                    if isinstance(data, list):
                        return data
                except Exception:
                    pass
        return []

    for rp in run_dirs:
        findings = load_findings(rp)
        total = len(findings)
        sev_count = {"CRITICAL": 0, "HIGH": 0, "MEDIUM": 0, "LOW": 0}

        for it in findings:
            sev = (str(it.get("severity") or it.get("Severity") or "")).upper()
            if sev.startswith("CRIT"):
                sev = "CRITICAL"
            elif sev.startswith("HIGH"):
                sev = "HIGH"
            elif sev.startswith("MED"):
                sev = "MEDIUM"
            elif sev.startswith("LOW"):
                sev = "LOW"
            else:
                continue
            if sev in sev_count:
                sev_count[sev] += 1

        runs.append({
            "run_id": rp.name,
            "total": total,
            "crit": sev_count["CRITICAL"],
            "high": sev_count["HIGH"],
            "medium": sev_count["MEDIUM"],
            "low": sev_count["LOW"],
        })

    has_data = len(runs) > 0

    if has_data:
        last = runs[-1]
        last_run_id = last["run_id"]
        # Thử parse thời gian từ tên RUN_YYYYmmdd_HHMMSS
        last_ts = None
        try:
            parts = last_run_id.split("_")
            if len(parts) >= 3:
                dt_str = parts[1] + parts[2]
                last_ts = datetime.strptime(dt_str, "%Y%m%d%H%M%S")
        except Exception:
            pass

        findings_last = load_findings(OUT_DIR / last_run_id)

        # TOP RISK: lấy CRIT/HIGH trước, tối đa 10 dòng
        tmp = []
        for it in findings_last:
            sev = (str(it.get("severity") or it.get("Severity") or "")).upper()
            if sev.startswith("CRIT"):
                sev = "CRITICAL"
            elif sev.startswith("HIGH"):
                sev = "HIGH"
            else:
                continue

            path = it.get("file") or it.get("path") or ""
            line = it.get("line") or it.get("start_line") or ""
            loc = f"{path}:{line}" if path or line else ""

            tmp.append({
                "severity": sev,
                "tool": it.get("tool") or it.get("Tool") or "N/A",
                "rule_id": it.get("rule_id") or it.get("RuleID") or it.get("check_id") or "",
                "location": loc,
                "message": it.get("message") or it.get("shortDescription") or "",
            })

        # Ưu tiên CRITICAL rồi HIGH
        def sev_weight(s):
            if s == "CRITICAL":
                return 2
            if s == "HIGH":
                return 1
            return 0

        tmp.sort(key=lambda x: (-sev_weight(x["severity"]), x["tool"], x["rule_id"]))
        top_risks = tmp[:10]

        last_run_detail = {
            "run_id": last_run_id,
            "total": last["total"],
            "crit": last["crit"],
            "high": last["high"],
            "medium": last["medium"],
            "low": last["low"],
            "last_updated_str": last_ts.strftime("%Y-%m-%d %H:%M:%S") if last_ts else "",
        }

    # Đọc tool_config cho bảng BY TOOL / CONFIG
    tool_cfg = {}
    try:
        cfg_path = ROOT / "ui" / "tool_config.json"
        if cfg_path.is_file():
            import json
            with open(cfg_path, "r", encoding="utf-8") as f:
                tool_cfg = json.load(f)
    except Exception:
        tool_cfg = {}

    dashboard = {
        "has_data": has_data,
        "runs": runs,
        "last_run": last_run_detail,
        "top_risks": top_risks,
    }

    return render_template("index.html", dashboard=dashboard, tool_config=tool_cfg)
'''

after = data[next_idx:]

# Nếu đã từng patch rồi thì không patch nữa
if "Dashboard v2:" in data:
    print("[INFO] app.py đã có Dashboard v2, bỏ qua.")
    sys.exit(0)

new_data = before + textwrap.dedent(new_block).lstrip("\n") + after

with open(path, "w", encoding="utf-8") as f:
    f.write(new_data)

print("[OK] Đã patch route '/' trong app.py với Dashboard v2.")
PY
