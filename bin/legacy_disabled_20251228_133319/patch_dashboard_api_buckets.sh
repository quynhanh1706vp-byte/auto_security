#!/usr/bin/env bash
set -euo pipefail

APP="app.py"
echo "[i] APP = $APP"

if [ ! -f "$APP" ]; then
  echo "[ERR] Không tìm thấy $APP"
  exit 1
fi

python3 - "$APP" <<'PY'
from pathlib import Path

path = Path("app.py")
data = path.read_text(encoding="utf-8")
lines = data.splitlines(keepends=True)

out = []
i = 0
removed_dd = 0
removed_tr = 0

while i < len(lines):
    line = lines[i]

    # Xoá toàn bộ hàm api_dashboard_data cũ + decorator ngay trước nó
    if 'def api_dashboard_data' in line:
        removed_dd += 1
        if out and '"/api/dashboard_data"' in out[-1]:
            out.pop()
        i += 1
        while i < len(lines):
            l2 = lines[i]
            if l2.strip() == "" or l2.startswith((" ", "\t")):
                i += 1
                continue
            break
        continue

    # Xoá toàn bộ hàm api_top_risks cũ + decorator ngay trước nó
    if 'def api_top_risks' in line:
        removed_tr += 1
        if out and '"/api/top_risks"' in out[-1]:
            out.pop()
        i += 1
        while i < len(lines):
            l2 = lines[i]
            if l2.strip() == "" or l2.startswith((" ", "\t")):
                i += 1
                continue
            break
        continue

    out.append(line)
    i += 1

print("[INFO] removed api_dashboard_data:", removed_dd, "api_top_risks:", removed_tr)

cleaned = "".join(out).rstrip() + "\n\n"

