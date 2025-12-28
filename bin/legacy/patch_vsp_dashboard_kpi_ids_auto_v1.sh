#!/usr/bin/env bash
set -euo pipefail

echo "[INFO] Tự tìm template Dashboard trong thư mục templates/ ..."

python - << 'PY'
import pathlib, re, sys, datetime

tpl_root = pathlib.Path("templates")
if not tpl_root.is_dir():
    print("[ERR] Không thấy thư mục templates/ trong UI root")
    sys.exit(1)

candidates = list(tpl_root.glob("*.html"))
if not candidates:
    print("[ERR] Không tìm thấy file .html nào trong templates/")
    sys.exit(1)

target = None
for p in candidates:
    txt = p.read_text(encoding="utf-8", errors="ignore")
    if "KPI ZONE" in txt and "10 KEY METRICS" in txt and "TOTAL FINDINGS" in txt:
        target = p
        break

if target is None:
    # Fallback: kiếm file có "TAB 1 – DASHBOARD" + "TOTAL FINDINGS"
    for p in candidates:
        txt = p.read_text(encoding="utf-8", errors="ignore")
        if "TAB 1" in txt and "DASHBOARD" in txt and "TOTAL FINDINGS" in txt:
            target = p
            break

if target is None:
    print("[ERR] Không tìm thấy template Dashboard (không có KPI ZONE / TAB 1 / TOTAL FINDINGS)")
    sys.exit(1)

txt = target.read_text(encoding="utf-8", errors="ignore")
print(f"[INFO] Dùng template: {target}")

def patch_card(label, anchor, span_id):
    global txt
    start = txt.find(label)
    if start == -1:
        print(f"[WARN] Không thấy label '{label}' – bỏ qua")
        return
    end = txt.find(anchor, start)
    if end == -1:
        print(f"[WARN] Không thấy anchor '{anchor}' sau '{label}' – bỏ qua")
        return
    segment = txt[start:end]

    # Chỉ chèn span nếu đoạn giữa label và anchor còn chứa dấu '-' độc lập
    new_segment, n = re.subn(
        r'>(\s*-\s*)<',
        lambda m: f'><span id="{span_id}">{m.group(1).strip() or "-"}</span><',
        segment,
        count=1,
    )
    if n == 0:
        print(f"[WARN] Không tìm thấy giá trị '-' để patch cho '{label}' – có thể đã patch trước đó")
        return

    txt_before = txt[:start]
    txt_after = txt[end:]
    txt_new = txt_before + new_segment + txt_after
    txt = txt_new
    print(f"[OK] Patched {label} -> id={span_id}")

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

# Ghi lại + backup
ts = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
backup = target.with_suffix(target.suffix + f".bak_kpi_ids_{ts}")
backup.write_text(target.read_text(encoding="utf-8", errors="ignore"), encoding="utf-8")
target.write_text(txt, encoding="utf-8")

print(f"[BACKUP] {backup}")
print("[DONE] KPI IDs patched.")
PY
