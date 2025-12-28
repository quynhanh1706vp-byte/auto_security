#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

for JS in "static/js/vsp_dashboard_kpi_v1.js" "static/js/vsp_dashboard_charts_v1.js"; do
  FILE="$ROOT/$JS"
  if [ ! -f "$FILE" ]; then
    echo "[WARN] Không thấy $JS – bỏ qua."
    continue
  fi

  BAK="${FILE}.bak_top_module_$(date +%Y%m%d_%H%M%S)"
  cp "$FILE" "$BAK"
  echo "[BACKUP] $FILE -> $BAK"

  python - << PY
from pathlib import Path

path = Path("$FILE")
txt = path.read_text(encoding="utf-8")

inject = """
function vspNormalizeTopModule(m) {
  if (!m) return 'N/A';
  if (typeof m === 'string') return m;
  try {
    if (m.label) return String(m.label);
    if (m.path) return String(m.path);
    if (m.id)   return String(m.id);
    return String(m);
  } catch (e) {
    return 'N/A';
  }
}
"""

if "vspNormalizeTopModule" not in txt:
    txt = inject + "\\n" + txt
    print("[PATCH] Inject helper vspNormalizeTopModule() vào", path.name)
else:
    print("[INFO] vspNormalizeTopModule() đã tồn tại trong", path.name)

if "data.top_vulnerable_module" in txt:
    txt = txt.replace("data.top_vulnerable_module",
                      "vspNormalizeTopModule(data.top_vulnerable_module)")
    print("[PATCH] Thay data.top_vulnerable_module -> vspNormalizeTopModule(...) trong", path.name)
else:
    print("[WARN] Không thấy 'data.top_vulnerable_module' trong", path.name)

path.write_text(txt, encoding="utf-8")
PY

done

echo "[DONE] patch_vsp_dashboard_top_module_v1.sh hoàn tất."