block = r'''@app.route("/api/dashboard_data", methods=["GET"])
def api_dashboard_data():
    """
    JSON phẳng cho Dashboard – lấy từ summary_unified.json của RUN_* mới nhất.
    """
    import json, os
    from pathlib import Path

    ROOT = Path(__file__).resolve().parent.parent
    out_dir = ROOT / "out"

    default = {
        "run": None,
        "total": 0,
        "critical": 0,
        "high": 0,
        "medium": 0,
        "low": 0,
        "info": 0,
        "buckets": {
            "CRITICAL": 0,
            "HIGH": 0,
            "MEDIUM": 0,
            "LOW": 0,
            "INFO": 0,
        },
    }

    if not out_dir.is_dir():
        return default

    latest_run = None
    for name in sorted(os.listdir(out_dir)):
        if name.startswith("RUN_2"):  # chỉ lấy RUN_YYYYmmdd_...
            latest_run = name

    if not latest_run:
        return default

    summary_path = out_dir / latest_run / "report" / "summary_unified.json"
    if not summary_path.is_file():
        return default

    try:
        with summary_path.open("r", encoding="utf-8") as f:
            summary = json.load(f)
    except Exception:
        return default

    def get_any(d, *keys, default=0):
        for k in keys:
            if k in d and d[k] is not None:
                return d[k]
        return default

    crit = get_any(summary, "critical", "crit", "C")
    high = get_any(summary, "high", "H")
    med  = get_any(summary, "medium", "M")
    low  = get_any(summary, "low", "L")
    info = get_any(summary, "info", "I")

    total = summary.get("total")
    if total is None:
        try:
            total = int(crit + high + med + low + info)
        except Exception:
            total = 0

    resp = {
        "run": latest_run,
        "total": total,
        "critical": crit,
        "high": high,
        "medium": med,
        "low": low,
        "info": info,
        "buckets": {
            "CRITICAL": crit,
            "HIGH": high,
            "MEDIUM": med,
            "LOW": low,
            "INFO": info,
        },
    }
    return resp


@app.route("/api/top_risks", methods=["GET"])
def api_top_risks():
    """
    Trả về top 10 findings CRITICAL/HIGH + bucket.
    Ưu tiên dùng findings_unified.json; nếu không có thì chỉ trả bucket từ summary_unified.
    """
    import json, os
    from pathlib import Path
    from collections import Counter

    ROOT = Path(__file__).resolve().parent.parent
    out_dir = ROOT / "out"

    result = {
        "run": None,
        "total": 0,
        "buckets": {},
        "top_risks": [],
    }

    if not out_dir.is_dir():
        return result

    latest_run = None
    for name in sorted(os.listdir(out_dir)):
        if name.startswith("RUN_2"):
            latest_run = name

    if not latest_run:
        return result

    run_dir = out_dir / latest_run
    report_dir = run_dir / "report"
    candidates = [
        report_dir / "findings_unified.json",
        run_dir / "findings_unified.json",
    ]

    result["run"] = latest_run

    findings_path = None
    for c in candidates:
        if c.is_file():
            findings_path = c
            break

    # Nếu không có findings_unified => chỉ trả bucket từ summary_unified để chart dùng được
    summary_path = report_dir / "summary_unified.json"
    if findings_path is None:
        if summary_path.is_file():
            try:
                with summary_path.open("r", encoding="utf-8") as f:
                    s = json.load(f)
            except Exception:
                return result

            def get_any(d, *keys, default=0):
                for k in keys:
                    if k in d and d[k] is not None:
                        return d[k]
                return default

            crit = get_any(s, "critical", "crit", "C")
            high = get_any(s, "high", "H")
            med  = get_any(s, "medium", "M")
            low  = get_any(s, "low", "L")
            info = get_any(s, "info", "I")

            result["buckets"] = {
                "CRITICAL": crit,
                "HIGH": high,
                "MEDIUM": med,
                "LOW": low,
                "INFO": info,
            }
            result["total"] = crit + high + med + low + info
        return result

    try:
        with findings_path.open("r", encoding="utf-8") as f:
            data = json.load(f)
    except Exception:
        return result

    if isinstance(data, dict) and "findings" in data:
        findings = data["findings"]
    elif isinstance(data, list):
        findings = data
    else:
        return result

    def norm_sev(raw):
        if not raw:
            return "INFO"
        s = str(raw).upper()
        if s.startswith("CRIT"):
            return "CRITICAL"
        if s.startswith("HI"):
            return "HIGH"
        if s.startswith("MED"):
            return "MEDIUM"
        if s.startswith("LO"):
            return "LOW"
        if s.startswith("INFO") or s.startswith("INFORMATIONAL"):
            return "INFO"
        return "INFO"

    sev_counter = Counter()
    total = 0
    top_candidates = []

    for f in findings:
        sev = (
            f.get("severity")
            or f.get("sev")
            or f.get("severity_norm")
            or f.get("severity_normalized")
            or f.get("level")
            or "INFO"
        )
        s = norm_sev(sev)
        sev_counter[s] += 1
        total += 1

        if s in ("CRITICAL", "HIGH"):
            tool = f.get("tool") or f.get("source") or f.get("engine") or "?"
            rule = f.get("rule_id") or f.get("id") or f.get("check_id") or "?"
            location = (
                f.get("location")
                or f.get("path")
                or f.get("file")
                or ""
            )
            line = f.get("line") or f.get("start_line") or None
            if line:
                location = f"{location}:{line}" if location else str(line)

            top_candidates.append({
                "severity": s,
                "tool": tool,
                "rule": rule,
                "location": location,
            })

    for k in ["CRITICAL", "HIGH", "MEDIUM", "LOW", "INFO"]:
        sev_counter.setdefault(k, 0)

    result["total"] = total
    result["buckets"] = dict(sev_counter)

    weight = {"CRITICAL": 2, "HIGH": 1}
    top_candidates.sort(
        key=lambda x: (weight.get(x["severity"], 0), x.get("tool") or ""),
        reverse=True,
    )
    result["top_risks"] = top_candidates[:10]

    return result
'''

cleaned = cleaned + block + "\n"
path.write_text(cleaned, encoding="utf-8")
print("[OK] patched app.py with new /api/dashboard_data and /api/top_risks")
PY
