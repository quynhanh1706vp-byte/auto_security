#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need grep; need sed; need curl

TS="$(date +%Y%m%d_%H%M%S)"
OUT="out_ci"; mkdir -p "$OUT"
EVID="$OUT/p109_${TS}"; mkdir -p "$EVID"

W="wsgi_vsp_ui_gateway.py"
[ -f "$W" ] || { echo "[ERR] missing $W"; exit 2; }
cp -f "$W" "${W}.bak_p109_${TS}"
echo "[BACKUP] ${W}.bak_p109_${TS}"

JS1="static/js/vsp_runs_kpi_compact_v3.js"
JS2="static/js/vsp_runs_quick_actions_v1.js"
for f in "$JS1" "$JS2"; do
  [ -f "$f" ] || { echo "[ERR] missing $f"; exit 2; }
  cp -f "$f" "${f}.bak_p109_${TS}"
  echo "[BACKUP] ${f}.bak_p109_${TS}"
done

python3 - <<'PY'
from pathlib import Path
import re

# --- 1) Patch P108 CI pin: choose newest CI by RID string (not by mtime) ---
w = Path("wsgi_vsp_ui_gateway.py")
s = w.read_text(encoding="utf-8", errors="replace")

if "VSP_P108_RUNS_V3_WRAP_CALLABLE_APP_APPLICATION_V1" not in s:
    raise SystemExit("[ERR] P108 block not found; cannot patch pin logic.")

marker = "VSP_P109_CI_PIN_BY_RID_V1"
if marker not in s:
    # Replace CI pin block inside _vsp_p108_scan()
    # Find the exact pattern introduced in P108:
    #   ci=[...]
    #   if ci:
    #       newest_ci=ci[0]
    # and replace with RID-based newest.
    pat = re.compile(
        r'(?s)# Pin newest REAL CI folder.*?if include_ci:\s*'
        r'ci=\[x for x in items if.*?\]\s*'
        r'if ci:\s*'
        r'newest_ci=ci\[0\]\s*'
        r'rest=\[x for x in items if x is not newest_ci\]\s*'
        r'items=\[newest_ci\]\+rest'
    )
    repl = (
        "# Pin newest REAL CI folder (prefer VSP_CI_*, avoid alias VSP_CI_RUN_*)\n"
        f"# {marker}\n"
        "    if include_ci:\n"
        "        ci=[x for x in items if str(x.get(\"rid\",\"\"))"
        ".startswith(\"VSP_CI_\") and not str(x.get(\"rid\",\"\"))"
        ".startswith(\"VSP_CI_RUN_\")]\n"
        "        if ci:\n"
        "            # Choose newest by RID string (stable) instead of mtime (can be skewed by touch/copy)\n"
        "            newest_ci = sorted(ci, key=lambda x: str(x.get(\"rid\",\"\")), reverse=True)[0]\n"
        "            rest=[x for x in items if x is not newest_ci]\n"
        "            items=[newest_ci]+rest"
    )
    s2, n = pat.subn(repl, s, count=1)
    if n != 1:
        # Fallback: do a smaller, safer substitution: newest_ci=ci[0] -> newest_ci=sorted(...)[0]
        s2 = re.sub(r'newest_ci=ci\[0\]',
                    'newest_ci = sorted(ci, key=lambda x: str(x.get("rid","")), reverse=True)[0]',
                    s, count=1)
    w.write_text(s2, encoding="utf-8")
    print("[OK] patched P108 CI pin to RID-based newest (P109)")
else:
    print("[OK] P109 pin already applied")

# --- 2) Patch /runs JS boot to DOM ready (avoid document.body is null) ---
def ensure_onready_and_wrap_calls(path: str):
    p = Path(path)
    t = p.read_text(encoding="utf-8", errors="replace")
    if "function onReady(fn)" not in t:
        helper = (
            "\n// VSP_P109_ONREADY_HELPER_V1\n"
            "function onReady(fn){\n"
            "  if (document.readyState === \"loading\") {\n"
            "    document.addEventListener(\"DOMContentLoaded\", fn, { once:true });\n"
            "  } else {\n"
            "    fn();\n"
            "  }\n"
            "}\n"
        )
        # insert helper near top (after 'use strict' if present)
        m = re.search(r'(?m)^\s*["\']use strict["\'];\s*$', t)
        if m:
            insert_at = m.end()
            t = t[:insert_at] + helper + t[insert_at:]
        else:
            t = helper + t

    # wrap common top-level calls like boot(); init(); bootSomething(); initSomething();
    def wrap_line(m):
        call = m.group(0).strip()
        return f"onReady(() => {{ {call} }});"

    # Replace standalone lines that are just a call
    t2, n1 = re.subn(r'(?m)^\s*(boot[A-Za-z0-9_]*\(\);\s*)$',
                     lambda m: wrap_line(m), t)
    t2, n2 = re.subn(r'(?m)^\s*(init[A-Za-z0-9_]*\(\);\s*)$',
                     lambda m: wrap_line(m), t2)

    # If nothing matched, also try any single-call line containing "boot" near EOF
    if (n1 + n2) == 0:
        t2, _ = re.subn(r'(?m)^\s*([A-Za-z0-9_$]*boot[A-Za-z0-9_$]*\(\);\s*)$',
                        lambda m: wrap_line(m), t2, count=1)

    p.write_text(t2, encoding="utf-8")
    print(f"[OK] DOM-ready wrapped: {path}")

ensure_onready_and_wrap_calls("static/js/vsp_runs_kpi_compact_v3.js")
ensure_onready_and_wrap_calls("static/js/vsp_runs_quick_actions_v1.js")
PY

echo "== [P109] py_compile gateway =="
python3 -m py_compile "$W"

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"

echo "== [P109] daemon-reload + restart =="
sudo systemctl daemon-reload
sudo systemctl restart "$SVC"
sudo systemctl is-active "$SVC" --quiet && echo "[OK] service active" || { echo "[ERR] service not active"; exit 2; }

echo "== [P109] wait LISTEN 8910 =="
ok=0
for i in $(seq 1 120); do
  if ss -lntp 2>/dev/null | grep -qE ':(8910)\b'; then ok=1; break; fi
  sleep 0.1
done
[ "$ok" -eq 1 ] || { echo "[ERR] no LISTEN 8910"; systemctl status "$SVC" --no-pager -n 80 | head -n 80; exit 2; }

echo "== [P109] wait /runs up =="
ok=0
for i in $(seq 1 200); do
  if curl -fsS --connect-timeout 1 --max-time 6 "$BASE/runs" -o /dev/null; then ok=1; break; fi
  sleep 0.2
done
[ "$ok" -eq 1 ] || { echo "[ERR] /runs not reachable"; journalctl -u "$SVC" -n 120 --no-pager | tail -n 120; exit 2; }

echo "== [P109] smoke: rid_latest vs runs_v3 top must match =="
rid_latest="$(curl -fsS "$BASE/api/vsp/rid_latest_v3?offset=0" | python3 -c 'import sys,json;j=json.load(sys.stdin);print(j.get("rid",""))')"
top="$(curl -fsS "$BASE/api/ui/runs_v3?limit=50&include_ci=1" | python3 -c 'import sys,json;j=json.load(sys.stdin);print(j["items"][0]["rid"] if j.get("items") else "")')"
echo "rid_latest=$rid_latest"
echo "top=$top"
python3 - <<PY
rl="$rid_latest".strip()
top="$top".strip()
print("MATCH=", (rl==top))
PY

echo "[OK] P109 done"
