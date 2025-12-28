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

if "def api_top_risks_v2" in data:
    print("[INFO] app.py đã có api_top_risks_v2, bỏ qua.")
    raise SystemExit(0)

block = '''
@app.route("/api/top_risks_v2", methods=["GET"])
def api_top_risks_v2():
    """
    Trả về buckets CRIT/HIGH/MED/LOW + TOP 10 findings CRITICAL/HIGH.
    """
    import json, os
    from pathlib import Path
    from collections import Counter

    ROOT = Path(__file__).resolve().parent.parent  # /home/test/Data/SECURITY_BUNDLE
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

    # lấy buckets từ summary_unified.json (nếu có)
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

    # tìm findings_unified.json để lấy TOP
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
def api_top_risks_compat():
    """
    Alias cho /api/top_risks_v2 để JS cũ/JS mới dùng chung.
    """
    return api_top_risks_v2()
'''

data = data.rstrip() + "\n\n" + textwrap.dedent(block) + "\n"
path.write_text(data, encoding="utf-8")
print("[OK] Đã append api_top_risks_v2 + alias /api/top_risks vào app.py")
PY
