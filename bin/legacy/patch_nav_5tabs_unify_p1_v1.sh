#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing cmd: $1"; exit 2; }; }
need python3; need date

TS="$(date +%Y%m%d_%H%M%S)"
echo "[INFO] TS=$TS"

python3 - <<'PY'
from pathlib import Path
import re, time

TPL_DIR = Path("templates")
targets = [
  TPL_DIR/"vsp_5tabs_enterprise_v2.html",
  TPL_DIR/"vsp_dashboard_2025.html",
  TPL_DIR/"vsp_data_source_v1.html",
  TPL_DIR/"vsp_rule_overrides_v1.html",
]

MARK = "VSP_P1_NAV5_UNIFY_V1"
NAV = r'''
<!-- {MARK} -->
<div id="vspNav5" style="position:sticky;top:0;z-index:9999;background:rgba(10,14,20,.92);backdrop-filter: blur(6px);
  border-bottom:1px solid rgba(255,255,255,.08);padding:10px 12px;display:flex;gap:10px;align-items:center;">
  <div style="font-weight:900;letter-spacing:.4px;color:#cfe0ff;">VSP</div>

  <a class="pill" href="/" style="text-decoration:none;padding:8px 10px;border-radius:12px;
     background:rgba(255,255,255,.06);color:#dbe7ff;font-weight:700;">Dashboard</a>

  <a class="pill" href="/vsp5" style="text-decoration:none;padding:8px 10px;border-radius:12px;
     background:rgba(255,255,255,.06);color:#dbe7ff;font-weight:700;">Runs &amp; Reports</a>

  <a class="pill" href="/data_source" style="text-decoration:none;padding:8px 10px;border-radius:12px;
     background:rgba(255,255,255,.06);color:#dbe7ff;font-weight:700;">Data Source</a>

  <a class="pill" href="/settings" style="text-decoration:none;padding:8px 10px;border-radius:12px;
     background:rgba(255,255,255,.06);color:#dbe7ff;font-weight:700;">Settings</a>

  <a class="pill" href="/rule_overrides" style="text-decoration:none;padding:8px 10px;border-radius:12px;
     background:rgba(255,255,255,.06);color:#dbe7ff;font-weight:700;">Rule Overrides</a>

  <div style="margin-left:auto;opacity:.85;font-size:12px;color:#9bb2d9;">
    P1 UI • nav unified
  </div>
</div>
'''.strip().replace("{MARK}", MARK)

def inject_after_body_open(html: str) -> str:
  if MARK in html:
    return html
  # insert right after <body ...>
  m = re.search(r"<body\b[^>]*>", html, flags=re.I)
  if not m:
    return html  # no body tag -> skip
  i = m.end()
  return html[:i] + "\n" + NAV + "\n" + html[i:]

changed = 0
for f in targets:
  if not f.exists():
    print(f"[SKIP] missing template: {f}")
    continue
  s = f.read_text(encoding="utf-8", errors="replace")
  s2 = inject_after_body_open(s)
  if s2 != s:
    bak = f"{f}.bak_nav5_{int(time.time())}"
    Path(bak).write_text(s, encoding="utf-8")
    f.write_text(s2, encoding="utf-8")
    print(f"[OK] injected nav5 into: {f.name} (backup: {Path(bak).name})")
    changed += 1
  else:
    print(f"[OK] already/unchanged: {f.name}")

print(f"[DONE] templates patched: {changed}")
PY

echo "[OK] done. Ctrl+F5 /vsp5 and other pages."
