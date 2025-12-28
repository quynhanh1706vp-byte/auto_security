#!/usr/bin/env bash
set -euo pipefail

APP="app.py"
echo "[i] APP = $APP"

if [ ! -f "$APP" ]; then
  echo "[ERR] Không tìm thấy $APP"
  exit 1
fi

python3 - "$APP" <<'PY'
import sys, pathlib

path = pathlib.Path(sys.argv[1])
code = path.read_text(encoding="utf-8")

marker = "# === DASHBOARD_DATA_API_V1 ==="
if marker in code:
    print("[INFO] Đã có block DASHBOARD_DATA_API_V1, bỏ qua.")
    sys.exit(0)

append = """
# === DASHBOARD_DATA_API_V1 ===
from flask import jsonify, send_from_directory, abort

def _sb_list_runs():
    from pathlib import Path
    root = Path("/home/test/Data/SECURITY_BUNDLE")
    out = root / "out"
    runs = []
    if not out.is_dir():
        return runs
    for p in out.iterdir():
        if not p.is_dir():
            continue
        name = p.name
        if not name.startswith("RUN_"):
            continue
        # RUN_YYYYmmdd_HHMMSS = 19 ký tự
        if len(name) != 19:
            continue
        date_part = name[4:12]
        time_part = name[13:]
        if not (date_part.isdigit() and time_part.isdigit()):
            continue
        runs.append(p)
    runs.sort(key=lambda x: x.name)
    return runs

def _sb_pick_summary_file(run_dir):
    from pathlib import Path
    candidates = [
        run_dir / "summary_unified.json",
        run_dir / "summary.json",
        run_dir / "report" / "summary_unified.json",
        run_dir / "report" / "summary.json",
    ]
    for c in candidates:
        if c.is_file():
            return c
    return None

def _sb_pick_findings_file(run_dir):
    from pathlib import Path
    candidates = [
        run_dir / "findings_unified.json",
        run_dir / "report" / "findings_unified.json",
        run_dir / "report" / "findings.json",
    ]
    for c in candidates:
        if c.is_file():
            return c
    return None

def _sb_extract_counts_from_summary_dict(data):
    total = 0
    crit = high = medium = low = 0

    # Có thể là { "summary_all": {...} }
    if isinstance(data, dict) and "summary_all" in data and isinstance(data["summary_all"], dict):
        data = data["summary_all"]

    if not isinstance(data, dict):
        return total, crit, high, medium, low

    total = (
        data.get("total")
        or data.get("total_findings")
        or data.get("findings_total")
        or 0
    )

    sev = (
        data.get("by_severity")
        or data.get("severity_buckets")
        or data.get("severity")
        or {}
    ) or {}

    # chuẩn hoá key upper
    sev_up = {str(k).upper(): int(v or 0) for k, v in sev.items()}

    crit = sev_up.get("CRITICAL", 0)
    high = sev_up.get("HIGH", 0)
    medium = sev_up.get("MEDIUM", 0)
    low = (
        sev_up.get("LOW", 0)
        + sev_up.get("INFO", 0)
        + sev_up.get("UNKNOWN", 0)
    )

    return int(total or 0), crit, high, medium, low

def _sb_extract_counts_from_findings_list(items):
    from collections import Counter
    total = len(items)
    c = Counter()
    for it in items:
        if not isinstance(it, dict):
            continue
        sev = (it.get("severity") or it.get("sev") or "").upper()
        c[sev] += 1
    crit = c.get("CRITICAL", 0)
    high = c.get("HIGH", 0)
    medium = c.get("MEDIUM", 0)
    low = c.get("LOW", 0) + c.get("INFO", 0) + c.get("UNKNOWN", 0)
    return total, crit, high, medium, low

def _sb_pick_report_html(run_dir):
    from pathlib import Path
    rep = run_dir / "report"
    if not rep.is_dir():
        return None
    candidates = [
        "pm_style_report.html",
        "pm_style_report_print.html",
        "simple_report.html",
        "checkmarx_like.html",
        "security_resilient.html",
    ]
    for name in candidates:
        p = rep / name
        if p.is_file():
            return name
    return None

@app.route("/api/dashboard_data", methods=["GET"])
def api_dashboard_data():
    \"""
    Trả về JSON cho Dashboard:
    - tổng findings, buckets CRIT/HIGH/MED/LOW
    - top_risks (max 10)
    - trend_runs (một số RUN gần nhất)
    - tool_config_rows (từ tool_config.json)
    \"""
    import json, datetime
    from pathlib import Path

    root = Path("/home/test/Data/SECURITY_BUNDLE")
    out = root / "out"

    total = 0
    crit = high = medium = low = 0
    last_run_id = "RUN_YYYYmmdd_HHMMSS"
    last_updated = "—"
    top_risks = []
    trend_runs = []
    tool_rows = []

    runs = _sb_list_runs()
    if runs:
        last = runs[-1]
        last_run_id = last.name
        dt = datetime.datetime.fromtimestamp(last.stat().st_mtime)
        last_updated = dt.strftime("%Y-%m-%d %H:%M:%S")

        # 1) summary / findings cho RUN mới nhất
        summary_file = _sb_pick_summary_file(last)
        findings_file = _sb_pick_findings_file(last)

        if summary_file is not None:
            try:
                with summary_file.open("r", encoding="utf-8") as f:
                    data = json.load(f)
                total, crit, high, medium, low = _sb_extract_counts_from_summary_dict(data)
                print(f"[INFO][API] Dashboard dùng summary: {summary_file}")
            except Exception as e:
                print(f"[WARN][API] Lỗi đọc summary {summary_file}: {e}")

        elif findings_file is not None:
            try:
                with findings_file.open("r", encoding="utf-8") as f:
                    items = json.load(f)
                total, crit, high, medium, low = _sb_extract_counts_from_findings_list(items)
                print(f"[INFO][API] Dashboard đếm từ findings: {findings_file}")
            except Exception as e:
                print(f"[WARN][API] Lỗi đọc findings {findings_file}: {e}")

        # 2) TOP RISK (Critical / High – max 10) từ findings_file
        if findings_file is not None:
            try:
                with findings_file.open("r", encoding="utf-8") as f:
                    items = json.load(f)
                # lọc CRIT/HIGH
                buf = []
                for it in items:
                    if not isinstance(it, dict):
                        continue
                    sev = (it.get("severity") or it.get("sev") or "").upper()
                    if sev not in ("CRITICAL", "HIGH"):
                        continue
                    tool = it.get("tool") or it.get("scanner") or it.get("source") or "—"
                    rule = it.get("rule") or it.get("rule_id") or it.get("check_id") or "—"
                    loc = (
                        it.get("location")
                        or it.get("path")
                        or it.get("file")
                        or "—"
                    )
                    buf.append({
                        "severity": sev,
                        "tool": tool,
                        "rule": rule,
                        "location": loc,
                    })
                # ưu tiên CRITICAL trước, rồi HIGH, giới hạn 10
                buf.sort(key=lambda x: (0 if x["severity"] == "CRITICAL" else 1))
                top_risks = buf[:10]
            except Exception as e:
                print(f"[WARN][API] Lỗi build top_risks từ {findings_file}: {e}")

        # 3) TREND – LAST RUNS (tối đa 8 RUN gần nhất)
        import json as _json2
        for r in reversed(runs[-8:]):
            s_file = _sb_pick_summary_file(r)
            f_file = _sb_pick_findings_file(r)
            t_total = 0
            t_crit = t_high = 0
            if s_file is not None:
                try:
                    with s_file.open("r", encoding="utf-8") as f:
                        data = _json2.load(f)
                    t_total, c, h, m, l = _sb_extract_counts_from_summary_dict(data)
                    t_crit = c
                    t_high = h
                except Exception as e:
                    print(f"[WARN][API] Trend: lỗi đọc {s_file}: {e}")
            elif f_file is not None:
                try:
                    with f_file.open("r", encoding="utf-8") as f:
                        items = _json2.load(f)
                    t_total, c, h, m, l = _sb_extract_counts_from_findings_list(items)
                    t_crit = c
                    t_high = h
                except Exception as e:
                    print(f"[WARN][API] Trend: lỗi đọc {f_file}: {e}")
            trend_runs.append({
                "run_id": r.name,
                "total": int(t_total or 0),
                "crit_high": int((t_crit or 0) + (t_high or 0)),
            })

    # 4) BY TOOL / CONFIG từ ui/tool_config.json
    try:
        cfg_path = pathlib.Path("/home/test/Data/SECURITY_BUNDLE/ui/tool_config.json")
        if cfg_path.is_file():
            import json as _json3
            with cfg_path.open("r", encoding="utf-8") as f:
                cfg = _json3.load(f)
            rows = []
            if isinstance(cfg, list):
                tools_list = cfg
            elif isinstance(cfg, dict) and "tools" in cfg and isinstance(cfg["tools"], list):
                tools_list = cfg["tools"]
            else:
                tools_list = []
            for t in tools_list:
                if not isinstance(t, dict):
                    continue
                name = t.get("name") or t.get("tool") or "—"
                enabled = bool(t.get("enabled", True))
                level = t.get("level") or t.get("profile") or "—"
                modes = t.get("modes") or t.get("mode") or {}
                if isinstance(modes, dict):
                    on_modes = [k.upper() for k, v in modes.items() if v]
                    modes_str = ", ".join(on_modes) if on_modes else "—"
                else:
                    modes_str = str(modes)
                rows.append({
                    "name": name,
                    "enabled": enabled,
                    "level": level,
                    "modes": modes_str,
                })
            tool_rows = rows
    except Exception as e:
        print(f"[WARN][API] Lỗi đọc tool_config.json: {e}")

    resp = {
        "total_findings": int(total or 0),
        "crit": int(crit or 0),
        "high": int(high or 0),
        "medium": int(medium or 0),
        "low": int(low or 0),
        "last_run_id": last_run_id,
        "last_updated": last_updated,
        "top_risks": top_risks,
        "trend_runs": trend_runs,
        "tool_config_rows": tool_rows,
    }
    print("[INFO][API] DASH:", resp["last_run_id"], resp["total_findings"],
          resp["crit"], resp["high"], resp["medium"], resp["low"])
    return jsonify(resp)

@app.route("/api/runs", methods=["GET"])
def api_runs():
    \"""
    Trả list các RUN_* + tổng findings + Crit/High + có report HTML hay không.
    Dùng cho tab Run & Report.
    \"""
    import json, datetime
    runs = _sb_list_runs()
    out = []
    for r in reversed(runs):  # mới nhất trước
        summary_file = _sb_pick_summary_file(r)
        findings_file = _sb_pick_findings_file(r)
        total = 0
        crit = high = medium = low = 0
        if summary_file is not None:
            try:
                with summary_file.open("r", encoding="utf-8") as f:
                    data = json.load(f)
                total, crit, high, medium, low = _sb_extract_counts_from_summary_dict(data)
            except Exception as e:
                print(f"[WARN][API] Runs: lỗi đọc {summary_file}: {e}")
        elif findings_file is not None:
            try:
                with findings_file.open("r", encoding="utf-8") as f:
                    items = json.load(f)
                total, crit, high, medium, low = _sb_extract_counts_from_findings_list(items)
            except Exception as e:
                print(f"[WARN][API] Runs: lỗi đọc {findings_file}: {e}")

        rep_name = _sb_pick_report_html(r)
        has_report = rep_name is not None
        dt = datetime.datetime.fromtimestamp(r.stat().st_mtime)
        out.append({
            "run_id": r.name,
            "mtime": dt.strftime("%Y-%m-%d %H:%M:%S"),
            "total": int(total or 0),
            "crit": int(crit or 0),
            "high": int(high or 0),
            "medium": int(medium or 0),
            "low": int(low or 0),
            "crit_high": int((crit or 0) + (high or 0)),
            "has_report": has_report,
            "report_html_url": f"/report/{r.name}/html" if has_report else None,
        })
    return jsonify({"runs": out})

@app.route("/report/<run_id>/html", methods=["GET"])
def view_run_report_html(run_id):
    \"""
    Mở report HTML tốt nhất cho RUN_*/report/ (pm_style_report.html, simple_report.html,...)
    \"""
    from pathlib import Path
    root = Path("/home/test/Data/SECURITY_BUNDLE")
    run_dir = root / "out" / run_id
    if not run_dir.is_dir():
        abort(404)
    rep_name = _sb_pick_report_html(run_dir)
    if rep_name is None:
        abort(404)
    report_dir = run_dir / "report"
    return send_from_directory(str(report_dir), rep_name)

@app.route("/runs", methods=["GET"])
def runs_page():
    \"""
    Trang Run & Report – frontend sẽ fetch /api/runs để lấp data.
    \"""
    return render_template("runs.html")
"""

code = code.rstrip() + "\n\n" + append + "\n"
path.write_text(code, encoding="utf-8")
print("[OK] Đã append DASHBOARD_DATA_API_V1 vào app.py")
PY
