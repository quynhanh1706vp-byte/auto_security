#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date
F="vsp_demo_app.py"
MARK="VSP_LANDING_ALIAS_COMMERCIAL_P0_V1"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 3; }
TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_${MARK}_${TS}"
echo "[BACKUP] $F.bak_${MARK}_${TS}"

python3 - <<'PY'
from pathlib import Path
import re
MARK="VSP_LANDING_ALIAS_COMMERCIAL_P0_V1"
p=Path("vsp_demo_app.py")
s=p.read_text(encoding="utf-8", errors="replace")
if MARK in s:
    print("[OK] already patched:", MARK); raise SystemExit(0)

# ensure imports
def ensure(name):
    nonlocal_s = None
m = re.search(r"^from\s+flask\s+import\s+([^\n]+)$", s, flags=re.M)
if m:
    items=[x.strip() for x in m.group(1).split(",")]
    need=["redirect","url_for","render_template"]
    changed=False
    for x in need:
        if x not in items:
            items.append(x); changed=True
    if changed:
        s = s[:m.start()] + "from flask import " + ", ".join(items) + s[m.end():]
        print("[OK] extended flask import with redirect/url_for/render_template")
else:
    s = "from flask import redirect, url_for, render_template\n" + s
    print("[OK] inserted flask import redirect/url_for/render_template at top")

inject = f"""
# === {MARK} ===
@app.get("/")
def vsp_landing():
    return redirect(url_for("vsp4"))

@app.get("/dashboard")
def vsp_dashboard_alias():
    return redirect(url_for("vsp4"))

@app.get("/vsp5")
def vsp5():
    # enterprise 5-tabs view
    return render_template("vsp_5tabs_enterprise_v2.html")
# === /{MARK} ===
""".strip()

# insert after app = Flask(...) block
lines=s.splitlines(True)
idx=None
for i,ln in enumerate(lines):
    if re.match(r"^\s*app\s*=\s*Flask\s*\(", ln):
        idx=i; break
if idx is None:
    lines.insert(0, inject+"\n\n")
else:
    bal = lines[idx].count("(")-lines[idx].count(")")
    j=idx+1
    while j < len(lines) and bal>0:
        bal += lines[j].count("(")-lines[j].count(")")
        j += 1
    lines.insert(j, "\n\n"+inject+"\n\n")

p.write_text("".join(lines), encoding="utf-8")
print("[OK] injected landing + aliases")
PY

python3 -m py_compile "$F"
echo "[OK] py_compile OK: $F"
echo "[NEXT] restart 8910 then verify:"
echo "  curl -sS -I http://127.0.0.1:8910/ | head"
echo "  curl -sS http://127.0.0.1:8910/vsp5 | head -n 3"
