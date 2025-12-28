#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need curl
command -v systemctl >/dev/null 2>&1 || true

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
TS="$(date +%Y%m%d_%H%M%S)"

HTML="$(curl -fsS "$BASE/reports")"
# try to detect which template by unique title or marker; fallback brute-force inject to any template containing "Reports"
python3 - <<'PY'
from pathlib import Path
import re, sys

html = sys.stdin.read()
tpl_dir = Path("templates")
targets = []

# If HTML has title, use that to match template content
m = re.search(r"<title>(.*?)</title>", html, re.I|re.S)
title = (m.group(1).strip() if m else "")

for p in tpl_dir.rglob("*.html"):
    t = p.read_text(encoding="utf-8", errors="replace")
    name = p.name.lower()
    # try match by title
    if title and title in t:
        targets.append(p); continue
    # else heuristic for reports pages
    if "report" in name or "runs_reports" in name:
        # already injected? skip
        targets.append(p)

# de-dup
seen=set(); uniq=[]
for p in targets:
    if str(p) not in seen:
        uniq.append(p); seen.add(str(p))
targets = uniq

MARK="VSP_P1_TABS4_AUTORID_NODASH_V1"
inject = '\n<!-- '+MARK+' -->\n<script src="/static/js/vsp_tabs4_autorid_v1.js?v={{ asset_v|default(\'\') }}"></script>\n'

patched=0
for p in targets:
    t = p.read_text(encoding="utf-8", errors="replace")
    if "vsp_tabs4_autorid_v1.js" in t:
        continue
    if "</body>" in t:
        t2 = t.replace("</body>", inject + "</body>", 1)
    else:
        t2 = t + inject
    p.write_text(t2, encoding="utf-8")
    print("[OK] injected into", p)
    patched += 1

if patched == 0:
    print("[WARN] no reports template patched (maybe /reports is built inline in python)")
PY <<<"$HTML"

systemctl restart "$SVC" 2>/dev/null || true
echo "[OK] restarted $SVC"

echo "== re-smoke /reports contains autorid js? =="
curl -sS "$BASE/reports" | grep -q "vsp_tabs4_autorid_v1.js" && echo "[OK] /reports has autorid js" || echo "[WARN] /reports still missing (route might be inline HTML in python)"
