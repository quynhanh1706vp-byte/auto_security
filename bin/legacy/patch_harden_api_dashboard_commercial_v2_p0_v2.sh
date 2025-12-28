#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date

F="vsp_demo_app.py"
MARK="VSP_API_DASHBOARD_COMMERCIAL_V2_P0_V1"

[ -f "$F" ] || { echo "[ERR] missing $F"; exit 3; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_harden_api_v2_${TS}"
echo "[BACKUP] $F.bak_harden_api_v2_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("vsp_demo_app.py")
s = p.read_text(encoding="utf-8", errors="replace")

# Ensure Response import exists (safe add)
if "Response" not in s:
    m = re.search(r"^from\s+flask\s+import\s+(.+)$", s, flags=re.M)
    if m and "Response" not in m.group(1):
        line = m.group(0)
        new_line = line.rstrip() + ", Response"
        s = s[:m.start()] + new_line + s[m.end():]
    else:
        s = "from flask import Response\n" + s

# Replace the whole marked block (v1) with hardened v2
pat = r"#\s*===\s*"+re.escape("VSP_API_DASHBOARD_COMMERCIAL_V2_P0_V1")+r"\s*===.*?#\s*===\s*/"+re.escape("VSP_API_DASHBOARD_COMMERCIAL_V2_P0_V1")+r"\s*==="
m = re.search(pat, s, flags=re.S)
if not m:
    print("[ERR] cannot find marker block to replace:", "VSP_API_DASHBOARD_COMMERCIAL_V2_P0_V1")
    raise SystemExit(4)

harden = """
# === VSP_API_DASHBOARD_COMMERCIAL_V2_P0_V1 ===
@app.get("/api/vsp/dashboard_commercial_v2")
def vsp_api_dashboard_commercial_v2():
    \"\"\"Commercial dashboard API (v2) - hardened.
    - No jsonify dependency
    - Always returns stable model (even if findings_unified.json missing/invalid)
    - Includes short debug trace on error (for P0 bring-up)
    \"\"\"
    from pathlib import Path
    import json, traceback
    base = Path(__file__).resolve().parent
    fp = base / "findings_unified.json"

    payload = {"ok": False, "notes": ["missing findings_unified.json"], "counts_by_severity": {}, "items": [], "findings": []}
    err = None

    if fp.exists():
        try:
            payload = json.loads(fp.read_text(encoding="utf-8", errors="replace"))
        except Exception as e:
            err = f"invalid findings_unified.json: {e}"
            payload = {"ok": False, "notes": [err], "counts_by_severity": {}, "items": [], "findings": []}

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
        tb = traceback.format_exc().splitlines()[-8:]
        model = {"ok": False, "error": str(e), "trace_tail": tb}
        return Response(json.dumps(model, ensure_ascii=False), mimetype="application/json"), 500
# === /VSP_API_DASHBOARD_COMMERCIAL_V2_P0_V1 ===
""".strip("\n")

s = s[:m.start()] + harden + s[m.end():]
p.write_text(s, encoding="utf-8")
print("[OK] replaced dashboard_commercial_v2 with hardened Response-based implementation")
PY

python3 -m py_compile "$F"
echo "[OK] py_compile OK: $F"

echo "[NEXT] restart UI 8910 then verify:"
echo "  curl -sS 'http://127.0.0.1:8910/api/vsp/dashboard_commercial_v2' | jq .ok,.summary_only,.total_findings -C"
