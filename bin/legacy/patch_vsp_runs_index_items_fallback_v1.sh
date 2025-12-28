#!/usr/bin/env bash
set -euo pipefail

LOG_PREFIX="[PATCH_VSP_RUNS_INDEX_ITEMS_FALLBACK_V1]"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/vsp_demo_app.py"

echo "$LOG_PREFIX ROOT = $ROOT"
echo "$LOG_PREFIX APP  = $APP"

if [ ! -f "$APP" ]; then
  echo "$LOG_PREFIX [ERR] Không tìm thấy $APP" >&2
  exit 1
fi

ts="$(date +%Y%m%d_%H%M%S)"
backup="${APP}.bak_runs_index_items_fallback_${ts}"
cp "$APP" "$backup"
echo "$LOG_PREFIX [BACKUP] $backup"

cd "$ROOT"

python - << 'PY'
import pathlib, textwrap

LOG_PREFIX = "[PATCH_VSP_RUNS_INDEX_ITEMS_FALLBACK_V1]"
app_path = pathlib.Path("vsp_demo_app.py")
txt = app_path.read_text(encoding="utf-8")
lines = txt.splitlines()

def replace_route_block(lines, route_path, new_block):
    dec_line = f'@app.route("{route_path}"'
    start = None
    for i, line in enumerate(lines):
        norm = line.replace("'", '"')
        if dec_line in norm:
            start = i
            break
    if start is None:
        print(f"{LOG_PREFIX} [ERR] Không tìm thấy route {route_path} trong file.")
        return lines

    base_indent = len(lines[start]) - len(lines[start].lstrip())
    end = len(lines)
    for j in range(start + 1, len(lines)):
        line = lines[j]
        if not line.strip():
            continue
        indent = len(line) - len(line.lstrip())
        if indent <= base_indent and (
            line.lstrip().startswith("def ")
            or line.lstrip().startswith("@app.route")
            or line.lstrip().startswith("class ")
        ):
            end = j
            break

    print(f"{LOG_PREFIX} Patch {route_path}: lines {start}..{end}")
    new_block_lines = textwrap.dedent(new_block).splitlines()
    return lines[:start] + new_block_lines + lines[end:]


new_runs_block = '''
@app.route("/api/vsp/runs_index_v3")
def api_vsp_runs_index_v3():
    """
    Local implementation cho Runs & Reports tab (VSP 2025 UI demo).

    Đọc summary_by_run.json trong SECURITY_BUNDLE/out và
    expose items + kpi + trend_crit_high cho UI.
    """
    import json
    from pathlib import Path
    from flask import request, jsonify

    root = Path(__file__).resolve().parent.parent
    out_dir = root / "out"
    summary_path = out_dir / "summary_by_run.json"

    try:
        with summary_path.open("r", encoding="utf-8") as f:
            summary = json.load(f)
    except FileNotFoundError:
        return jsonify({"ok": False, "error": f"Missing {summary_path}"}), 500

    # Chuẩn hóa items theo nhiều kiểu schema khác nhau
    if isinstance(summary, dict):
        raw_items = (
            summary.get("items")
            or summary.get("by_run")
            or summary.get("runs")
            or summary.get("data")
        )
        if isinstance(raw_items, list):
            items = raw_items
        else:
            items = []
        kpi = summary.get("kpi") or {}
        trend = summary.get("trend_crit_high") or summary.get("trend") or []
    else:
        items = summary if isinstance(summary, list) else []
        kpi = {}
        trend = []

    try:
        limit = int(request.args.get("limit", 50))
    except Exception:
        limit = 50

    items_slice = items[:limit]

    # Nếu summary_by_run.json chưa có kpi ⇒ tự tính KPI cơ bản
    if not kpi:
        total_runs = len(items)
        last_n = min(total_runs, 20)
        if last_n > 0:
            last_items = items[:last_n]
            total_findings_sum = 0
            for it in last_items:
                try:
                    total_findings_sum += int(it.get("total_findings", 0))
                except Exception:
                    continue
            avg_last_n = total_findings_sum / float(last_n) if last_n > 0 else 0.0
        else:
            avg_last_n = 0.0

        kpi = {
            "total_runs": total_runs,
            "last_n": last_n,
            "avg_findings_per_run_last_n": avg_last_n,
        }

    return jsonify(
        {
            "ok": True,
            "items": items_slice,
            "kpi": kpi,
            "trend_crit_high": trend,
        }
    )
'''

lines = replace_route_block(lines, "/api/vsp/runs_index_v3", new_runs_block)

new_txt = "\n".join(lines) + "\n"
app_path.write_text(new_txt, encoding="utf-8")
print(f"{LOG_PREFIX} Done patching {app_path}")
PY

echo "$LOG_PREFIX Hoàn tất."
