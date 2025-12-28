#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date

F="vsp_demo_app.py"
MARK="VSP_SERVE_FINDINGS_UNIFIED_P0_V1"

[ -f "$F" ] || { echo "[ERR] missing $F"; exit 3; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_fix_${MARK}_${TS}"
echo "[BACKUP] $F.bak_fix_${MARK}_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("vsp_demo_app.py")
s = p.read_text(encoding="utf-8", errors="replace")

# 1) Ensure send_file import exists (safe add)
if "send_file" not in s:
    m = re.search(r"^from\s+flask\s+import\s+(.+)$", s, flags=re.M)
    if m and "send_file" not in m.group(1):
        # append into first flask import line
        line = m.group(0)
        new_line = line.rstrip() + ", send_file"
        s = s[:m.start()] + new_line + s[m.end():]
    else:
        # add separate import near top
        s = "from flask import send_file\n" + s

# 2) Remove any previous incomplete blocks with same marker (if any)
s = re.sub(
    r"\n?#\s*===\s*VSP_SERVE_FINDINGS_UNIFIED_P0_V1\s*===.*?#\s*===\s*/VSP_SERVE_FINDINGS_UNIFIED_P0_V1\s*===\s*\n?",
    "\n",
    s,
    flags=re.S
)

# 3) If already patched cleanly, stop
if "def vsp_findings_unified_json" in s and "/findings_unified.json" in s:
    print("[OK] route already present (def vsp_findings_unified_json).")
    p.write_text(s, encoding="utf-8")
    raise SystemExit(0)

inj = """
# === VSP_SERVE_FINDINGS_UNIFIED_P0_V1 ===
@app.get("/findings_unified.json")
def vsp_findings_unified_json():
    \"\"\"Serve unified findings in same-origin mode for UI widgets.\"\"\"
    try:
        from pathlib import Path
        base = Path(__file__).resolve().parent
        fp = base / "findings_unified.json"
        if not fp.exists():
            return (
                "{\\"ok\\":false,\\"error\\":\\"missing findings_unified.json\\"}",
                404,
                {"Content-Type": "application/json"},
            )
        return send_file(str(fp), mimetype="application/json", as_attachment=False)
    except Exception as e:
        msg = str(e).replace('"', '\\\\\"')
        return (
            "{\\"ok\\":false,\\"error\\":\\"%s\\"}" % msg,
            500,
            {"Content-Type": "application/json"},
        )
# === /VSP_SERVE_FINDINGS_UNIFIED_P0_V1 ===
""".strip("\n")

# 4) Insert after app = Flask(...) if possible, else append near top
m = re.search(r"^app\s*=\s*Flask\([^\n]*\)\s*$", s, flags=re.M)
if m:
    insert_at = m.end()
    s = s[:insert_at] + "\n\n" + inj + "\n\n" + s[insert_at:]
else:
    # fallback: after first occurrence of "app =" or at beginning
    m2 = re.search(r"^app\s*=", s, flags=re.M)
    if m2:
        s = s[:m2.start()] + inj + "\n\n" + s[m2.start():]
    else:
        s = inj + "\n\n" + s

p.write_text(s, encoding="utf-8")
print("[OK] injected /findings_unified.json route")
PY

python3 -m py_compile "$F"
echo "[OK] py_compile OK: $F"

echo "[NEXT] restart UI 8910 then verify:"
echo "  curl -sS http://127.0.0.1:8910/findings_unified.json | jq .ok,.notes -C"
