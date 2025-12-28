#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date

F="vsp_demo_app.py"
MARK="VSP_VSP4_TEMPLATE_FALLBACK_P0_V1"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 3; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_${MARK}_${TS}"
echo "[BACKUP] $F.bak_${MARK}_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

MARK="VSP_VSP4_TEMPLATE_FALLBACK_P0_V1"
p=Path("vsp_demo_app.py")
s=p.read_text(encoding="utf-8", errors="replace")

if MARK in s:
    print("[OK] already patched:", MARK)
    raise SystemExit(0)

# ensure render_template imported
m = re.search(r"^from\s+flask\s+import\s+([^\n]+)$", s, flags=re.M)
if m:
    items=[x.strip() for x in m.group(1).split(",")]
    if "render_template" not in items:
        items.append("render_template")
        s = s[:m.start()] + "from flask import " + ", ".join(items) + s[m.end():]
else:
    # insert near top if no flask import line exists
    s = "from flask import render_template\n" + s

inject = f"""
# === {MARK} ===
@app.get("/vsp4")
def vsp4():
    \"\"\"P0 fallback: always render vsp_dashboard_2025.html if present.\"\"\"
    from pathlib import Path
    tpl = Path(__file__).resolve().parent / "templates" / "vsp_dashboard_2025.html"
    if tpl.exists():
        return render_template("vsp_dashboard_2025.html")
    # legacy message
    return "VSP4 template not found", 404
# === /{MARK} ===
""".strip("\n")

# insert after app = Flask(...) block (first occurrence)
mapp = re.search(r"^\s*app\s*=\s*Flask\s*\(", s, flags=re.M)
if mapp:
    # find end of that multiline block by paren balance
    lines=s.splitlines(True)
    i0=None
    for i,ln in enumerate(lines):
        if re.match(r"^\s*app\s*=\s*Flask\s*\(", ln):
            i0=i; break
    if i0 is None:
        s = inject + "\n\n" + s
    else:
        bal = lines[i0].count("(")-lines[i0].count(")")
        j=i0+1
        while j < len(lines) and bal>0:
            bal += lines[j].count("(")-lines[j].count(")")
            j += 1
        # insert after j
        lines.insert(j, "\n\n"+inject+"\n\n")
        s="".join(lines)
else:
    s = inject + "\n\n" + s

p.write_text(s, encoding="utf-8")
print("[OK] injected /vsp4 fallback route")
PY

python3 -m py_compile "$F"
echo "[OK] py_compile OK: $F"
echo "[NEXT] restart 8910 then:"
echo "  curl -sS http://127.0.0.1:8910/vsp4 | head -n 3"
