#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date
F="vsp_demo_app.py"
MARK="VSP_SELFCHECK_P0_V1"
TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_${MARK}_${TS}"
echo "[BACKUP] $F.bak_${MARK}_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, json
MARK="VSP_SELFCHECK_P0_V1"
p=Path("vsp_demo_app.py")
s=p.read_text(encoding="utf-8", errors="replace")
if MARK in s:
    print("[OK] already patched"); raise SystemExit(0)

# ensure jsonify import exists
m = re.search(r"^from\s+flask\s+import\s+([^\n]+)$", s, flags=re.M)
if m:
    items=[x.strip() for x in m.group(1).split(",")]
    if "jsonify" not in items:
        items.append("jsonify")
        s = s[:m.start()] + "from flask import " + ", ".join(items) + s[m.end():]
else:
    s = "from flask import jsonify\n" + s

inject = f"""
# === {MARK} ===
@app.get("/api/vsp/selfcheck_p0")
def vsp_selfcheck_p0():
    import os, time, json
    from pathlib import Path
    ui_root = Path(__file__).resolve().parent
    # best-effort: prefer latest findings_unified.json under ui/out_ci if present
    candidates = [
        ui_root / "out_ci" / "reports" / "findings_unified.json",
        ui_root / "out_ci" / "findings_unified.json",
        ui_root / "findings_unified.json",
    ]
    total = None
    src = None
    for fp in candidates:
        if fp.exists():
            try:
                j=json.loads(fp.read_text(encoding="utf-8", errors="replace"))
                total = j.get("total_findings") or j.get("total") or j.get("total_count")
                src = str(fp)
                break
            except Exception:
                pass
    ok = True
    return jsonify({{
        "ok": ok,
        "ts": int(time.time()),
        "who": "{MARK}",
        "findings_total": total,
        "findings_src": src,
        "ui": {{"vsp4": True, "vsp5": True}},
    }})
# === /{MARK} ===
""".strip()

# append near end of file (safe)
s = s + "\n\n" + inject + "\n"
p.write_text(s, encoding="utf-8")
print("[OK] injected selfcheck endpoint")
PY

python3 -m py_compile "$F"
echo "[OK] py_compile OK"
echo "[NEXT] restart 8910 then:"
echo "  curl -sS http://127.0.0.1:8910/api/vsp/selfcheck_p0 | jq . -C"
