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

ts = time.strftime("%Y%m%d_%H%M%S")
bundle_tag = '<script src="/static/js/vsp_bundle_commercial_v2.js?v={{ asset_v }}"></script>'

patched = 0
scanned = 0
targets = []

for p in tpl_dir.rglob("*.html"):
    s = p.read_text(encoding="utf-8", errors="replace")
    if "vsp_dashboard_gate_story_v1.js" not in s:
        continue
    scanned += 1
    if "vsp_bundle_commercial_v2.js" in s:
        continue
    targets.append(p)

if not targets:
    print(f"[OK] no templates need patch (scanned_gate_story={scanned})")
    raise SystemExit(0)

for p in targets:
    s = p.read_text(encoding="utf-8", errors="replace")
    bak = p.with_name(p.name + f".bak_force_bundle_{ts}")
    bak.write_text(s, encoding="utf-8")

    if re.search(r"</body\s*>", s, flags=re.I):
        s2, n = re.subn(r"(</body\s*>)", bundle_tag + r"\n\1", s, count=1, flags=re.I)
    else:
        s2, n = s + "\n" + bundle_tag + "\n", 1

    if n != 1:
        print("[WARN] cannot insert into:", p)
        continue

    p.write_text(s2, encoding="utf-8")
    patched += 1
    print(f"[OK] patched: {p} (backup={bak.name})")

print(f"[DONE] patched_files={patched} scanned_gate_story={scanned}")
PY

echo "== restart =="
systemctl restart "$SVC"

echo "== verify /vsp5 has bundle =="
curl -fsS "$BASE/vsp5" | grep -n "vsp_bundle_commercial_v2.js" | head -n 5 || {
  echo "[ERR] /vsp5 still missing bundle include"; exit 2;
}

echo "[OK] /vsp5 now includes bundle"
echo "[DONE] Hard refresh: Ctrl+Shift+R  $BASE/vsp5"
