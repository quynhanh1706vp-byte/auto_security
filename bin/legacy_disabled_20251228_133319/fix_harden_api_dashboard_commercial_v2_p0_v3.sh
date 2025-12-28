#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date

F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 3; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_fix_harden_dashv2_${TS}"
echo "[BACKUP] $F.bak_fix_harden_dashv2_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("vsp_demo_app.py")
s = p.read_text(encoding="utf-8", errors="replace")

# Ensure Response import exists
if "Response" not in s:
    m = re.search(r"^from\s+flask\s+import\s+(.+)$", s, flags=re.M)
    if m and "Response" not in m.group(1):
        line = m.group(0)
        s = s[:m.start()] + line.rstrip() + ", Response" + s[m.end():]
    else:
        s = "from flask import Response\n" + s

# Find and replace the whole route block for /api/vsp/dashboard_commercial_v2
pat = r'(^@app\.(?:get|route)\(\s*["\']/api/vsp/dashboard_commercial_v2["\'].*?\)\s*\n(?:^@.*\n)*)^def\s+\w+\s*\(\s*\)\s*:\s*\n(?:^[ \t].*\n)*'
m = re.search(pat, s, flags=re.M)
if not m:
    # fallback: find decorator line and replace until next top-level @app.* or end
    m2 = re.search(r'^@app\.(?:get|route)\(\s*["\']/api/vsp/dashboard_commercial_v2["\'].*\)\s*$', s, flags=re.M)
    if not m2:
        raise SystemExit("[ERR] cannot find route decorator for /api/vsp/dashboard_commercial_v2 in vsp_demo_app.py")
    start = m2.start()
    tail = s[m2.end():]
    m3 = re.search(r'^\s*@app\.', tail, flags=re.M)
    end = m2.end() + (m3.start() if m3 else len(tail))
    old = s[start:end]
else:
    start, end = m.start(), m.end()
    old = s[start:end]

harden = """
@app.get("/api/vsp/dashboard_commercial_v2")
def vsp_api_dashboard_commercial_v2():
    \"\"\"Commercial dashboard API (v2) - hardened.
    Always returns stable JSON model derived from findings_unified.json.
    \"\"\"
    from pathlib import Path
    import json, traceback

    base = Path(__file__).resolve().parent
    fp = base / "findings_unified.json"

    payload = {"ok": False, "notes": ["missing findings_unified.json"], "counts_by_severity": {}, "items": [], "findings": []}
    if fp.exists():
        try:
            payload = json.loads(fp.read_text(encoding="utf-8", errors="replace"))
        except Exception as e:
            payload = {"ok": False, "notes": [f"invalid findings_unified.json: {e}"], "counts_by_severity": {}, "items": [], "findings": []}

    try:
        counts = payload.get("counts_by_severity") or {}
        items  = payload.get("items") or []
        by_tool_sev = payload.get("by_tool_severity") or {}

        total = payload.get("total")
        if not isinstance(total, int):
            total = 0
            for it in items:
                c = it.get("count")
                if isinstance(c, int):
                    total += c
            if total == 0:
                total = sum(int(counts.get(k,0) or 0) for k in ["CRITICAL","HIGH","MEDIUM","LOW","INFO","TRACE"])

        notes = payload.get("notes") or []
        summary_only = False
        if isinstance(notes, list) and any("placeholder generated" in str(x).lower() for x in notes):
            summary_only = True
        if (payload.get("findings") == []) and (len(items) > 0):
            summary_only = True

        model = {
            "ok": True,
            "ts": payload.get("generated_at"),
            "run_dir": payload.get("run_dir"),
            "summary_only": summary_only,
            "notes": notes,
            "counts_by_severity": {
                "CRITICAL": int(counts.get("CRITICAL", 0) or 0),
                "HIGH": int(counts.get("HIGH", 0) or 0),
                "MEDIUM": int(counts.get("MEDIUM", 0) or 0),
                "LOW": int(counts.get("LOW", 0) or 0),
                "INFO": int(counts.get("INFO", 0) or 0),
                "TRACE": int(counts.get("TRACE", 0) or 0),
            },
            "total_findings": int(total),
            "by_tool_severity": by_tool_sev,
            "items": items,
        }
        return Response(json.dumps(model, ensure_ascii=False), mimetype="application/json")
    except Exception as e:
        tb = traceback.format_exc().splitlines()[-10:]
        model = {"ok": False, "error": str(e), "trace_tail": tb}
        return Response(json.dumps(model, ensure_ascii=False), mimetype="application/json"), 500
""".lstrip()

s2 = s[:start] + harden + s[end:]
p.write_text(s2, encoding="utf-8")
print("[OK] replaced route block for /api/vsp/dashboard_commercial_v2")
PY

python3 -m py_compile "$F"
echo "[OK] py_compile OK: $F"
echo "[NEXT] restart UI 8910 then verify:"
echo "  curl -sS 'http://127.0.0.1:8910/api/vsp/dashboard_commercial_v2' | jq .ok,.summary_only,.total_findings -C"
