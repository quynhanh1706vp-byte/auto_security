#!/usr/bin/env bash
set -euo pipefail

BIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UI_ROOT="$(cd "$BIN_DIR/.." && pwd)"
TPL="$UI_ROOT/templates/vsp_dashboard_2025.html"

if [ ! -f "$TPL" ]; then
  echo "[ERR] Không tìm thấy $TPL"
  exit 1
fi

backup="$TPL.bak_kpi_ids_$(date +%Y%m%d_%H%M%S)"
cp "$TPL" "$backup"
echo "[BACKUP] $TPL -> $backup"

python - << 'PY'
import re, pathlib

path = pathlib.Path("templates/vsp_dashboard_2025.html")
txt = path.read_text(encoding="utf-8")

def patch_card(label, anchor, span_id):
    global txt
    start = txt.find(label)
    if start == -1:
        print(f"[WARN] Không thấy label '{label}'")
        return
    end = txt.find(anchor, start)
    if end == -1:
        print(f"[WARN] Không thấy anchor '{anchor}' sau '{label}'")
        return
    segment = txt[start:end]
    new_segment, n = re.subn(
        r'>(\s*-\s*)<',
        lambda m: f'><span id="{span_id}">{m.group(1).strip() or "-"}</span><',
        segment,
        count=1,
    )
    if n == 0:
        print(f"[WARN] Không thấy giá trị '-' để patch cho '{label}'")
        return
    print(f"[OK] Patched {label} -> id={span_id}")
    txt = txt[:start] + new_segment + txt[end:]

# 6 severity buckets + 4 advanced KPI
patch_card("TOTAL FINDINGS", "Last run", "vsp-kpi-total-findings")
patch_card("CRITICAL", "Δ vs prev", "vsp-kpi-critical")
patch_card("HIGH", "Δ vs prev", "vsp-kpi-high")
patch_card("MEDIUM", "Δ vs prev", "vsp-kpi-medium")
patch_card("LOW", "Δ vs prev", "vsp-kpi-low")

patch_card("INFO + TRACE", "Noise surface", "vsp-kpi-info-trace")
patch_card("SECURITY POSTURE SCORE", "Weighted by", "vsp-kpi-score")
patch_card("TOP RISKY TOOL", "Most CRITICAL/HIGH", "vsp-kpi-top-tool")
patch_card("TOP IMPACTED CWE", "Most frequent CWE", "vsp-kpi-top-cwe")
patch_card("TOP VULNERABLE MODULE", "CVE-heavy dependency", "vsp-kpi-top-module")

path.write_text(txt, encoding="utf-8")
PY

echo "[DONE] patch_vsp_dashboard_kpi_ids_v1.sh hoàn tất."
