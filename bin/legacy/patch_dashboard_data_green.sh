#!/usr/bin/env bash
set -euo pipefail

cd /home/test/Data/SECURITY_BUNDLE/ui
APP="app.py"

cp "$APP" "$APP.bak_$(date +%Y%m%d_%H%M%S)" || true

python3 - "$APP" <<'PY'
from pathlib import Path
import textwrap
import re

path = Path("app.py")
data = path.read_text(encoding="utf-8")

pattern = r"@app\.route\(\s*['\"]/['\"][^)]*\)"
m = re.search(pattern, data)

if m:
    start = m.start()
    rest = data[start:]
    m2 = re.search(r"\n@app\.route\(", rest[1:])
    if m2:
        end = start + 1 + m2.start()
    else:
        end = len(data)
    before = data[:start]
    after = data[end:]
else:
    before = data.rstrip() + "\n\n"
    after = ""

body_new = textwrap.dedent('''
@app.route("/")
def index():
    # Dashboard main: latest RUN_* summary_unified.json + findings.json
    import json
    from pathlib import Path

    root = Path(__file__).resolve().parent.parent  # /home/test/Data/SECURITY_BUNDLE
    out_dir = root / "out"

    run_dirs = sorted(
        [p for p in out_dir.glob("RUN_*") if p.is_dir() and not p.name.startswith("RUN_DEMO_")],
        key=lambda p: p.stat().st_mtime,
        reverse=True,
    )

    summary = {
        "run_id": None,
        "src": "",
        "total": 0,
        "critical": 0,
        "high": 0,
        "medium": 0,
        "low": 0,
        "info": 0,
        "tools": [],
        "critical_pct": 0,
        "high_pct": 0,
        "medium_pct": 0,
        "low_pct": 0,
        "info_pct": 0,
    }

    trend = []
    top_risks = []

    def parse_summary(path, run_name):
        try:
            raw = json.loads(path.read_text(encoding="utf-8"))
        except Exception as e:
            print(f"[ERR][INDEX] cannot read {path}: {e}")
            return None

        total = (
            raw.get("total_findings")
            or raw.get("TOTAL_FINDINGS")
            or raw.get("total")
            or raw.get("total_findings_all")
            or 0
        )

        sev_raw = (
            raw.get("severity_counts")
            or raw.get("SEVERITY_COUNTS")
            or raw.get("by_severity")
            or raw.get("severity")
            or {}
        )
        sev = {str(k).upper(): int(v) for k, v in sev_raw.items()}

        return {
            "run_id": run_name,
            "src": raw.get("src") or raw.get("SRC") or "",
            "total": int(total),
            "critical": sev.get("CRITICAL", 0),
            "high": sev.get("HIGH", 0),
            "medium": sev.get("MEDIUM", 0),
            "low": sev.get("LOW", 0),
            "info": sev.get("INFO", 0),
        }

    if run_dirs:
        # latest run
        run_dir = run_dirs[0]
        report_dir = run_dir / "report"
        summary_path = report_dir / "summary_unified.json"
        findings_path = report_dir / "findings.json"

        parsed = parse_summary(summary_path, run_dir.name)
        if parsed:
            summary.update(parsed)

        # percentages for severity bar chart
        max_bucket = max(
            summary["critical"],
            summary["high"],
            summary["medium"],
            summary["low"],
            summary["info"],
            1,
        )
        if max_bucket > 0:
            summary["critical_pct"] = int(summary["critical"] * 100 / max_bucket)
            summary["high_pct"] = int(summary["high"] * 100 / max_bucket)
            summary["medium_pct"] = int(summary["medium"] * 100 / max_bucket)
            summary["low_pct"] = int(summary["low"] * 100 / max_bucket)
            summary["info_pct"] = int(summary["info"] * 100 / max_bucket)

        # per-tool counts
        try:
            raw2 = json.loads(summary_path.read_text(encoding="utf-8"))
        except Exception:
            raw2 = {}
        tools_raw = raw2.get("by_tool") or raw2.get("BY_TOOL") or raw2.get("tools") or {}
        tools = []
        for name, counts in tools_raw.items():
            if isinstance(counts, dict):
                count_val = int(counts.get("count", 0))
            else:
                try:
                    count_val = int(counts)
                except Exception:
                    count_val = 0
            tools.append({"name": name, "count": count_val})
        summary["tools"] = tools

        # Trend – last runs (up to 6)
        for rd in run_dirs[:6]:
            sp = rd / "report" / "summary_unified.json"
            if not sp.is_file():
                continue
            parsed_trend = parse_summary(sp, rd.name)
            if parsed_trend:
                trend.append(parsed_trend)

        # Top risk findings from findings.json
        try:
            raw_findings = json.loads(findings_path.read_text(encoding="utf-8"))
            if isinstance(raw_findings, dict) and "items" in raw_findings:
                items = raw_findings.get("items") or []
            elif isinstance(raw_findings, list):
                items = raw_findings
            else:
                items = []
        except Exception as e:
            print(f"[WARN][INDEX] cannot read findings from {findings_path}: {e}")
            items = []

        def pick(d, keys, default=""):
            for k in keys:
                if k in d and d[k]:
                    return d[k]
            return default

        severity_order = {"CRITICAL": 4, "HIGH": 3, "MEDIUM": 2, "LOW": 1, "INFO": 0}

        for it in items:
            if not isinstance(it, dict):
                continue
            sev_raw_item = str(pick(it, ["severity_norm", "SEVERITY", "severity"], "INFO")).upper()
            sev_rank = severity_order.get(sev_raw_item, 0)
            rule_id = pick(it, ["rule_id", "id", "check_id", "rule", "type"], "")
            tool = pick(it, ["tool", "source", "scanner"], "")
            msg = pick(it, ["message_short", "message", "msg", "description", "detail"], "")
            path_val = pick(it, ["file", "path", "target", "location"], "")
            line_val = pick(it, ["line", "line_number", "start_line"], "")

            top_risks.append(
                {
                    "severity": sev_raw_item,
                    "severity_rank": sev_rank,
                    "rule_id": rule_id,
                    "tool": tool,
                    "msg": msg,
                    "path": path_val,
                    "line": line_val,
                }
            )

        top_risks.sort(key=lambda x: (x["severity_rank"], x["rule_id"]), reverse=True)
        top_risks = top_risks[:10]

    print(
        f"[INFO][INDEX] RUN={summary['run_id']}, total={summary['total']}, "
        f"C={summary['critical']}, H={summary['high']}, "
        f"M={summary['medium']}, L={summary['low']}"
    )

    return render_template("index.html", summary=summary, trend=trend, top_risks=top_risks)
''').lstrip()

path.write_text(before + body_new + "\n\n" + after, encoding="utf-8")
print("[OK] patched index() for Dashboard data")
PY
