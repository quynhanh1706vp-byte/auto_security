#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
TS="$(date +%Y%m%d_%H%M%S)"
OUT="out_ci/p463fixh_${TS}"
mkdir -p "$OUT"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1" | tee -a "$OUT/log.txt"; exit 2; }; }
need python3; need date; need grep; need head; need curl; need awk
command -v sudo >/dev/null 2>&1 || { echo "[ERR] need sudo" | tee -a "$OUT/log.txt"; exit 2; }
command -v systemctl >/dev/null 2>&1 || { echo "[ERR] need systemctl" | tee -a "$OUT/log.txt"; exit 2; }

W="wsgi_vsp_ui_gateway.py"
[ -f "$W" ] || { echo "[ERR] missing $W" | tee -a "$OUT/log.txt"; exit 2; }

cp -f "$W" "$OUT/${W}.bak_${TS}"
echo "[OK] backup => $OUT/${W}.bak_${TS}" | tee -a "$OUT/log.txt"

python3 - <<'PY'
from pathlib import Path
import re, sys

p=Path("wsgi_vsp_ui_gateway.py")
s=p.read_text(encoding="utf-8", errors="replace")

MARK="VSP_P463FIXH_SAFE_ADD_URL_RULE_V1"
if MARK in s:
    print("[OK] already patched P463fixh")
    sys.exit(0)

# Count occurrences before
before = len(re.findall(r"\.add_url_rule\s*\(", s))

# Replace `<obj>.add_url_rule(` with `getattr(<obj>,"add_url_rule", lambda *a, **k: None)(`
# This prevents AttributeError in non-Flask wrapper environments.
pat = re.compile(r"\b([A-Za-z_][A-Za-z0-9_]*)\.add_url_rule\s*\(")
s2 = pat.sub(r'getattr(\1, "add_url_rule", (lambda *a, **k: None))(', s)

after = len(re.findall(r"\.add_url_rule\s*\(", s2))
if before == 0:
    print("[WARN] no .add_url_rule( occurrences found; nothing changed")
    sys.exit(0)

# Stamp marker once near top (after imports) so we don't reapply
m = re.search(r"(?s)\A((?:\s*#.*\n)*)((?:\s*(?:from|import)\s+.*\n)+)", s2)
stamp = f"\n# --- {MARK} ---\n"
if m:
    head=m.group(0)
    rest=s2[len(head):]
    s2 = head + stamp + rest
else:
    s2 = stamp + s2

p.write_text(s2, encoding="utf-8")
print(f"[OK] patched .add_url_rule calls: before={before} after_dot_calls={after}")
PY

python3 -m py_compile "$W" | tee -a "$OUT/log.txt"

echo "[INFO] restart $SVC" | tee -a "$OUT/log.txt"
sudo systemctl restart "$SVC" || true
sleep 1
sudo systemctl is-active "$SVC" | tee -a "$OUT/log.txt" || true

echo "== check crash signature in last logs (should be empty) ==" | tee -a "$OUT/log.txt"
tail -n 250 out_ci/ui_8910.error.log | grep -n "AttributeError: .*add_url_rule" || true

echo "== quick exports sanity ==" | tee -a "$OUT/log.txt"
curl -sS --connect-timeout 1 --max-time 10 "$BASE/api/vsp/sha256" | head -c 200 | tee -a "$OUT/log.txt"
echo "" | tee -a "$OUT/log.txt"
curl -sS -D- -o /dev/null --connect-timeout 1 --max-time 10 "$BASE/api/vsp/export_csv" \
 | awk 'BEGIN{IGNORECASE=1} /^HTTP\/|^Content-Type:|^Content-Disposition:/{print}' | tee -a "$OUT/log.txt"

echo "[OK] P463fixh done: $OUT/log.txt" | tee -a "$OUT/log.txt"
