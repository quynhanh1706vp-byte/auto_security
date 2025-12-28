#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need node; need date; need systemctl

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
JS="static/js/vsp_bundle_commercial_v2.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_fixsyntax_${TS}"
echo "[BACKUP] ${JS}.bak_fixsyntax_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, sys

p = Path("static/js/vsp_bundle_commercial_v2.js")
s = p.read_text(encoding="utf-8", errors="replace")

# fix broken const declarations introduced in addon
s2 = s
s2 = s2.replace("const $(q,el=document){ return el.querySelector(q); }",
                "const $ = (q, el=document) => el.querySelector(q);")
s2 = s2.replace("const $all(q,el=document){ return Array.from(el.querySelectorAll(q)); }",
                "const $all = (q, el=document) => Array.from(el.querySelectorAll(q));")

if s2 == s:
    print("[WARN] pattern not found; nothing changed (maybe already fixed or different formatting).")
else:
    p.write_text(s2, encoding="utf-8")
    print("[OK] patched bundle syntax")
PY

node --check static/js/vsp_bundle_commercial_v2.js
systemctl restart "$SVC"
echo "[DONE] reload /vsp5"
