#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need curl; need wc; need grep

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
TS="$(date +%Y%m%d_%H%M%S)"

echo "== [0] fetch live /vsp5 html =="
HTML="$(curl -fsS "$BASE/vsp5")"
LIVE="/tmp/vsp5_live_${TS}.html"
echo "$HTML" > "$LIVE"
echo "[OK] saved $LIVE bytes=$(wc -c < "$LIVE")"

python3 - "$TS" <<'PY'
from pathlib import Path
import re, sys

ts = sys.argv[1]
live_path = Path(f"/tmp/vsp5_live_{ts}.html")
live = live_path.read_text(errors="ignore")

tpl_dir = Path("templates")
cands = list(tpl_dir.rglob("*.html"))
if not cands:
    print("[ERR] no templates/*.html found")
    raise SystemExit(2)

if 'id="vsp-dashboard-main"' in live:
    print("[OK] live HTML already has anchor -> nothing to patch")
    raise SystemExit(0)

lines = [ln.strip() for ln in live.splitlines() if ln.strip()]
picked = []
for ln in lines:
    l = ln.lower()
    if any(t in l for t in ["<div", "<main", "<section", "<nav", "<header", "<script", "<link", "vsp_", "static/js", "static/css"]):
        ln2 = re.sub(r"\s+", " ", ln)[:140]
        if len(ln2) >= 25:
            picked.append(ln2)
    if len(picked) >= 80:
        break
picked = list(dict.fromkeys(picked)) or [live[i:i+120] for i in range(0, min(len(live), 2400), 200)]

def score(t: str) -> int:
    s = 0
    for p in picked:
        if p in t:
            s += 2
        else:
            toks = [x for x in re.split(r"[^A-Za-z0-9_/-]+", p) if len(x) >= 6]
            hit = sum(1 for x in toks[:12] if x in t)
            if hit >= 2:
                s += 1
    return s

scored = []
for f in cands:
    txt = f.read_text(errors="ignore")
    # ưu tiên template kiểu dashboard/tab bundle
    if ("vsp_bundle_tabs5_v1.js" not in txt) and ("vsp_tabs4_autorid_v1.js" not in txt):
        continue
    scored.append((score(txt), f))

scored.sort(key=lambda x: x[0], reverse=True)
top = [x for x in scored if x[0] > 0][:6]

if not top:
    # fallback theo tên/keyword vsp5
    for f in cands:
        txt = f.read_text(errors="ignore")
        if "vsp5" in txt or "/vsp5" in txt or "vsp5" in f.name.lower():
            top.append((1, f))
    top = top[:6]

if not top:
    print("[ERR] could not identify template to patch")
    raise SystemExit(2)

print("[OK] top templates:")
for sc, f in top:
    print(f" - score={sc} {f}")

def ensure_anchor(html: str) -> str:
    if 'id="vsp-dashboard-main"' in html:
        return html
    out = re.sub(r"(<body[^>]*>)", r'\1\n  <div id="vsp-dashboard-main"></div>', html, count=1, flags=re.I)
    if out != html:
        return out
    out = re.sub(r"(</body>)", r'  <div id="vsp-dashboard-main"></div>\n\1', html, count=1, flags=re.I)
    return out

patched = 0
for _, f in top:
    old = f.read_text(errors="ignore")
    new = ensure_anchor(old)
    if new != old:
        bak = f.with_suffix(f.suffix + f".bak_anchor_{ts}")
        bak.write_text(old)
        f.write_text(new)
        patched += 1
        print(f"[PATCH] {f} (backup {bak.name})")
    else:
        print(f"[SKIP] {f} already has anchor")

print(f"[DONE] patched templates={patched}")
PY

echo "== [1] restart service (if exists) =="
if command -v systemctl >/dev/null 2>&1; then
  systemctl restart "$SVC" 2>/dev/null || true
fi

echo "== [2] verify anchor on live /vsp5 =="
curl -sS "$BASE/vsp5" | grep -n 'id="vsp-dashboard-main"' | head -n 3 || echo "[ERR] anchor still missing"

echo "[DONE] If still not visible in browser: Ctrl+Shift+R."
