#!/usr/bin/env bash
set -euo pipefail

cd /home/test/Data/SECURITY_BUNDLE/ui

APP="app.py"
cp "$APP" "$APP.bak_fix_quotes_$(date +%Y%m%d_%H%M%S)" || true

python3 - <<'PY'
from pathlib import Path

path = Path("app.py")
data = path.read_text(encoding="utf-8")

start = data.find("# === _SB_HELPER_RUN_INDEX_V2 start ===")
end = data.find("# === _SB_HELPER_RUN_INDEX_V2 end ===")
if start == -1 or end == -1:
    print("[ERR] Không tìm thấy marker helper, không sửa được.")
    raise SystemExit(1)

# move end to sau dòng end
end = data.find("\n", end)
if end == -1:
    end = len(data)
else:
    end = end + 1

new_block = '''# === _SB_HELPER_RUN_INDEX_V2 start ===
from pathlib import Path
import json

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


@app.route("/runs")
def runs():
    """Runs & Reports history from out/RUN_* (newest first)."""
    runs = _load_runs_index(max_items=100)
    latest_run_id = runs[0]["run_id"] if runs else None
    return render_template("runs.html", runs=runs, latest_run_id=latest_run_id,)


@app.route("/datasource")
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


@app.route("/settings")
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

# === _SB_HELPER_RUN_INDEX_V2 end ===
'''

data = data[:start] + new_block + data[end:]
path.write_text(data, encoding="utf-8")
print("[OK] Replaced helper block without escaped quotes.")
PY
