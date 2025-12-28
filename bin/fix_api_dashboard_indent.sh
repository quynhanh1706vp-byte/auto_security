#!/usr/bin/env bash
set -euo pipefail

APP="app.py"
echo "[i] APP = $APP"

if [ ! -f "$APP" ]; then
  echo "[ERR] Không tìm thấy $APP"
  exit 1
fi

python3 - "$APP" <<'PY'
import sys, pathlib, textwrap

path = pathlib.Path(sys.argv[1])
code = path.read_text(encoding="utf-8")

# Tìm route /api/dashboard_data
idx = code.find('@app.route("/api/dashboard_data"')
if idx == -1:
    idx = code.find("@app.route('/api/dashboard_data'")
if idx == -1:
    print("[ERR] Không tìm thấy @app.route('/api/dashboard_data') trong app.py")
    sys.exit(1)

def_idx = code.find("def api_dashboard_data", idx)
if def_idx == -1:
    print("[ERR] Không tìm thấy def api_dashboard_data sau route.")
    sys.exit(1)

# Kết thúc block: tới @app.route tiếp theo
end = code.find("\n@app.route", def_idx + 1)
if end == -1:
    end = len(code)

before = code[:idx]
after = code[end:]

new_block = textwrap.dedent("""
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
        cfg_path = Path("/home/test/Data/SECURITY_BUNDLE/ui/tool_config.json")
        if cfg_path.is_file():
            import json as _json3
            with cfg_path.open("r", encoding="utf-8") as f:
                cfg = _json3.load(f)

            rows = []
            tools_list = []
            raw = cfg

            if isinstance(raw, list):
                tools_list = raw
            elif isinstance(raw, dict):
                if isinstance(raw.get("tools"), list):
                    tools_list = raw["tools"]
                else:
                    for k, v in raw.items():
                        if isinstance(v, dict):
                            item = dict(v)
                            item.setdefault("name", k)
                            tools_list.append(item)

            for t in tools_list:
                if not isinstance(t, dict):
                    continue
                name = t.get("name") or t.get("tool") or "—"
                enabled = bool(t.get("enabled", True))
                level = t.get("level") or t.get("profile") or "—"
                modes = t.get("modes") or t.get("mode") or {}
                modes_str = "—"
                if isinstance(modes, dict):
                    on_modes = [str(k).upper() for k, v in modes.items() if v]
                    modes_str = ", ".join(on_modes) if on_modes else "—"
                elif isinstance(modes, (list, tuple)):
                    modes_str = ", ".join(str(x).upper() for x in modes) or "—"
                elif modes:
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
""").lstrip("\n")

code_new = before + new_block + "\n" + after
path.write_text(code_new, encoding="utf-8")
print("[OK] Đã ghi lại api_dashboard_data với indent chuẩn.")
PY
