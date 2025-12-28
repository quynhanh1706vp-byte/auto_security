#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date

W="wsgi_vsp_ui_gateway.py"
[ -f "$W" ] || { echo "[ERR] missing $W"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$W" "${W}.bak_topfind_polish_${TS}"
echo "[BACKUP] ${W}.bak_topfind_polish_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("wsgi_vsp_ui_gateway.py")
s=p.read_text(encoding="utf-8", errors="replace")

# Patch inside _vsp__normalize_items: derive component/version from title "... in pkg ver"
pat = r'(def _vsp__normalize_items\(raw\):[\s\S]*?items\.append\(\{[\s\S]*?"title": f\.get\("title"\),[\s\S]*?\}\)\n)'
m=re.search(pat, s)
if not m:
    print("[WARN] could not locate normalize_items block; skip")
else:
    # inject component/version extraction after title assignment in dict build
    s = re.sub(
        r'"title": f\.get\("title"\),',
        '"title": f.get("title"),\n'
        '            "component": None,\n'
        '            "version": None,',
        s,
        count=1
    )

    # after building items list, fill component/version if missing
    inject = r'''
    # derive component/version for non-file vulns: "... in <pkg> <ver>"
    rx = re.compile(r"\s+in\s+([A-Za-z0-9_.\-]+)\s+([0-9][A-Za-z0-9_.\-]*)\s*$")
    for it in items:
        try:
            t = (it.get("title") or "")
            mm = rx.search(t)
            if mm:
                it["component"] = it.get("component") or mm.group(1)
                it["version"] = it.get("version") or mm.group(2)
        except Exception:
            pass
'''
    # place inject just before "items.sort(...)" inside normalize_items
    s = re.sub(r'\n\s*items\.sort\(', "\n" + inject + "\n    items.sort(", s, count=1)

# Patch in middleware response to include flags
s = re.sub(r'"total": len\(items\),\s*"items": items\[:limit\],',
           '"total": len(items),\n                    "limit_applied": limit,\n                    "items_truncated": (len(items) > limit),\n                    "items": items[:limit],', s, count=1)

p.write_text(s, encoding="utf-8")
print("[OK] patched topfind polish (component/version + flags)")
PY

python3 -m py_compile wsgi_vsp_ui_gateway.py
echo "[OK] py_compile OK"

sudo systemctl restart vsp-ui-8910.service
sudo systemctl is-active --quiet vsp-ui-8910.service && echo "[OK] service active"

BASE="http://127.0.0.1:8910"
RID="VSP_CI_20251218_114312"
curl -sS "$BASE/api/vsp/top_findings_v1?rid=$RID&limit=5" | python3 - <<'PY'
import sys,json
j=json.load(sys.stdin)
print("ok=",j.get("ok"),"rid_used=",j.get("rid_used"),"total=",j.get("total"),"limit=",j.get("limit_applied"),"trunc=",j.get("items_truncated"))
if j.get("items"):
  print("first_component=",j["items"][0].get("component"),"ver=",j["items"][0].get("version"))
PY
