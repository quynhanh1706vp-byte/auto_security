#!/usr/bin/env bash
set -euo pipefail
APP="/home/test/Data/SECURITY_BUNDLE/ui/vsp_demo_app.py"
[ -f "$APP" ] || { echo "[ERR] missing $APP"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$APP" "$APP.bak_rm_gitleaks_overwrite_${TS}"
echo "[BACKUP] $APP.bak_rm_gitleaks_overwrite_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("/home/test/Data/SECURITY_BUNDLE/ui/vsp_demo_app.py")
t = p.read_text(encoding="utf-8", errors="ignore")

TAG = "# === VSP_REMOVE_GITLEAKS_OVERWRITE_V1 ==="
if TAG in t:
    print("[OK] tag exists, skip")
    raise SystemExit(0)

# Replace only obvious "reset to default" assignments (do NOT touch real injections)
rules = [
    # has_gitleaks resets
    (r"(?m)^(?P<ind>\s*)(?P<v>[A-Za-z_]\w*)\[\s*['\"]has_gitleaks['\"]\s*\]\s*=\s*False\s*$",
     r"\g<ind>\g<v>.setdefault('has_gitleaks', False)"),
    (r"(?m)^(?P<ind>\s*)(?P<v>[A-Za-z_]\w*)\[\s*['\"]has_gitleaks['\"]\s*\]\s*=\s*0\s*$",
     r"\g<ind>\g<v>.setdefault('has_gitleaks', False)"),

    # gitleaks_verdict default resets
    (r"(?m)^(?P<ind>\s*)(?P<v>[A-Za-z_]\w*)\[\s*['\"]gitleaks_verdict['\"]\s*\]\s*=\s*None\s*$",
     r"\g<ind>\g<v>.setdefault('gitleaks_verdict', '')"),
    (r"(?m)^(?P<ind>\s*)(?P<v>[A-Za-z_]\w*)\[\s*['\"]gitleaks_verdict['\"]\s*\]\s*=\s*['\"]{0,1}['\"]\s*$",
     r"\g<ind>\g<v>.setdefault('gitleaks_verdict', '')"),

    # gitleaks_total default resets
    (r"(?m)^(?P<ind>\s*)(?P<v>[A-Za-z_]\w*)\[\s*['\"]gitleaks_total['\"]\s*\]\s*=\s*None\s*$",
     r"\g<ind>\g<v>.setdefault('gitleaks_total', 0)"),
    (r"(?m)^(?P<ind>\s*)(?P<v>[A-Za-z_]\w*)\[\s*['\"]gitleaks_total['\"]\s*\]\s*=\s*0\s*$",
     r"\g<ind>\g<v>.setdefault('gitleaks_total', 0)"),

    # gitleaks_counts default resets
    (r"(?m)^(?P<ind>\s*)(?P<v>[A-Za-z_]\w*)\[\s*['\"]gitleaks_counts['\"]\s*\]\s*=\s*None\s*$",
     r"\g<ind>\g<v>.setdefault('gitleaks_counts', {})"),
    (r"(?m)^(?P<ind>\s*)(?P<v>[A-Za-z_]\w*)\[\s*['\"]gitleaks_counts['\"]\s*\]\s*=\s*\{\s*\}\s*$",
     r"\g<ind>\g<v>.setdefault('gitleaks_counts', {})"),
]

before = t
for pat, rep in rules:
    t = re.sub(pat, rep, t)

if t == before:
    # still add tag marker to avoid re-running loops blindly
    t = t + "\n\n" + TAG + "\n"
    p.write_text(t, encoding="utf-8")
    print("[WARN] no overwrite patterns found; tag appended only")
    raise SystemExit(0)

# Add tag near end
t = t + "\n\n" + TAG + "\n"
p.write_text(t, encoding="utf-8")
print("[OK] replaced gitleaks overwrite-to-default assignments (best-effort)")
PY

python3 -m py_compile "$APP"
echo "[OK] py_compile OK"
echo "DONE"
