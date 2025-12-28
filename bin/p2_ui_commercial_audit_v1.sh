#!/usr/bin/env bash
set -euo pipefail
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need curl; need grep; need sed; need awk

pages=(/vsp5 /runs /data_source /settings /rule_overrides)

python3 - <<'PY'
import re, subprocess, sys, collections

BASE = sys.argv[1] if len(sys.argv)>1 else "http://127.0.0.1:8910"
pages = ["/vsp5","/runs","/data_source","/settings","/rule_overrides"]

def sh(cmd):
    return subprocess.check_output(cmd, shell=True, text=True, stderr=subprocess.STDOUT)

asset_re = re.compile(r'static/(js|css)/[^"\']+\.(?:js|css)\?v=\d+')
fname_re = re.compile(r'static/(js|css)/([^"\']+\.(?:js|css))\?v=\d+')

print("== VSP Commercial UI Audit v1 ==")
overall_warn = 0

for p in pages:
    html = sh(f'curl -sS "{BASE}{p}"')[:600000]  # cap
    assets = asset_re.findall(html)
    paths = asset_re.findall  # not used
    asset_paths = re.findall(r'static/(?:js|css)/[^"\']+\.(?:js|css)\?v=\d+', html)
    fnames = [m.group(2) for m in fname_re.finditer(html)]

    print(f"\n--- PAGE {p} ---")
    print(f"assets_total={len(asset_paths)} unique={len(set(asset_paths))}")

    # duplicates by filename (commercial should avoid same file repeated)
    c = collections.Counter(fnames)
    dups = [(k,v) for k,v in c.items() if v>1]
    if dups:
        overall_warn += 1
        print("[WARN] duplicate asset filenames:")
        for k,v in sorted(dups, key=lambda x:-x[1])[:20]:
            print(f"  - {k} x{v}")
    else:
        print("[OK] no duplicate asset filename")

    # anchor checks (dashboard)
    if p == "/vsp5":
        if 'id="vsp-dashboard-main"' not in html:
            overall_warn += 1
            print('[WARN] missing anchor id="vsp-dashboard-main" (dash force will fail)')
        else:
            print('[OK] anchor #vsp-dashboard-main present')

        # banner mismatch present?
        if "Findings payload mismatch" in html:
            overall_warn += 1
            print('[WARN] mismatch banner string found in HTML')
        else:
            print('[OK] mismatch banner string not found in HTML')

        # rough duplicate section hints
        n_dash = html.count("VSP Dashboard")
        n_gate = html.lower().count("gate story")
        if n_dash > 1:
            overall_warn += 1
            print(f"[WARN] 'VSP Dashboard' appears {n_dash} times (possible duplicated block)")
        if n_gate > 1:
            overall_warn += 1
            print(f"[WARN] 'Gate story' appears {n_gate} times (possible duplicated block)")

    # print asset list (short)
    for a in sorted(set(asset_paths))[:30]:
        print("  ", a)
    if len(set(asset_paths)) > 30:
        print("  ...")

print(f"\n== SUMMARY == warnings={overall_warn}")
PY "$BASE"
