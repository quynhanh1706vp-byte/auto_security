#!/usr/bin/env bash
set -euo pipefail

ROOT="/home/test/Data/SECURITY_BUNDLE"
UI_ROOT="$ROOT/ui"

echo "=== [1] Check API CORE 8961 /runs_index_v3 ==="
if curl -s "http://localhost:8961/api/vsp/runs_index_v3?limit=3" >/tmp/vsp_core_runs.json 2>/tmp/vsp_core_runs.err; then
  echo "  -> OK: nhận JSON từ 8961"
  jq '.items | length as $n | "items=\($n)", (if $n>0 then .items[0] else "no_items" end)' /tmp/vsp_core_runs.json
else
  echo "  -> LỖI gọi 8961, xem /tmp/vsp_core_runs.err"
fi

echo
echo "=== [2] Check API UI 8910 /runs_index_v3 (proxy) ==="
if curl -s "http://localhost:8910/api/vsp/runs_index_v3?limit=3" >/tmp/vsp_ui_runs.json 2>/tmp/vsp_ui_runs.err; then
  echo "  -> OK: nhận JSON từ 8910"
  jq '.items | length as $n | "items=\($n)", (if $n>0 then .items[0] else "no_items" end)' /tmp/vsp_ui_runs.json
else
  echo "  -> LỖI gọi 8910, xem /tmp/vsp_ui_runs.err"
fi

echo
echo "=== [3] GREP runs_index_v3 trong UI ==="
cd "$UI_ROOT"
grep -R "runs_index_v3" -n . || echo "  (không tìm thấy chuỗi runs_index_v3 trong UI)"

echo
TPL_MAIN="$UI_ROOT/templates/vsp_dashboard_2025.html"
echo "=== [4] Kiểm tra script RUNS trong $TPL_MAIN ==="
if [ -f "$TPL_MAIN" ]; then
  grep -n "vsp_runs" "$TPL_MAIN" || echo "  (template không nhắc tới vsp_runs*)"
else
  echo "  -> KHÔNG tìm thấy template $TPL_MAIN"
fi

echo
echo "=== [5] Tìm khai báo trùng VSP_RUN_EXPORT_BASE, VSP_RUNS_UI_v1 ==="
grep -R "VSP_RUN_EXPORT_BASE" -n static/js || echo "  (không thấy VSP_RUN_EXPORT_BASE)"
grep -R "VSP_RUNS_UI_v1" -n static/js || echo "  (không thấy VSP_RUNS_UI_v1)"

echo
echo "=== [6] Liệt kê các file JS có chữ 'runs' trong tên ==="
ls static/js | grep -i "runs" || echo "  (không có file nào chứa 'runs' trong tên)"

echo
echo "=== DONE – hãy xem các WARNING/khác biệt ở trên để biết sai chỗ nào ==="
