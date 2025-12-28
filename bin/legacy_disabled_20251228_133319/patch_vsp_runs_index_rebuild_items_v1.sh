#!/usr/bin/env bash
set -euo pipefail

LOG_PREFIX="[PATCH_VSP_RUNS_INDEX_REBUILD_ITEMS_V1]"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/vsp_demo_app.py"

echo "$LOG_PREFIX ROOT = $ROOT"
echo "$LOG_PREFIX APP  = $APP"

if [ ! -f "$APP" ]; then
  echo "$LOG_PREFIX [ERR] Không tìm thấy $APP" >&2
  exit 1
fi

ts="$(date +%Y%m%d_%H%M%S)"
backup="${APP}.bak_runs_index_rebuild_items_${ts}"
cp "$APP" "$backup"
echo "$LOG_PREFIX [BACKUP] $backup"

cd "$ROOT"

python - << 'PY'
import pathlib, textwrap, json, os, datetime

LOG_PREFIX = "[PATCH_VSP_RUNS_INDEX_REBUILD_ITEMS_V1]"
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

    Ưu tiên:
    1) Đọc KPI + trend từ out/summary_by_run.json (nếu có).
    2) Tự quét thư mục out/RUN_* để build danh sách items (list run)
       nên không phụ thuộc schema summary_by_run.json nữa.
    """
    import json
    from pathlib import Path
    from flask import request, jsonify
    import os
    import datetime

    root = Path(__file__).resolve().parent.parent
    out_dir = root / "out"
    summary_path = out_dir / "summary_by_run.json"

    kpi = {}
    trend = []

    # (1) Đọc KPI + trend (nếu có)
    if summary_path.exists():
        try:
            with summary_path.open("r", encoding="utf-8") as f:
                summary = json.load(f)
            if isinstance(summary, dict):
                kpi = summary.get("kpi") or {}
                trend = summary.get("trend_crit_high") or summary.get("trend") or []
        except Exception:
            pass

    # (2) Quét thư mục RUN_* để build items
    items = []

    # Duyệt tất cả thư mục RUN_* trong out/
    run_dirs = [p for p in out_dir.iterdir() if p.is_dir() and p.name.startswith("RUN_")]
    # Sắp xếp theo thời gian sửa đổi mới nhất (mới -> cũ)
    run_dirs.sort(key=lambda p: p.stat().st_mtime, reverse=True)

    for run_dir in run_dirs:
        run_id = run_dir.name
        report_dir = run_dir / "report"
        summary_file = report_dir / "summary_unified.json"
        if not summary_file.exists():
            continue

        try:
            with summary_file.open("r", encoding="utf-8") as f:
                s = json.load(f)
        except Exception:
            continue

        # Lấy total_findings
        total_findings = None
        # Ưu tiên các kiểu phổ biến
        if isinstance(s, dict):
            # Kiểu summary_all.total_findings
            total_findings = (
                s.get("summary_all", {}).get("total_findings")
                if isinstance(s.get("summary_all"), dict)
                else None
            )
            # Kiểu top-level total_findings
            if total_findings is None:
                total_findings = s.get("total_findings")

            # Nếu vẫn None, thử tính từ by_severity
            if total_findings is None:
                sev = None
                if "summary_all" in s and isinstance(s["summary_all"], dict):
                    sev = s["summary_all"].get("by_severity")
                if sev is None:
                    sev = s.get("by_severity")
                if isinstance(sev, dict):
                    try:
                        total_findings = int(sum(int(v) for v in sev.values()))
                    except Exception:
                        total_findings = None

            # Run type / source
            run_profile = s.get("run_profile") if isinstance(s.get("run_profile"), dict) else {}
            run_type = run_profile.get("type") or run_profile.get("run_type") or "UNKNOWN"
            source = run_profile.get("source") or run_profile.get("source_type") or "FULL_EXT"

            # Score nếu có
            score = s.get("security_posture_score")
            if score is None and isinstance(s.get("summary_all"), dict):
                score = s["summary_all"].get("security_posture_score")

            # Time nếu có
            started_at = run_profile.get("started_at") or run_profile.get("started") or None
        else:
            run_type = "UNKNOWN"
            source = "FULL_EXT"
            score = None
            started_at = None

        # Nếu vẫn chưa có total_findings, bỏ qua run này
        if total_findings is None:
            continue

        # Nếu không có started_at thì lấy mtime thư mục
        if not started_at:
            try:
                dt = datetime.datetime.fromtimestamp(run_dir.stat().st_mtime)
                started_at = dt.isoformat(timespec="seconds")
            except Exception:
                started_at = ""

        item = {
            "run_id": run_id,
            "run_type": run_type,
            "source": source,
            "total_findings": int(total_findings),
            "security_posture_score": score if isinstance(score, (int, float)) else None,
            "started_at": started_at,
        }
        items.append(item)

    # (3) Áp dụng limit
    try:
        limit = int(request.args.get("limit", 50))
    except Exception:
        limit = 50
    items_slice = items[:limit]

    # (4) Nếu chưa có KPI thì tự build
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
