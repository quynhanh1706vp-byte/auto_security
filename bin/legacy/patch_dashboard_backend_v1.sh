#!/usr/bin/env bash
set -euo pipefail

APP=$(find "/home/test/Data/SECURITY_BUNDLE" -maxdepth 2 -type f -name 'app.py' | head -n 1 || true)

if [ -z "$APP" ]; then
  echo "[ERR] Không tìm thấy app.py"
  exit 1
fi

echo "[i] APP = $APP"

python3 - "$APP" <<'PY'
import sys, pathlib, textwrap

path = pathlib.Path(sys.argv[1])
data = path.read_text(encoding="utf-8")

if "SB_DASHBOARD_BACKEND_V1" in data:
    print("[INFO] Đã có block SB_DASHBOARD_BACKEND_V1 – bỏ qua.")
    sys.exit(0)

append = textwrap.dedent("""
# ==== SB_DASHBOARD_BACKEND_V1 ====
from pathlib import Path
import json

# helper: tìm RUN_* mới nhất
def _sb_find_latest_run_root():
    base = Path("/home/test/Data/SECURITY_BUNDLE/out")
    if not base.is_dir():
        return None
    runs = sorted([p for p in base.glob("RUN_*") if p.is_dir()])
    if not runs:
        return None
    return runs[-1]

# helper: đọc summary_unified.json của RUN mới nhất
def _sb_load_summary_latest():
    root = _sb_find_latest_run_root()
    if root is None:
        return None, None
    summary_path = root / "report" / "summary_unified.json"
    if not summary_path.is_file():
        return str(root), None
    try:
        data = json.loads(summary_path.read_text(encoding="utf-8"))
    except Exception as e:
        print("[SB][INDEX] Lỗi đọc", summary_path, e)
        return str(root), None
    return str(root), data

def _sb_build_dashboard_data():
    run_root, summary = _sb_load_summary_latest()
    total = 0
    crit = high = med = low = 0
    last_updated = ""
    by_tool_counts = {}
    last_runs = []
    top_risks = []

    if summary:
        # tổng findings – thử nhiều dạng key khác nhau cho chắc
        for key in ["total_findings", "findings_total", "total_all"]:
            v = summary.get(key)
            if isinstance(v, int):
                total = v
                break
        else:
            tot = summary.get("totals") or summary.get("summary") or {}
            if isinstance(tot, dict):
                for key in ["all", "total", "total_findings"]:
                    v = tot.get(key)
                    if isinstance(v, int):
                        total = v
                        break

        sev = summary.get("severity") or summary.get("severity_counts") or summary.get("severityBuckets") or {}
        if isinstance(sev, dict):
            crit = sev.get("CRITICAL", sev.get("critical", 0)) or 0
            high = sev.get("HIGH", sev.get("high", 0)) or 0
            med  = sev.get("MEDIUM", sev.get("medium", 0)) or 0
            low  = sev.get("LOW", sev.get("low", 0)) or 0

        last_updated = (summary.get("last_updated")
                        or summary.get("generated_at")
                        or "")

        by_tool_counts = summary.get("by_tool") or summary.get("tools") or {}
        last_runs = summary.get("runs") or summary.get("trend_last_runs") or []
        top_risks = summary.get("top_risks") or summary.get("top_findings") or []

    crit_high_str = f"{crit}/{high}" if (crit or high) else "0/0"

    # chuẩn hoá list RUN
    nruns = []
    if isinstance(last_runs, list):
        for r in last_runs:
            if not isinstance(r, dict):
                continue
            nruns.append({
                "name": r.get("name") or r.get("run") or r.get("id", ""),
                "time": r.get("time") or r.get("timestamp", ""),
                "total": r.get("total") or r.get("findings") or 0,
                "crit_high": r.get("crit_high") or r.get("critHigh") or r.get("crit_high_str") or "",
            })

    # chuẩn hoá top risk
    nrisks = []
    if isinstance(top_risks, list):
        for f in top_risks:
            if not isinstance(f, dict):
                continue
            nrisks.append({
                "severity": f.get("severity", ""),
                "tool": f.get("tool") or f.get("scanner") or "",
                "rule": f.get("rule") or f.get("id") or "",
                "location": f.get("location") or f.get("file") or "",
            })

    # đọc tool_config.json rồi join với thống kê theo tool
    tools_cfg_path_candidates = [
        Path(__file__).resolve().parent / "tool_config.json",
        Path(__file__).resolve().parent.parent / "ui" / "tool_config.json",
        Path("/home/test/Data/SECURITY_BUNDLE/ui/tool_config.json"),
    ]
    tools_cfg = []
    for c in tools_cfg_path_candidates:
        if c.is_file():
            try:
                tools_cfg = json.loads(c.read_text(encoding="utf-8"))
            except Exception as e:
                print("[SB][INDEX] Lỗi đọc", c, e)
            break

    tools_rows = []
    if isinstance(tools_cfg, list):
        for t in tools_cfg:
            if not isinstance(t, dict):
                continue
            name = t.get("tool") or t.get("name") or ""
            count = 0
            if isinstance(by_tool_counts, dict) and name:
                v = by_tool_counts.get(name) or by_tool_counts.get(name.lower())
                if isinstance(v, dict):
                    for kk in ["count", "total", "findings"]:
                        vv = v.get(kk)
                        if isinstance(vv, int):
                            count = vv
                            break
                elif isinstance(v, int):
                    count = v

            enabled_flag = str(t.get("enabled", "")).upper()
            enabled = "ON" if enabled_flag in ("1", "TRUE", "ON", "YES") else "OFF"

            modes = []
            if str(t.get("mode_offline", "1")).upper() not in ("0", "FALSE", "OFF", "NO"):
                modes.append("Offline")
            if str(t.get("mode_online", "")).upper() in ("1", "TRUE", "ON", "YES"):
                modes.append("Online")
            if str(t.get("mode_cicd", "")).upper() in ("1", "TRUE", "ON", "YES"):
                modes.append("CI/CD")

            tools_rows.append({
                "name": name,
                "enabled": enabled,
                "level": t.get("level") or t.get("profile") or "",
                "modes": ", ".join(modes),
                "count": count,
            })

    last_run_name = Path(run_root).name if run_root else "N/A"

    return {
        "last_run_name": last_run_name,
        "src_folder": "/home/test/Data/Khach",
        "mode": "Offline",
        "profile": "Aggressive",
        "total_findings": total,
        "crit_high": crit_high_str,
        "last_updated": last_updated,
        "severity_counts": {"critical": crit, "high": high, "medium": med, "low": low},
        "tools": tools_rows,
        "runs": nruns,
        "top_risks": nrisks,
    }

@app.route("/")
def index():
    data = _sb_build_dashboard_data()
    print(f"[INFO][INDEX] RUN={data.get('last_run_name')}, total={data.get('total_findings')}, C={data['severity_counts']['critical']}, H={data['severity_counts']['high']}, M={data['severity_counts']['medium']}, L={data['severity_counts']['low']}")
    return render_template("index.html", **data)

@app.route("/api/dashboard_data")
def api_dashboard_data():
    return jsonify(_sb_build_dashboard_data())

@app.route("/api/tools_by_config")
def api_tools_by_config():
    data = _sb_build_dashboard_data()
    return jsonify(data.get("tools", []))

@app.route("/api/runs")
def api_runs():
    data = _sb_build_dashboard_data()
    return jsonify(data.get("runs", []))

@app.route("/api/top_risks_any")
def api_top_risks_any():
    data = _sb_build_dashboard_data()
    return jsonify(data.get("top_risks", []))
# ==== END SB_DASHBOARD_BACKEND_V1 ====
""")

data = data + append
path.write_text(data, encoding="utf-8")
print("[OK] Đã append SB_DASHBOARD_BACKEND_V1 vào", path)
PY

echo "[DONE] patch_dashboard_backend_v1.sh hoàn thành."
