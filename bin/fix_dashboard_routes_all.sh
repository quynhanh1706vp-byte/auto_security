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
import textwrap

path = Path("app.py")
data = path.read_text(encoding="utf-8")
lines = data.splitlines(keepends=True)

out = []
i = 0
removed = 0

while i < len(lines):
    line = lines[i]

    # Nếu gặp hàm api_dashboard_data / api_top_risks / api_top_risks_v2 thì xoá cả hàm + decorator ngay trước nó
    if ("def api_dashboard_data" in line or
        "def api_top_risks_v2" in line or
        "def api_top_risks_compat" in line or
        "def api_top_risks(" in line):

        removed += 1
        # xoá decorator nếu nằm ngay trước
        if out and ('"/api/dashboard_data"' in out[-1]
                    or '"/api/top_risks_v2"' in out[-1]
                    or '"/api/top_risks"' in out[-1]):
            out.pop()

        # bỏ qua thân hàm
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

print(f"[INFO] Đã xoá {removed} block route cũ (nếu có).")

cleaned = "".join(out)

block = '''
@app.route("/api/dashboard_data", methods=["GET"])
def api_dashboard_data():
    # Trả JSON phẳng cho Dashboard từ summary_unified.json của RUN_* mới nhất
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
        if name.startswith("RUN_2"):
            latest_run = name

    if not latest_run:
        return default

    summary_path = out_dir / latest_run / "report" / "summary_unified.json"
    if not summary_path.is_file():
        return default

    try:
        with summary_path.open("r", encoding="utf-8") as f:
            s = json.load(f)
    except Exception:
        return default

    def g(d, *keys, default=0):
        for k in keys:
            if k in d and d[k] is not None:
                return d[k]
        return default

    crit = g(s, "critical", "crit", "C")
    high = g(s, "high", "H")
    med  = g(s, "medium", "M")
    low  = g(s, "low", "L")
    info = g(s, "info", "I")

    total = s.get("total")
    if total is None:
        total = crit + high + med + low + info

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


@app.route("/api/top_risks_v2", methods=["GET"])
def api_top_risks_v2():
    # Buckets + top 10 CRITICAL/HIGH từ findings_unified.json (nếu có)
    import json, os
    from collections import Counter
    from pathlib import Path

    ROOT = Path(__file__).resolve().parent.parent
    out_dir = ROOT / "out"

    result = {
        "run": None,
        "total": 0,
        "buckets": {
            "CRITICAL": 0,
            "HIGH": 0,
            "MEDIUM": 0,
            "LOW": 0,
            "INFO": 0,
        },
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
    result["run"] = latest_run

    summary_path = report_dir / "summary_unified.json"

    if summary_path.is_file():
        try:
            with summary_path.open("r", encoding="utf-8") as f:
                s = json.load(f)
        except Exception:
            s = {}
        def g(d, *keys, default=0):
            for k in keys:
                if k in d and d[k] is not None:
                    return d[k]
            return default
        crit = g(s, "critical", "crit", "C")
        high = g(s, "high", "H")
        med  = g(s, "medium", "M")
        low  = g(s, "low", "L")
        info = g(s, "info", "I")
        result["buckets"] = {
            "CRITICAL": crit,
            "HIGH": high,
            "MEDIUM": med,
            "LOW": low,
            "INFO": info,
        }
        result["total"] = crit + high + med + low + info

    # tìm findings_unified.json
    candidates = [
        report_dir / "findings_unified.json",
        run_dir / "findings_unified.json",
    ]
    findings_path = None
    for c in candidates:
        if c.is_file():
            findings_path = c
            break

    if not findings_path:
        return result

    try:
        with findings_path.open("r", encoding="utf-8") as f:
            d = json.load(f)
    except Exception:
        return result

    if isinstance(d, dict) and "findings" in d:
        findings = d["findings"]
    elif isinstance(d, list):
        findings = d
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

    sev_counter = Counter(result["buckets"])
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

    result["buckets"] = dict(sev_counter)
    result["total"] = sum(sev_counter.values())

    weight = {"CRITICAL": 2, "HIGH": 1}
    top_candidates.sort(
        key=lambda x: (weight.get(x["severity"], 0), x.get("tool") or ""),
        reverse=True,
    )
    result["top_risks"] = top_candidates[:10]

    return result


@app.route("/api/top_risks", methods=["GET"])
def api_top_risks():
    # Alias cho /api/top_risks_v2
    return api_top_risks_v2()
'''

block = textwrap.dedent(block)

marker = 'if __name__ == "__main__":'
if marker in cleaned:
    new_data = cleaned.replace(marker, block + "\n\n" + marker, 1)
else:
    new_data = cleaned.rstrip() + "\n\n" + block + "\n"

path.write_text(new_data, encoding="utf-8")
print("[OK] Đã ghi lại app.py với /api/dashboard_data + /api/top_risks_v2 + /api/top_risks.")
PY
