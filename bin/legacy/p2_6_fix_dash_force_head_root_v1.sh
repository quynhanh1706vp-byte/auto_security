#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3
command -v node >/dev/null 2>&1 || { echo "[WARN] node not found -> skip node --check"; }

TS="$(date +%Y%m%d_%H%M%S)"
JS_DIR="static/js"
[ -d "$JS_DIR" ] || { echo "[ERR] missing $JS_DIR"; exit 2; }

python3 - <<'PY'
from pathlib import Path
import re, sys, time

jsdir = Path("static/js")
targets = []
for p in jsdir.glob("*.js"):
    try:
        s = p.read_text(encoding="utf-8", errors="ignore")
    except Exception:
        continue
    if ("VSP_DASH_FORCE" in s) or ("#vsp-dashboard-main" in s) or ("vsp-dashboard-main" in s and "querySelector" in s):
        targets.append((p, s))

if not targets:
    print("[ERR] cannot find dashboard-force JS to patch (no VSP_DASH_FORCE / #vsp-dashboard-main)", file=sys.stderr)
    sys.exit(2)

patched = 0
for p, s in targets:
    orig = s

    # 1) HEAD -> GET (avoid Chrome "Fetch failed loading: HEAD ..." spam)
    s = re.sub(r'(method\s*:\s*)(["\'])HEAD\2', r'\1"GET"', s)
    s = re.sub(r'(method\s*=\s*)(["\'])HEAD\2', r'\1"GET"', s)

    # 2) root fallback: if code does document.querySelector('#vsp-dashboard-main') then fallback to body
    # handle both quote styles
    s = s.replace("document.querySelector('#vsp-dashboard-main')",
                  "(document.querySelector('#vsp-dashboard-main') || document.body)")
    s = s.replace('document.querySelector("#vsp-dashboard-main")',
                  '(document.querySelector("#vsp-dashboard-main") || document.body)')

    # also catch common var assignment patterns
    s = re.sub(r'(\bconst\s+root\s*=\s*)document\.querySelector\((["\'])#vsp-dashboard-main\2\)',
               r'\1(document.querySelector("#vsp-dashboard-main") || document.body)', s)
    s = re.sub(r'(\bvar\s+root\s*=\s*)document\.querySelector\((["\'])#vsp-dashboard-main\2\)',
               r'\1(document.querySelector("#vsp-dashboard-main") || document.body)', s)
    s = re.sub(r'(\blet\s+root\s*=\s*)document\.querySelector\((["\'])#vsp-dashboard-main\2\)',
               r'\1(document.querySelector("#vsp-dashboard-main") || document.body)', s)

    if s != orig:
        bak = p.with_suffix(p.suffix + f".bak_dashforce_fix_{time.strftime('%Y%m%d_%H%M%S')}")
        bak.write_text(orig, encoding="utf-8")
        p.write_text(s, encoding="utf-8")
        print(f"[OK] patched {p} (backup {bak.name})")
        patched += 1

print(f"[DONE] patched_files={patched} total_candidates={len(targets)}")
PY

if command -v node >/dev/null 2>&1; then
  # check any patched candidates quickly
  for f in static/js/*.js; do
    grep -q "VSP_DASH_FORCE" "$f" 2>/dev/null && node --check "$f" && echo "[OK] node --check: $f" || true
  done
fi

echo
echo "[NEXT] Hard refresh /vsp5 (Ctrl+Shift+R) -> expect:"
echo "  - no more HEAD spam"
echo "  - no '[VSP_DASH_FORCE] ... không thấy #vsp-dashboard-main'"
