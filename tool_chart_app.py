#!/usr/bin/env python3
import json
import subprocess
from pathlib import Path

from flask import Flask, render_template

ROOT = Path("/home/test/Data/SECURITY_BUNDLE")
TEMPLATES = ROOT / "ui" / "templates"

app = Flask(__name__, template_folder=str(TEMPLATES))

# Map label đẹp cho tool (có thể chỉnh sửa tuỳ ý)
TOOL_LABELS = {
    "Semgrep": "Semgrep (Code)",
    "Bandit": "Bandit (Python)",
    "Gitleaks": "Gitleaks (Secrets)",
    "TrivyVuln": "Trivy FS (Vuln)",
    "TrivySecret": "Trivy FS (Secrets)",
    "TrivyMisconfig": "Trivy FS (Misconfig)",
    "TrivySBOM": "Trivy SBOM",
    "Grype": "Grype (SBOM SCA)",
}


def get_last_run_dir() -> Path:
    """Gọi last_run.sh để lấy RUN mới nhất."""
    script = ROOT / "bin" / "last_run.sh"
    if not script.is_file():
        raise RuntimeError(f"Không tìm thấy last_run.sh tại {script}")
    out = subprocess.check_output([str(script)], text=True).strip()
    if not out:
        raise RuntimeError("last_run.sh không trả về RUN dir")
    p = Path(out)
    if not p.is_dir():
        raise RuntimeError(f"RUN dir không tồn tại: {p}")
    return p


def try_load_json(path: Path):
    if not path.is_file():
        return None
    with path.open(encoding="utf-8") as f:
        return json.load(f)


def build_by_tool(run_dir: Path):
    """
    Trả về (by_tool_dict, summary_dict hoặc None).

    Ưu tiên dùng summary_unified.json nếu có by_tool,
    nếu không thì tự tính từ findings.json.
    """
    summary_path = run_dir / "report" / "summary_unified.json"
    findings_path = run_dir / "report" / "findings.json"

    summary = try_load_json(summary_path) or {}
    by_tool = summary.get("by_tool") if isinstance(summary, dict) else None
    if isinstance(by_tool, dict) and by_tool:
        # Đã có by_tool trong summary → dùng luôn
        return by_tool, summary

    # Không có by_tool trong summary → tự tính từ findings.json
    findings = try_load_json(findings_path)
    if not isinstance(findings, list):
        return {}, summary

    agg = {}
    for item in findings:
        if not isinstance(item, dict):
            continue
        tool = (
            item.get("tool")
            or item.get("category")
            or item.get("source")
            or "Unknown"
        )
        d = agg.setdefault(tool, {"total": 0})
        d["total"] += 1

    return agg, summary


@app.route("/")
def tool_chart():
    run_dir = get_last_run_dir()
    by_tool, summary = build_by_tool(run_dir)

    tools = []
    for key, data in by_tool.items():
        total = int(data.get("total", 0)) if isinstance(data, dict) else int(data or 0)
        label = TOOL_LABELS.get(key, key)
        tools.append({
            "key": key,
            "label": label,
            "total": total,
        })

    # sort tool theo total giảm dần
    tools.sort(key=lambda x: x["total"], reverse=True)
    max_total = max((t["total"] for t in tools), default=0)

    return render_template(
        "tool_chart.html",
        tools=tools,
        max_total=max_total,
        run_dir=str(run_dir),
    )


if __name__ == "__main__":
    # Port riêng, tránh đụng 8905
    app.run(host="0.0.0.0", port=8910, debug=True)
