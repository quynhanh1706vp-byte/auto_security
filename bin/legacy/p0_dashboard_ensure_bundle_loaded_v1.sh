#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need systemctl; need curl; need grep

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
SVC="vsp-ui-8910.service"

python3 - <<'PY'
from pathlib import Path
import re, time

tpl_dir = Path("templates")
if not tpl_dir.exists():
    raise SystemExit("[ERR] templates/ not found")

# Find templates that likely render /vsp5 by looking for these dashboard scripts.
needles = [
    "vsp_dashboard_gate_story_v1.js",
    "vsp_dashboard_commercial_panels_v1.js",
    "VSP • Dashboard",
    "/vsp5",
]

cands = []
for p in tpl_dir.rglob("*.html"):
    s = p.read_text(encoding="utf-8", errors="replace")
    score = sum(1 for n in needles if n in s)
    if score >= 1:
        cands.append((score, p, s))

if not cands:
    raise SystemExit("[ERR] cannot find any dashboard template containing gate_story/panels")

cands.sort(key=lambda x: (-x[0], str(x[1])))
score, p, s = cands[0]
ts = time.strftime("%Y%m%d_%H%M%S")
bak = p.with_name(p.name + f".bak_add_bundle_{ts}")
bak.write_text(s, encoding="utf-8")

print(f"[PICK] template={p} score={score}")
print(f"[BACKUP] {bak}")

# If bundle already included -> do nothing
if "vsp_bundle_commercial_v2.js" in s:
    print("[OK] bundle already included in template")
    raise SystemExit(0)

tag = r'<script src="/static/js/vsp_bundle_commercial_v2.js?v={{ asset_v }}"></script>'

# Insert before </body> if present, otherwise append
if re.search(r"</body\s*>", s, flags=re.I):
    s2, n = re.subn(r"(</body\s*>)", tag + r"\n\1", s, count=1, flags=re.I)
else:
    s2, n = s + "\n" + tag + "\n", 1

if n != 1:
    raise SystemExit("[ERR] failed to insert script tag")

p.write_text(s2, encoding="utf-8")
print("[OK] inserted bundle script tag into template")
PY

echo "== restart service =="
systemctl restart "$SVC"

echo "== verify /vsp5 has bundle script tag =="
curl -fsS "$BASE/vsp5" | grep -n "vsp_bundle_commercial_v2.js" | head -n 5 || {
  echo "[ERR] /vsp5 still missing bundle include"; exit 2;
}

echo "== verify bundle is served =="
curl -fsS -I "$BASE/static/js/vsp_bundle_commercial_v2.js" | head -n 8

echo "[DONE] Hard refresh: Ctrl+Shift+R  $BASE/vsp5"
