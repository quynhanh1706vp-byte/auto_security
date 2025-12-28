#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date

F="vsp_demo_app.py"
MARK="VSP_DASHV2_HARDEN_ALT_P0_V1"

[ -f "$F" ] || { echo "[ERR] missing $F"; exit 3; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_fix_backslashn_${TS}"
echo "[BACKUP] $F.bak_fix_backslashn_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

F = Path("vsp_demo_app.py")
s = F.read_text(encoding="utf-8", errors="replace")

# (1) sanitize: remove literal "\n" tokens that appear at start of a physical line
#     Example broken line: "    \\n\\nimport shutil"
lines = s.splitlines(True)  # keepends
out = []
changed = 0
for ln in lines:
    # if after leading whitespace we see one or more literal \n tokens -> drop them
    m = re.match(r"^(\s*)(\\n)+", ln)
    if m:
        ln2 = re.sub(r"^(\s*)(\\n)+", r"\1", ln)
        if ln2 != ln:
            changed += 1
            ln = ln2
    out.append(ln)

s2 = "".join(out)

# (2) Also remove stray literal "\n" tokens that were inserted as separators between blocks:
#     Only when they appear as their own "token-y" lines (safe)
s2b = re.sub(r"^\s*\\n\s*$", "", s2, flags=re.M)
if s2b != s2:
    changed += 1
s2 = s2b

# (3) Ensure Response import exists
if "Response" not in s2:
    m = re.search(r"^from\s+flask\s+import\s+(.+)$", s2, flags=re.M)
    if m and "Response" not in m.group(1):
        line = m.group(0)
        s2 = s2[:m.start()] + line.rstrip() + ", Response" + s2[m.end():]
    else:
        s2 = "from flask import Response\n" + s2

# (4) Remove any previous harden-alt block (in case partial)
MARK = "VSP_DASHV2_HARDEN_ALT_P0_V1"
s2 = re.sub(
    r"\n?#\s*===\s*"+re.escape(MARK)+r"\s*===.*?#\s*===\s*/"+re.escape(MARK)+r"\s*===\s*\n?",
    "\n",
    s2,
    flags=re.S
)

# (5) Inject clean endpoint with REAL newlines
inj = f"""
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
""".strip("\n")

m = re.search(r"^app\s*=\s*Flask\([^\n]*\)\s*$", s2, flags=re.M)
if m:
    s2 = s2[:m.end()] + "\n\n" + inj + "\n\n" + s2[m.end():]
else:
    s2 = inj + "\n\n" + s2

F.write_text(s2, encoding="utf-8")
print("[OK] sanitized backslash-n lines:", changed)
print("[OK] injected clean harden endpoint:", MARK)
PY

python3 -m py_compile "$F"
echo "[OK] py_compile OK: $F"

echo "[NEXT] HARD restart 8910 then verify:"
echo "  curl -sS 'http://127.0.0.1:8910/api/vsp/dashboard_commercial_v2_harden' | jq . -C"
