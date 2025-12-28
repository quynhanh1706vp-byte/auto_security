#!/usr/bin/env bash
set -euo pipefail

LOG_PREFIX="[PATCH_VSP_CORE_DATASOURCE_RUNS_V1]"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/vsp_demo_app.py"

echo "$LOG_PREFIX ROOT = $ROOT"
echo "$LOG_PREFIX APP  = $APP"

if [ ! -f "$APP" ]; then
  echo "$LOG_PREFIX [ERR] Không tìm thấy $APP" >&2
  exit 1
fi

ts="$(date +%Y%m%d_%H%M%S)"
backup="${APP}.bak_datasource_runs_v1_${ts}"
cp "$APP" "$backup"
echo "$LOG_PREFIX [BACKUP] $backup"

cd "$ROOT"

python - << 'PY'
import pathlib, textwrap

LOG_PREFIX = "[PATCH_VSP_CORE_DATASOURCE_RUNS_V1]"
app_path = pathlib.Path("vsp_demo_app.py")
txt = app_path.read_text(encoding="utf-8")
lines = txt.splitlines()

def replace_route_block(lines, route_path, new_block):
    dec_line = f'@app.route("{route_path}"'
    start = None
    for i, line in enumerate(lines):
        # Chuẩn hóa dùng dấu "
        norm = line.replace("'", '"')
        if dec_line in norm:
            start = i
            break
    if start is None:
        print(f"{LOG_PREFIX} [WARN] Không tìm thấy route {route_path} – bỏ qua.")
        return lines

    base_indent = len(lines[start]) - len(lines[start].lstrip())
    end = len(lines)
    for j in range(start + 1, len(lines)):
        line = lines[j]
        if not line.strip():
            continue
        indent = len(line) - len(line.lstrip())
        # Khi gặp def/@app/class cùng hoặc thấp indent ⇒ sang block khác
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


new_datasource_block = '''
@app.route("/api/vsp/datasource_v2")
def api_vsp_datasource_v2():
    """
    Local implementation cho Data Source tab (VSP 2025 UI demo).

    Thay vì proxy sang core, route này đọc trực tiếp
    findings_unified.json của latest FULL_EXT run trong
    SECURITY_BUNDLE/out.
    """
    import json
    from pathlib import Path
    from flask import request, jsonify

    # SECURITY_BUNDLE root = parent của thư mục ui/
    root = Path(__file__).resolve().parent.parent
    out_dir = root / "out"

    dash_path = out_dir / "vsp_dashboard_v3_latest.json"
    try:
        with dash_path.open("r", encoding="utf-8") as f:
            dash = json.load(f)
    except FileNotFoundError:
        return jsonify({"ok": False, "error": f"Missing {dash_path}"}), 500

    latest_run = dash.get("latest_run_id")
    if not latest_run:
        return jsonify(
            {"ok": False, "error": "No latest_run_id in vsp_dashboard_v3_latest.json"}
        ), 500

    findings_path = out_dir / latest_run / "report" / "findings_unified.json"
    try:
        with findings_path.open("r", encoding="utf-8") as f:
            data = json.load(f)
    except FileNotFoundError:
        return jsonify(
            {
                "ok": False,
                "error": f"Missing findings_unified.json for run {latest_run}",
            }
        ), 500

    # data có thể là list hoặc {items: [...], total: N}
    if isinstance(data, dict) and "items" in data:
        items = data.get("items") or []
        total = int(data.get("total", len(items)))
    else:
        items = data
        total = len(items)

    try:
        limit = int(request.args.get("limit", 100))
    except Exception:
        limit = 100

    items_slice = items[:limit]

    return jsonify(
        {
            "ok": True,
            "run_id": latest_run,
            "total": total,
            "limit": limit,
            "items": items_slice,
        }
    )
'''

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

    if isinstance(summary, dict):
        items = summary.get("items") or []
        kpi = summary.get("kpi") or {}
        trend = summary.get("trend_crit_high") or []
    else:
        items = summary
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
            avg_last_n = (
                total_findings_sum / float(last_n) if last_n > 0 else 0.0
            )
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

lines = replace_route_block(lines, "/api/vsp/datasource_v2", new_datasource_block)
lines = replace_route_block(lines, "/api/vsp/runs_index_v3", new_runs_block)

new_txt = "\n".join(lines) + "\n"
app_path.write_text(new_txt, encoding="utf-8")
print(f"{LOG_PREFIX} Done patching {app_path}")
PY

echo "$LOG_PREFIX Hoàn tất."
