#!/usr/bin/env bash
set -euo pipefail

cd /home/test/Data/SECURITY_BUNDLE/ui

APP="app.py"
cp "$APP" "$APP.bak_routes_$(date +%Y%m%d_%H%M%S)" || true

python3 - "$APP" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
data = path.read_text(encoding="utf-8")

# 1) Đảm bảo import Path + json
if "from pathlib import Path" not in data:
    if "import os\n" in data:
        data = data.replace("import os\n", "import os\nfrom pathlib import Path\n", 1)
    else:
        data = "from pathlib import Path\n" + data

if "import json" not in data:
    if "import os\n" in data:
        data = data.replace("import os\n", "import os\nimport json\n", 1)
    else:
        data = "import json\n" + data


def replace_route_block(data_str: str, route_path: str, new_def: str) -> str:
    """Thay toàn bộ block @app.route("...") + def ... bằng new_def."""
    marker = f'@app.route("{route_path}")'
    idx = data_str.find(marker)
    if idx == -1:
        # Không có route cũ → append ở trước if __name__...
        main_idx = data_str.find('if __name__ == "__main__":')
        if main_idx == -1:
            return data_str + "\n\n" + new_def + "\n"
        return data_str[:main_idx] + "\n\n" + new_def + "\n\n" + data_str[main_idx:]
    # tìm điểm kết thúc block (route/def này) = trước route tiếp theo hoặc trước if __main__
    next_route = data_str.find("@app.route(", idx + len(marker))
    main_idx = data_str.find('if __name__ == "__main__":', idx + len(marker))
    candidates = [len(data_str)]
    if next_route != -1:
        candidates.append(next_route)
    if main_idx != -1:
        candidates.append(main_idx)
    end = min(candidates)
    return data_str[:idx] + new_def + "\n\n" + data_str[end:]


# ---------- Định nghĩa mới cho 3 route ----------

runs_def = '''@app.route("/runs")
def runs():
    """Runs & Reports history from out/RUN_* (newest first)."""
    base = Path(__file__).resolve().parents[1]
    out_dir = base / "out"
    runs = []
    if out_dir.is_dir():
        for run_dir in sorted(out_dir.glob("RUN_*"), reverse=True):
            report_dir = run_dir / "report"
            summary_path = report_dir / "summary_unified.json"
            if not summary_path.is_file():
                continue
            try:
                raw = json.loads(summary_path.read_text(encoding="utf-8"))
            except Exception:
                continue
            sev = raw.get("severity_counts") or raw.get("SEVERITY_COUNTS") or {}
            total = raw.get("total_findings") or raw.get("TOTAL_FINDINGS") or 0
            runs.append({
                "run_id": run_dir.name,
                "run_path": str(run_dir),
                "total": int(total),
                "critical": int(sev.get("CRITICAL", 0)),
                "high": int(sev.get("HIGH", 0)),
                "medium": int(sev.get("MEDIUM", 0)),
                "low": int(sev.get("LOW", 0)),
            })
            if len(runs) >= 100:
                break
    latest_run_id = runs[0]["run_id"] if runs else None
    return render_template("runs.html", runs=runs, latest_run_id=latest_run_id,)'''


datasource_def = '''@app.route("/datasource")
def datasource():
    """Data Source: show JSON source for latest RUN (summary_unified + findings)."""
    base = Path(__file__).resolve().parents[1]
    out_dir = base / "out"

    runs = []
    if out_dir.is_dir():
        for run_dir in sorted(out_dir.glob("RUN_*"), reverse=True):
            report_dir = run_dir / "report"
            summary_path = report_dir / "summary_unified.json"
            if not summary_path.is_file():
                continue
            try:
                raw = json.loads(summary_path.read_text(encoding="utf-8"))
            except Exception:
                continue
            sev = raw.get("severity_counts") or raw.get("SEVERITY_COUNTS") or {}
            total = raw.get("total_findings") or raw.get("TOTAL_FINDINGS") or 0
            runs.append({
                "run_id": run_dir.name,
                "run_path": str(run_dir),
                "total": int(total),
                "critical": int(sev.get("CRITICAL", 0)),
                "high": int(sev.get("HIGH", 0)),
                "medium": int(sev.get("MEDIUM", 0)),
                "low": int(sev.get("LOW", 0)),
            })
            if len(runs) >= 1:
                break

    if not runs:
        return render_template(
            "datasource.html",
            ds_run_id=None,
            ds_run_path=None,
            summary_path=None,
            findings_path=None,
            findings_sample=[],
            summary_preview=None,
            findings_raw_url=None,
        )

    latest = runs[0]
    run_dir = out_dir / latest["run_id"]
    report_dir = run_dir / "report"
    summary_path = report_dir / "summary_unified.json"
    findings_path = report_dir / "findings.json"

    try:
        summary = json.loads(summary_path.read_text(encoding="utf-8"))
    except Exception:
        summary = None

    findings_sample = []
    if findings_path.is_file():
        try:
            all_findings = json.loads(findings_path.read_text(encoding="utf-8"))
        except Exception:
            all_findings = []
        for f in all_findings[:30]:
            findings_sample.append({
                "severity": f.get("severity") or f.get("SEVERITY") or f.get("level", ""),
                "tool": f.get("tool") or f.get("TOOL", ""),
                "rule_id": f.get("rule_id") or f.get("rule") or "",
                "location": f.get("location") or f.get("path") or "",
                "msg": f.get("message") or f.get("msg") or "",
            })

    if summary is not None:
        try:
            summary_preview = json.dumps(summary, indent=2, ensure_ascii=False)[:4000]
        except Exception:
            summary_preview = ""
    else:
        summary_preview = ""

    findings_raw_url = None

    return render_template(
        "datasource.html",
        ds_run_id=latest["run_id"],
        ds_run_path=str(run_dir),
        summary_path=str(summary_path),
        findings_path=str(findings_path),
        findings_sample=findings_sample,
        summary_preview=summary_preview,
        findings_raw_url=findings_raw_url,
    )'''


settings_def = '''@app.route("/settings")
def settings():
    """Settings view - read tool_config.json (read-only)."""
    config_path = Path(__file__).resolve().with_name("tool_config.json")
    tool_rows = []
    tool_config_raw = None

    if config_path.is_file():
        try:
            raw_text = config_path.read_text(encoding="utf-8")
            tool_config_raw = raw_text
            raw = json.loads(raw_text)
        except Exception:
            raw = None
        else:
            if isinstance(raw, dict):
                for name, cfg in raw.items():
                    tool_rows.append({
                        "name": name,
                        "enabled": bool(cfg.get("enabled", True)),
                        "level": cfg.get("level") or cfg.get("profile") or "",
                        "modes": cfg.get("modes") or cfg.get("mode") or "",
                        "notes": cfg.get("notes") or cfg.get("desc") or "",
                    })

    tool_rows.sort(key=lambda r: r["name"].lower())

    return render_template(
        "settings.html",
        tool_rows=tool_rows,
        tool_config_path=str(config_path),
        tool_config_raw=tool_config_raw,
    )'''


data = replace_route_block(data, "/runs", runs_def)
data = replace_route_block(data, "/datasource", datasource_def)
data = replace_route_block(data, "/settings", settings_def)

path.write_text(data, encoding="utf-8")
print("[OK] Patched /runs, /datasource, /settings with simple blocks.")
PY
