#!/usr/bin/env bash
set -euo pipefail

BIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$BIN_DIR/../.." && pwd)"
OUT_DIR="$ROOT/out"

echo "[VSP_DASH_FIX] ROOT = $ROOT"
echo "[VSP_DASH_FIX] OUT_DIR = $OUT_DIR"

if [ ! -d "$OUT_DIR" ]; then
  echo "[VSP_DASH_FIX] [ERR] Không tìm thấy thư mục out/ tại $OUT_DIR"
  exit 1
fi

export VSP_ROOT="$ROOT"

python - << 'PY'
import os, json, pathlib

root = pathlib.Path(os.environ["VSP_ROOT"]).resolve()
out_dir = root / "out"
print("[VSP_DASH_FIX_PY] ROOT =", root)
print("[VSP_DASH_FIX_PY] OUT_DIR =", out_dir)

candidates = sorted(out_dir.glob("RUN_VSP_FULL_EXT*/report/summary_unified.json"))
if not candidates:
    print("[VSP_DASH_FIX_PY][ERR] Không tìm thấy RUN_VSP_FULL_EXT*/report/summary_unified.json")
    raise SystemExit(1)

sev_keys = ["CRITICAL", "HIGH", "MEDIUM", "LOW", "INFO", "TRACE"]

def compute_totals(path: pathlib.Path):
    data = json.loads(path.read_text(encoding="utf-8"))
    sev_map = data.get("summary_by_severity") or {}
    by_sev = {k: int(sev_map.get(k, 0) or 0) for k in sev_keys}
    total = int(sum(by_sev.values()))
    return total, by_sev

# 1) Ưu tiên run FULL_EXT mới nhất có total_findings > 0
chosen = None
chosen_total = 0
chosen_by_sev = None

for p in sorted(candidates, key=lambda x: x.stat().st_mtime, reverse=True):
    total, by_sev = compute_totals(p)
    run_dir = p.parents[1]
    run_id = run_dir.name
    print(f"[VSP_DASH_FIX_PY] Candidate {run_id}: total={total}")
    if total > 0:
        chosen = (run_id, p, by_sev, total)
        break

# 2) Nếu tất cả đều 0, lấy run mới nhất bất kỳ
if chosen is None:
    latest = max(candidates, key=lambda p: p.stat().st_mtime)
    run_dir = latest.parents[1]
    run_id = run_dir.name
    total, by_sev = compute_totals(latest)
    chosen = (run_id, latest, by_sev, total)

run_id, summary_path, by_sev, total_findings = chosen
print(f"[VSP_DASH_FIX_PY] Chọn run FULL_EXT cho dashboard: {run_id} (total={total_findings})")

dash_file = out_dir / "vsp_dashboard_v3_latest.json"
if dash_file.exists():
    dash = json.loads(dash_file.read_text(encoding="utf-8"))
else:
    dash = {}

dash["latest_run_id"] = run_id
dash["total_findings"] = int(total_findings)
dash["by_severity"] = {k: int(by_sev.get(k, 0) or 0) for k in sev_keys}

dash_file.write_text(json.dumps(dash, indent=2, ensure_ascii=False), encoding="utf-8")
print("[VSP_DASH_FIX_PY] Đã ghi", dash_file)
PY

echo "[VSP_DASH_FIX] Hoàn tất cập nhật vsp_dashboard_v3_latest.json (FULL_EXT)."
