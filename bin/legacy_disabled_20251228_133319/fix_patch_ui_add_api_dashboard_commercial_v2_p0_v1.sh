#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date

F="vsp_demo_app.py"
MARK="VSP_API_DASHBOARD_COMMERCIAL_V2_P0_V1"

[ -f "$F" ] || { echo "[ERR] missing $F"; exit 3; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_fix_${MARK}_${TS}"
echo "[BACKUP] $F.bak_fix_${MARK}_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

MARK = "VSP_API_DASHBOARD_COMMERCIAL_V2_P0_V1"

p = Path("vsp_demo_app.py")
s = p.read_text(encoding="utf-8", errors="replace")

# Ensure jsonify import exists (safe add)
if "jsonify" not in s:
    m = re.search(r"^from\s+flask\s+import\s+(.+)$", s, flags=re.M)
    if m and "jsonify" not in m.group(1):
        line = m.group(0)
        new_line = line.rstrip() + ", jsonify"
        s = s[:m.start()] + new_line + s[m.end():]
    else:
        s = "from flask import jsonify\n" + s

# Remove any previous/incomplete block with same marker
s = re.sub(
    r"\n?#\s*===\s*"+re.escape(MARK)+r"\s*===.*?#\s*===\s*/"+re.escape(MARK)+r"\s*===\s*\n?",
    "\n",
    s,
    flags=re.S
)

# If endpoint already exists, stop (after cleanup)
if "/api/vsp/dashboard_commercial_v2" in s:
    print("[OK] endpoint already present (post-cleanup).")
    p.write_text(s, encoding="utf-8")
    raise SystemExit(0)

inj = f"""
# === {MARK} ===
@app.get("/api/vsp/dashboard_commercial_v2")
def vsp_api_dashboard_commercial_v2():
    \"\"\"Commercial dashboard API (v2). Stable model derived from findings_unified.json.\"\"\"
    try:
        from pathlib import Path
        import json
        base = Path(__file__).resolve().parent
        fp = base / "findings_unified.json"

        payload = {{"ok": False, "notes": ["missing findings_unified.json"]}}
        if fp.exists():
            try:
                payload = json.loads(fp.read_text(encoding="utf-8", errors="replace"))
            except Exception as e:
                payload = {{"ok": False, "notes": [f"invalid findings_unified.json: {{e}}"]}}

        counts = payload.get("counts_by_severity") or {{}}
        items  = payload.get("items") or []
        by_tool_sev = payload.get("by_tool_severity") or {{}}

        # total_findings: prefer explicit total; else sum 'count' fields; else sum severity counts
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

        model = {{
            "ok": True,
            "ts": payload.get("generated_at"),
            "run_dir": payload.get("run_dir"),
            "summary_only": summary_only,
            "notes": notes,
            "counts_by_severity": {{
                "CRITICAL": int(counts.get("CRITICAL", 0) or 0),
                "HIGH": int(counts.get("HIGH", 0) or 0),
                "MEDIUM": int(counts.get("MEDIUM", 0) or 0),
                "LOW": int(counts.get("LOW", 0) or 0),
                "INFO": int(counts.get("INFO", 0) or 0),
                "TRACE": int(counts.get("TRACE", 0) or 0),
            }},
            "total_findings": int(total),
            "by_tool_severity": by_tool_sev,
            "items": items,
        }}
        return jsonify(model)
    except Exception as e:
        return jsonify({{"ok": False, "error": str(e)}}), 500
# === /{MARK} ===
""".strip("\n")

# Insert after app = Flask(...) if possible
m = re.search(r"^app\s*=\s*Flask\([^\n]*\)\s*$", s, flags=re.M)
if m:
    insert_at = m.end()
    s = s[:insert_at] + "\n\n" + inj + "\n\n" + s[insert_at:]
else:
    s = inj + "\n\n" + s

p.write_text(s, encoding="utf-8")
print("[OK] injected /api/vsp/dashboard_commercial_v2")
PY

python3 -m py_compile "$F"
echo "[OK] py_compile OK: $F"

echo "[VERIFY]"
echo "  curl -sS 'http://127.0.0.1:8910/api/vsp/dashboard_commercial_v2' | jq .ok,.summary_only,.total_findings -C"
echo "[NEXT] restart UI 8910 then Ctrl+Shift+R (404 should disappear)"
