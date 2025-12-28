#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date

F="vsp_demo_app.py"
MARK="VSP_DASHV2_HARDEN_ALT_P0_V1"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 3; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_fix_${MARK}_${TS}"
echo "[BACKUP] $F.bak_fix_${MARK}_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

MARK = "VSP_DASHV2_HARDEN_ALT_P0_V1"

p=Path("vsp_demo_app.py")
s=p.read_text(encoding="utf-8", errors="replace")

if MARK in s:
    print("[OK] already patched:", MARK)
    raise SystemExit(0)

# ensure Response import
if "Response" not in s:
    m=re.search(r"^from\s+flask\s+import\s+(.+)$", s, flags=re.M)
    if m and "Response" not in m.group(1):
        line=m.group(0)
        s=s[:m.start()]+line.rstrip()+", Response"+s[m.end():]
    else:
        s="from flask import Response\n"+s

inj=f"""
# === {MARK} ===
@app.get("/api/vsp/dashboard_commercial_v2_harden")
def vsp_api_dashboard_commercial_v2_harden():
    from pathlib import Path
    import json
    base = Path(__file__).resolve().parent
    fp = base / "findings_unified.json"
    payload = {{"ok": False, "notes": ["missing findings_unified.json"], "counts_by_severity": {{}}, "items": [], "findings": []}}
    if fp.exists():
        try:
            payload = json.loads(fp.read_text(encoding="utf-8", errors="replace"))
        except Exception as e:
            payload = {{"ok": False, "notes": [f"invalid findings_unified.json: {{e}}"], "counts_by_severity": {{}}, "items": [], "findings": []}}
    out = {{
        "ok": True,
        "who": "{MARK}",
        "run_dir": payload.get("run_dir"),
        "summary_only": (payload.get("findings")==[] and len(payload.get("items") or [])>0),
        "counts_by_severity": payload.get("counts_by_severity") or {{}},
        "items_len": len(payload.get("items") or []),
    }}
    return Response(json.dumps(out, ensure_ascii=False), mimetype="application/json")
# === /{MARK} ===
""".strip("\\n")

# insert after app = Flask(...) if possible
m=re.search(r"^app\\s*=\\s*Flask\\([^\\n]*\\)\\s*$", s, flags=re.M)
if m:
    s = s[:m.end()] + "\\n\\n" + inj + "\\n\\n" + s[m.end():]
else:
    s = inj + "\\n\\n" + s

p.write_text(s, encoding="utf-8")
print("[OK] injected alt endpoint /api/vsp/dashboard_commercial_v2_harden")
PY

python3 -m py_compile "$F"
echo "[OK] py_compile OK: $F"
echo "[NEXT] HARD restart 8910 then verify:"
echo "  curl -sS 'http://127.0.0.1:8910/api/vsp/dashboard_commercial_v2_harden' | jq . -C"
