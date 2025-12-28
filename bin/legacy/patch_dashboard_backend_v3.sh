#!/usr/bin/env bash
set -euo pipefail

APP="/home/test/Data/SECURITY_BUNDLE/ui/app.py"
echo "[i] APP = $APP"

if [ ! -f "$APP" ]; then
  echo "[ERR] Không tìm thấy app.py"
  exit 1
fi

python3 - "$APP" <<'PY'
import sys, re, textwrap

path = sys.argv[1]
with open(path, "r", encoding="utf-8") as f:
    data = f.read()

marker = '@app.route("/")'
start = data.find(marker)
if start == -1:
    print("[ERR] Không tìm thấy @app.route(\"/\") trong app.py")
    sys.exit(1)

end = data.find('@app.route(', start + len(marker))
if end == -1:
    end = len(data)

before = data[:start]
after = data[end:]

new_block = r'''
@app.route("/")
def index():
    """
    Dashboard v3:
    - Quét toàn bộ out/RUN_* để tính:
      + Tổng findings của RUN chuẩn mới nhất (RUN_YYYYmmdd_HHMMSS)
      + Phân bố CRITICAL/HIGH/MEDIUM/LOW
      + Bảng TREND - LAST RUNS
      + TOP RISK (max 10 findings CRIT/HIGH của RUN chuẩn mới nhất)
    """
    import json, os
    from pathlib import Path
    from datetime import datetime

    ROOT = Path("/home/test/Data/SECURITY_BUNDLE")
    OUT_DIR = ROOT / "out"

    runs = []
    run_path_map = {}
    last_run_detail = None
    top_risks = []

    if OUT_DIR.is_dir():
        run_dirs = sorted(
            [p for p in OUT_DIR.iterdir() if p.is_dir() and p.name.startswith("RUN_")],
            key=lambda p: p.name,
        )
    else:
        run_dirs = []

    def load_findings(run_path: Path):
        # Các tên file unify thường gặp
        candidates = [
            run_path / "report" / "findings_unified.json",
            run_path / "report" / "findings_unified_all_tools.json",
            run_path / "report" / "findings.json",
            run_path / "findings_unified.json",
            run_path / "findings_unified_all_tools.json",
            run_path / "findings.json",
        ]
        for c in candidates:
            if c.is_file():
                try:
                    with open(c, "r", encoding="utf-8") as f:
                        raw = json.load(f)
                    if isinstance(raw, list):
                        return raw
                    if isinstance(raw, dict):
                        for key in ("findings", "items", "results"):
                            v = raw.get(key)
                            if isinstance(v, list):
                                return v
                except Exception:
                    pass
        return []

    def norm_severity(item):
        sev = (
            str(
                item.get("severity_norm")
                or item.get("severity")
                or item.get("Severity")
                or ""
            )
            .strip()
            .upper()
        )
        if sev.startswith("CRIT"):
            return "CRITICAL"
        if sev.startswith("HIGH"):
            return "HIGH"
        if sev.startswith("MED"):
            return "MEDIUM"
        if sev.startswith("LOW"):
            return "LOW"
        return ""

    # Build list runs (cả RUN_gitleaks_..., RUN_GITLEAKS_EXT_..., RUN_YYYYmmdd_HHMMSS...)
    for rp in run_dirs:
        run_id = rp.name
        run_path_map[run_id] = rp

        findings = load_findings(rp)
        total = len(findings)
        sev_count = {"CRITICAL": 0, "HIGH": 0, "MEDIUM": 0, "LOW": 0}

        for it in findings:
            sev = norm_severity(it)
            if sev in sev_count:
                sev_count[sev] += 1

        runs.append(
            {
                "run_id": run_id,
                "total": total,
                "crit": sev_count["CRITICAL"],
                "high": sev_count["HIGH"],
                "medium": sev_count["MEDIUM"],
                "low": sev_count["LOW"],
            }
        )

    has_data = len(runs) > 0

    # Chỉ coi RUN_YYYYmmdd_HHMMSS là "RUN chuẩn"
    real_runs = [
        r for r in runs if re.match(r"^RUN_[0-9]{8}_[0-9]{6}$", r["run_id"])
    ]

    # Ưu tiên RUN chuẩn có total > 0
    real_runs_with_data = [r for r in real_runs if (r.get("total") or 0) > 0]
    chosen_list = real_runs_with_data or real_runs or runs

    if has_data and chosen_list:
        chosen_list = sorted(chosen_list, key=lambda r: r["run_id"])
        last = chosen_list[-1]
        last_run_id = last["run_id"]

        # Parse timestamp từ RUN_YYYYmmdd_HHMMSS
        last_ts = None
        try:
            m = re.match(r"^RUN_([0-9]{8})_([0-9]{6})", last_run_id)
            if m:
                dt_str = m.group(1) + m.group(2)
                last_ts = datetime.strptime(dt_str, "%Y%m%d%H%M%S")
        except Exception:
            pass

        findings_last = load_findings(run_path_map[last_run_id])

        # TOP RISK: CRIT/HIGH của RUN chuẩn mới nhất
        tmp = []
        for it in findings_last:
            sev = norm_severity(it)
            if sev not in ("CRITICAL", "HIGH"):
                continue

            path = it.get("file") or it.get("path") or it.get("location") or ""
            line = (
                it.get("line")
                or it.get("start_line")
                or it.get("startLine")
                or ""
            )
            loc = f"{path}:{line}" if path or line else ""

            tmp.append(
                {
                    "severity": sev,
                    "tool": it.get("tool") or it.get("Tool") or "N/A",
                    "rule_id": it.get("rule_id")
                    or it.get("RuleID")
                    or it.get("check_id")
                    or it.get("id")
                    or "",
                    "location": loc,
                    "message": it.get("message")
                    or it.get("shortDescription")
                    or it.get("title")
                    or "",
                }
            )

        def sev_weight(s):
            if s == "CRITICAL":
                return 2
            if s == "HIGH":
                return 1
            return 0

        tmp.sort(
            key=lambda x: (-sev_weight(x["severity"]), x["tool"], x["rule_id"])
        )
        top_risks = tmp[:10]

        last_run_detail = {
            "run_id": last_run_id,
            "total": last["total"],
            "crit": last["crit"],
            "high": last["high"],
            "medium": last["medium"],
            "low": last["low"],
            "last_updated_str": last_ts.strftime("%Y-%m-%d %H:%M:%S")
            if last_ts
            else "",
        }

    # Đọc tool_config cho bảng BY TOOL / CONFIG
    tool_cfg = {}
    try:
        cfg_path = ROOT / "ui" / "tool_config.json"
        if cfg_path.is_file():
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

data_new = before + textwrap.dedent(new_block).lstrip("\n") + after

with open(path, "w", encoding="utf-8") as f:
    f.write(data_new)

print("[OK] Đã thay thế route '/' bằng Dashboard v3.")
PY
