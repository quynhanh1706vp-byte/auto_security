#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date

W="wsgi_vsp_ui_gateway.py"
[ -f "$W" ] || { echo "[ERR] missing $W"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$W" "${W}.bak_topfind_polish_v1b_${TS}"
echo "[BACKUP] ${W}.bak_topfind_polish_v1b_${TS}"

python3 - <<'PY'
from pathlib import Path

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")

MARK = "VSP_P0_TOPFIND_MW_NO_FLASKROUTE_V1"
if MARK not in s:
    raise SystemExit("[ERR] missing MW marker VSP_P0_TOPFIND_MW_NO_FLASKROUTE_V1")

# --- patch only inside MW block to avoid collateral ---
b0 = s.find(f"# {MARK}")
b1 = s.find(f"# END {MARK}")
if b0 < 0 or b1 < 0 or b1 <= b0:
    raise SystemExit("[ERR] cannot locate MW block boundaries")

block = s[b0:b1]

# 1) Add component/version keys into normalize dict (idempotent)
if '"component": None' not in block:
    # try 2 known formats
    t1 = '"title": f.get("title"),\n            "cwe": f.get("cwe"),'
    r1 = '"title": f.get("title"),\n            "component": None,\n            "version": None,\n            "cwe": f.get("cwe"),'
    if t1 in block:
        block = block.replace(t1, r1, 1)
    else:
        t2 = '"title": f.get("title"),\n            "cwe": f.get("cwe"),'
        if t2 in block:
            block = block.replace(t2, r1, 1)

# 2) Inject derivation code before items.sort (idempotent)
DER_MARK = "# derive component/version for non-file vulns"
if DER_MARK not in block:
    inject = """
    # derive component/version for non-file vulns: "... in <pkg> <ver>"
    rx = re.compile(r"\\s+in\\s+([A-Za-z0-9_.\\-]+)\\s+([0-9][A-Za-z0-9_.\\-]*)\\s*$")
    for it in items:
        try:
            t = (it.get("title") or "")
            mm = rx.search(t)
            if mm:
                if not it.get("component"):
                    it["component"] = mm.group(1)
                if not it.get("version"):
                    it["version"] = mm.group(2)
        except Exception:
            pass
"""
    key = "items.sort(key=lambda x:"
    pos = block.find(key)
    if pos > 0:
        block = block[:pos] + inject + "\n    " + block[pos:]
    else:
        print("[WARN] cannot find items.sort; skip component/version derivation")

# 3) Add limit_applied + items_truncated into payload (idempotent)
if '"limit_applied"' not in block:
    # safest: replace the pair total/items line sequence
    a = '"total": len(items),\n                    "items": items[:limit],'
    b = '"total": len(items),\n                    "limit_applied": limit,\n                    "items_truncated": (len(items) > limit),\n                    "items": items[:limit],'
    if a in block:
        block = block.replace(a, b, 1)
    else:
        # fallback: handle different whitespace
        a2 = '"total": len(items),\n                    "items": items[:limit],'
        if a2 in block:
            block = block.replace(a2, b, 1)

# write back
s2 = s[:b0] + block + s[b1:]
p.write_text(s2, encoding="utf-8")
print("[OK] applied P1 polish v1b (component/version + flags)")
PY

python3 -m py_compile wsgi_vsp_ui_gateway.py
echo "[OK] py_compile OK"

sudo systemctl restart vsp-ui-8910.service
sudo systemctl is-active --quiet vsp-ui-8910.service && echo "[OK] service active"


BASE="http://127.0.0.1:8910"
RID="VSP_CI_20251218_114312"

rm -f /tmp/top.h /tmp/top.b
curl -sS --max-time 5 -D /tmp/top.h -o /tmp/top.b \
  "$BASE/api/vsp/top_findings_v1?rid=$RID&limit=5" || echo "CURL_EXIT=$?"

echo "== HEADERS =="; sed -n '1,15p' /tmp/top.h
echo "== BODY bytes =="; wc -c /tmp/top.b
echo "== BODY head =="; head -c 220 /tmp/top.b; echo

python3 - <<'PY'
import json, sys
b=open("/tmp/top.b","rb").read()
if not b.strip():
    print("ok= False rid_used= None total= None reason= EMPTY_BODY"); sys.exit(0)
if not b.lstrip().startswith((b"{", b"[")):
    print("ok= False rid_used= None total= None reason= NOT_JSON"); sys.exit(0)
j=json.loads(b.decode("utf-8","replace"))
print("ok=",j.get("ok"),"rid_used=",j.get("rid_used"),"total=",j.get("total"),
      "limit=",j.get("limit_applied"),"trunc=",j.get("items_truncated"),
      "reason=",j.get("reason"))
if j.get("items"):
    it=j["items"][0]
    print("first_component=",it.get("component"),"ver=",it.get("version"),"title=",(it.get("title") or "")[:80])
PY

echo "[DONE]"
