#!/usr/bin/env bash
set -euo pipefail

APP="app.py"
echo "[i] APP = $APP"

if [ ! -f "$APP" ]; then
  echo "[ERR] Không tìm thấy $APP"
  exit 1
fi

python3 - "$APP" <<'PY'
import sys, pathlib

path = pathlib.Path(sys.argv[1])
code = path.read_text(encoding="utf-8")

start = code.find("def _sb_extract_counts_from_summary_dict(")
if start == -1:
    print("[ERR] Không tìm thấy def _sb_extract_counts_from_summary_dict trong app.py")
    sys.exit(1)

end = code.find("def _sb_extract_counts_from_findings_list(", start)
if end == -1:
    print("[ERR] Không tìm thấy def _sb_extract_counts_from_findings_list sau đó.")
    sys.exit(1)

before = code[:start]
after = code[end:]

new_func = '''def _sb_extract_counts_from_summary_dict(data):
    """
    Rút trích (total, CRIT, HIGH, MED, LOW) từ một dict summary.

    Hỗ trợ nhiều dạng:
    - {"total":..., "by_severity": {...}}
    - {"summary_all": {"total_findings":..., "severity_buckets": {...}}}
    - severity_buckets có thể là:
        * dict: {"CRITICAL": 0, "HIGH": 10, ...}
        * list: [{"severity": "HIGH", "count": 10}, ...]
    """
    total = 0
    crit = high = medium = low = 0

    # Có thể là { "summary_all": {...} }
    if isinstance(data, dict) and "summary_all" in data and isinstance(data["summary_all"], dict):
        data = data["summary_all"]

    if not isinstance(data, dict):
        return total, crit, high, medium, low

    total = (
        data.get("total")
        or data.get("total_findings")
        or data.get("findings_total")
        or 0
    )

    sev = (
        data.get("by_severity")
        or data.get("severity_buckets")
        or data.get("severity")
        or {}
    ) or {}

    # Nếu sev là list (vd: [{"severity":"HIGH","count":10}, ...]) thì convert thành dict
    if not isinstance(sev, dict):
        if isinstance(sev, list):
            tmp = {}
            for item in sev:
                if not isinstance(item, dict):
                    continue
                key = (
                    item.get("severity")
                    or item.get("sev")
                    or item.get("name")
                    or ""
                )
                key = str(key).upper()
                if not key:
                    continue
                val = (
                    item.get("count")
                    or item.get("value")
                    or item.get("total")
                    or 0
                )
                try:
                    val = int(val or 0)
                except Exception:
                    val = 0
                tmp[key] = tmp.get(key, 0) + val
            sev = tmp
        else:
            sev = {}

    # Chuẩn hoá key upper
    sev_up = {}
    for k, v in sev.items():
        try:
            kk = str(k).upper()
            vv = int(v or 0)
        except Exception:
            continue
        sev_up[kk] = sev_up.get(kk, 0) + vv

    crit = sev_up.get("CRITICAL", 0)
    high = sev_up.get("HIGH", 0)
    medium = sev_up.get("MEDIUM", 0)
    low = (
        sev_up.get("LOW", 0)
        + sev_up.get("INFO", 0)
        + sev_up.get("UNKNOWN", 0)
    )

    return int(total or 0), crit, high, medium, low


'''

code_new = before + new_func + after
path.write_text(code_new, encoding="utf-8")
print("[OK] Đã patch _sb_extract_counts_from_summary_dict để handle severity dạng list.")
PY
