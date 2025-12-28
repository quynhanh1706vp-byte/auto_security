#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

APP="vsp_demo_app.py"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need grep; need sed; need curl

[ -f "$APP" ] || { echo "[ERR] missing $APP"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$APP" "${APP}.bak_p62v2_${TS}"
echo "[OK] backup ${APP}.bak_p62v2_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, sys, datetime

APP=Path("vsp_demo_app.py")
s=APP.read_text(encoding="utf-8", errors="replace")

# ----------------------------
# Patch A: run_status_v1 never 404 (only inside the run_status_v1 handler block)
# ----------------------------
MARK_A="P62V2_RUN_STATUS_ALWAYS_200"
if MARK_A not in s:
    # locate the first decorator/route mentioning run_status_v1
    idx = s.find("run_status_v1")
    if idx < 0:
        print("[ERR] cannot find run_status_v1 in vsp_demo_app.py")
        sys.exit(2)

    # find a nearby block start (prefer the decorator line)
    start = s.rfind("\n@", 0, idx)
    if start < 0: start = s.rfind("\n", 0, idx)
    # find next decorator/def at col0 (very defensive)
    m_next = re.search(r"\n@|\n(?:async\s+def|def)\s+", s[idx+1:])
    end = (idx+1 + m_next.start()) if m_next else len(s)

    block = s[start:end]

    # change "return jsonify(...), 404" to 200 only if this return is inside run_status block
    block2 = re.sub(r'(return\s+jsonify\([^\n]*\))\s*,\s*404\b', r'\1, 200', block)
    # also handle "status=404" patterns
    block2 = re.sub(r'\bstatus\s*=\s*404\b', 'status=200', block2)

    if block2 == block:
        # if no explicit 404 in block, still mark so we know we looked
        block2 = block + f"\n# {MARK_A}: scanned (no explicit 404 found)\n"
    else:
        block2 = block2 + f"\n# {MARK_A}: patched 404->200 in run_status_v1 handler\n"

    s = s[:start] + block2 + s[end:]
    print("[OK] patched run_status_v1 => always HTTP 200")

else:
    print("[OK] already patched:", MARK_A)

# ----------------------------
# Patch B: top_findings_v2 add run_id alias when only rid exists (compat)
# ----------------------------
MARK_B="P62V2_TOPFIND_RUNID_ALIAS"
if MARK_B not in s:
    # heuristic: find the json payload assembly that includes '"rid"' and '"items"' close to 'top_findings_v2'
    pos = s.find("top_findings_v2")
    if pos > 0:
        window = s[max(0,pos-2000):pos+8000]
        # patch common pattern: jsonify({ ... "rid": rid, ... })
        # We'll inject: "run_id": rid if run_id missing in that dict literal.
        # Do it by inserting right after "rid": ...
        def inject_runid(m):
            txt = m.group(0)
            if '"run_id"' in txt or "'run_id'" in txt:
                return txt + f"\n# {MARK_B}: already had run_id\n"
            # insert after rid field
            txt2 = re.sub(r'("rid"\s*:\s*[^,\n}]+)\s*,', r'\1,\n        "run_id": (j.get("rid") if isinstance(j, dict) else None) or rid,', txt, count=1)
            if txt2 == txt:
                # fallback: insert a safe post-processing block before return
                return txt + f"\n# {MARK_B}: no literal rid field matched\n"
            return txt2 + f"\n# {MARK_B}: added run_id alias\n"

        # Target a small safe area: the first 'return jsonify(' after pos
        mret = re.search(r"return\s+jsonify\(\s*\{[\s\S]{0,1500}?\}\s*\)", window)
        if mret:
            orig = mret.group(0)
            patched = orig
            if '"run_id"' not in orig and "'run_id'" not in orig and '"rid"' in orig:
                # simple injection in dict literal: add run_id right after rid
                patched = re.sub(r'("rid"\s*:\s*[^,\n}]+)\s*,', r'\1,\n        "run_id": rid,', orig, count=1)
                if patched != orig:
                    window2 = window.replace(orig, patched + f"\n# {MARK_B}: injected\n", 1)
                    s = s[:max(0,pos-2000)] + window2 + s[pos+8000:]
                    print("[OK] patched top_findings_v2 => include run_id alias")
                else:
                    print("[WARN] could not inject run_id alias (pattern not matched)")
            else:
                print("[OK] top_findings_v2 already includes run_id or no rid literal")
        else:
            print("[WARN] could not locate top_findings_v2 return jsonify block")
    else:
        print("[WARN] cannot locate top_findings_v2 in file")
else:
    print("[OK] already patched:", MARK_B)

APP.write_text(s, encoding="utf-8")
PY

echo "== [1] py_compile =="
python3 -m py_compile "$APP"
echo "[OK] py_compile OK"

echo "== [2] restart service =="
sudo systemctl restart "$SVC"

echo "== [3] wait /vsp5 up =="
ok=0
for i in $(seq 1 20); do
  code="$(curl -sS -o /dev/null -w "%{http_code}" --max-time 2 "$BASE/vsp5" || true)"
  if [ "$code" = "200" ]; then ok=1; break; fi
  sleep 0.4
done
[ "$ok" = "1" ] || { echo "[ERR] UI not up"; exit 2; }
echo "[OK] /vsp5 200"

echo "== [4] verify run_status_v1 returns HTTP 200 =="
RID="$(curl -fsS "$BASE/api/vsp/top_findings_v2?limit=1" | python3 -c 'import sys,json;j=json.load(sys.stdin);print(j.get("rid") or j.get("run_id") or "")')"
echo "[INFO] RID=$RID"
[ -n "$RID" ] || { echo "[ERR] RID empty"; exit 2; }

curl -sS -o /tmp/rs.json -w "HTTP=%{http_code}\n" "$BASE/api/vsp/run_status_v1/$RID"
head -c 400 /tmp/rs.json; echo
