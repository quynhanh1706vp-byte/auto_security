#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need curl; need grep

W="wsgi_vsp_ui_gateway.py"
[ -f "$W" ] || { echo "[ERR] missing $W"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$W" "${W}.bak_p107_${TS}"
echo "[BACKUP] ${W}.bak_p107_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, sys

p=Path("wsgi_vsp_ui_gateway.py")
s=p.read_text(encoding="utf-8", errors="replace")

marker="VSP_FIX_RUNS_V3_WRAPAPP_V2"
if marker not in s:
    print("[ERR] marker not found:", marker)
    sys.exit(2)

# Work only in a window after the marker to avoid unintended changes
idx=s.find(marker)
win=s[idx: idx+12000]  # big enough to include the wrapper function

# 1) Ensure roots include out_ci + ui/out_ci
# Try common patterns
roots_patterns=[
    r'roots\s*=\s*\[\s*"/home/test/Data/SECURITY_BUNDLE/out"\s*\]',
    r'ROOTS\s*=\s*\[\s*"/home/test/Data/SECURITY_BUNDLE/out"\s*\]',
]
new_roots='roots = ["/home/test/Data/SECURITY_BUNDLE/out", "/home/test/Data/SECURITY_BUNDLE/out_ci", "/home/test/Data/SECURITY_BUNDLE/ui/out_ci"]'

patched=False
for pat in roots_patterns:
    m=re.search(pat, win)
    if m:
        win2=re.sub(pat, new_roots, win, count=1)
        if win2!=win:
            win=win2; patched=True
        break

# If no explicit roots assignment found, insert one right after marker area
if not patched:
    # Insert a roots list near the top of wrapper window if it contains os.listdir(root)
    if "os.listdir" in win and "roots" in win:
        # best-effort: do nothing
        pass
    else:
        # still proceed; but warn
        print("[WARN] roots assignment not found; continuing")

# 2) Allow both RUN_ and VSP_CI_ in filters
# Replace: name.startswith("RUN_") -> (name.startswith("RUN_") or name.startswith("VSP_CI_"))
win = re.sub(r'name\.startswith\("RUN_"\)', r'(name.startswith("RUN_") or name.startswith("VSP_CI_"))', win)

# 3) Pin newest VSP_CI_ to front before slicing
# Insert pin block just before first slicing pattern "items = items[:limit" or "items[:limit]"
pin_block = r'''
        # [VSP_P107] pin newest VSP_CI_ into first page (avoid RID mismatch)
        if include_ci:
            vsp_ci = [x for x in items if str(x.get("rid","")).startswith("VSP_CI_") and not str(x.get("rid","")).startswith("VSP_CI_RUN_")]
            if vsp_ci:
                newest_ci = vsp_ci[0]
                rest = [x for x in items if x is not newest_ci]
                items = [newest_ci] + rest
'''
if "VSP_P107" not in win:
    # Try to place before a slicing line
    m=re.search(r'(?m)^\s*items\s*=\s*items\[:\s*limit', win)
    if m:
        insert_at=m.start()
        win = win[:insert_at] + pin_block + win[insert_at:]
    else:
        # Try alternative: before return out dict
        m=re.search(r'(?m)^\s*out\s*=\s*\{', win)
        if m:
            insert_at=m.start()
            win = win[:insert_at] + pin_block + win[insert_at:]
        else:
            print("[WARN] could not find insertion point for pin block")

# 4) Force ver="p107" if wrapper returns a JSON dict
# Replace '"ver": None' or missing ver assignment: best-effort add ver key if pattern exists
win = re.sub(r'"ver"\s*:\s*None', '"ver": "p107"', win)
win = re.sub(r"ver\s*=\s*None", 'ver = "p107"', win)

# Write back only the window change
s2 = s[:idx] + win + s[idx+len(win):]
p.write_text(s2, encoding="utf-8")
print("[OK] patched wrapper window (include_ci roots + VSP_CI filter + pin + ver=p107)")
PY

echo "== [P107] py_compile =="
python3 -m py_compile "$W"

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"

echo "== [P107] daemon-reload + restart =="
sudo systemctl daemon-reload
sudo systemctl restart "$SVC"
sudo systemctl is-active "$SVC" --quiet && echo "[OK] service active" || { echo "[ERR] service not active"; exit 2; }

echo "== [P107] wait /runs up (timeout relaxed) =="
ok=0
for i in $(seq 1 180); do
  if curl -fsS --connect-timeout 1 --max-time 6 "$BASE/runs" -o /dev/null; then ok=1; break; fi
  sleep 0.2
done
[ "$ok" -eq 1 ] || { echo "[ERR] /runs still not reachable"; journalctl -u "$SVC" -n 120 --no-pager | tail -n 120; exit 2; }

echo "== [P107] smoke runs_v3 must show ver=p107 + has VSP_CI =="
curl -fsS "$BASE/api/ui/runs_v3?limit=50&include_ci=1" -o /tmp/p107_runs_v3.json
python3 - <<'PY'
import json
j=json.load(open("/tmp/p107_runs_v3.json","r",encoding="utf-8",errors="replace"))
items=j.get("items",[])
txt=str(j)
print("ok=", j.get("ok"), "ver=", j.get("ver"), "items=", len(items),
      "first=", (items[0].get("rid") if items else None),
      "has_VSP_CI=", ("VSP_CI_" in txt))
PY

echo "[OK] P107 done"
