#!/usr/bin/env bash
set -euo pipefail

ROOT="/home/test/Data/SECURITY_BUNDLE/ui"
cd "$ROOT"
APP="app.py"

python3 - "$APP" <<'PY'
import sys, pathlib, json, re

app_path = pathlib.Path(sys.argv[1])
data = app_path.read_text(encoding="utf-8")

# ensure imports
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

# insert helper block if missing
if "_load_runs_index" not in data:
    marker = "app = Flask("
    idx = data.find(marker)
    if idx != -1:
        insert_pos = data.find("\n", idx)
        insert_pos = data.find("\n", insert_pos + 1)
        helper = '''

# === SECURITY_BUNDLE helper for RUN index / Data Source ===
ROOT = Path(__file__).resolve().parents[1]
OUT_DIR = ROOT / "out"


def _load_runs_index(max_items: int = 50):
    runs = []
    if not OUT_DIR.is_dir():
        return runs
    for run_dir in sorted(OUT_DIR.glob("RUN_*"), reverse=True):
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
        if len(runs) >= max_items:
            break
    return runs


def _load_latest_run_for_datasource():
    runs = _load_runs_index(max_items=1)
    if not runs:
        return None
    latest = runs[0]
    run_dir = OUT_DIR / latest["run_id"]
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
    return {
        "run": latest,
        "run_dir": str(run_dir),
        "summary_path": str(summary_path),
        "findings_path": str(findings_path),
        "findings_sample": findings_sample,
        "summary_preview": summary_preview,
    }

'''
        data = data[:insert_pos] + helper + data[insert_pos:]


# helper to replace a route block
def replace_route(data_str, route_path, new_block):
    pattern = re.compile(
        r'@app.route\\("%s"\\)[\\s\\S]*?(?=^@app.route\\(|^if __name__ == "__main__":|\\Z)' % route_path,
        re.MULTILINE,
    )
    if pattern.search(data_str):
        return pattern.sub(new_block + "\\n\\n", data_str, count=1)
    return data_str

# new /runs
block_runs = '''@app.route("/runs")
def runs():
    """Runs & Reports history from out/RUN_* (newest first)."""
    runs = _load_runs_index(max_items=100)
    latest_run_id = runs[0]["run_id"] if runs else None
    return render_template("runs.html", runs=runs, latest_run_id=latest_run_id,)
'''

# new /datasource
block_ds = '''@app.route("/datasource")
def datasource():
    """Data Source: show JSON source for latest RUN (summary_unified + findings)."""
    ctx = _load_latest_run_for_datasource()
    if not ctx:
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

    run = ctx["run"]
    findings_raw_url = None

    return render_template(
        "datasource.html",
        ds_run_id=run["run_id"],
        ds_run_path=ctx["run_dir"],
        summary_path=ctx["summary_path"],
        findings_path=ctx["findings_path"],
        findings_sample=ctx["findings_sample"],
        summary_preview=ctx["summary_preview"],
        findings_raw_url=findings_raw_url,
    )
'''

# new /settings
block_settings = '''@app.route("/settings")
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
    )
'''

data = replace_route(data, "/runs", block_runs)
data = replace_route(data, "/datasource", block_ds)
data = replace_route(data, "/settings", block_settings)

app_path.write_text(data, encoding="utf-8")
PY

echo "[OK] Patched app.py for runs / datasource / settings."
