#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need curl; need grep; need sed; need head; need date; need mktemp
command -v node >/dev/null 2>&1 || true
command -v systemctl >/dev/null 2>&1 || true

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"

ok(){ echo "[OK] $*"; }
warn(){ echo "[WARN] $*"; }
err(){ echo "[ERR] $*"; exit 2; }

echo "== [0] quick markers check =="
python3 - <<'PY'
from pathlib import Path
import sys

must = [
  ("static/js/vsp_runs_quick_actions_v1.js", "VSP_P2_5_RUNS_AUTOFILTER_RID_V1"),
  ("static/js/vsp_dashboard_luxe_v1.js", "VSP_P2_6D_LUXE_HEAD_ROOT_FIX_V1"),
  ("static/js/vsp_dashboard_luxe_v1.js", "VSP_P2_6E_LUXE_JGET_UNWRAP_RUN_FILE_ALLOW_V1"),
]
bad = 0
for f, m in must:
    p = Path(f)
    if not p.exists():
        print("[MISS]", f); bad += 1; continue
    s = p.read_text(encoding="utf-8", errors="ignore")
    if m not in s:
        print("[MISS_MARK]", f, "->", m); bad += 1
    else:
        print("[HAVE_MARK]", f, "->", m)

p = Path("static/js/vsp_dashboard_luxe_v1.js")
if p.exists():
    s = p.read_text(encoding="utf-8", errors="ignore")
    if "*/\\n/*" in s[:200]:
        print("[BAD] luxe has literal \\n in header again"); bad += 1
    else:
        print("[OK] luxe header newline is clean")

sys.exit(2 if bad else 0)
PY
ok "markers present + luxe header clean"

echo
echo "== [1] node syntax check (key files) =="
if command -v node >/dev/null 2>&1; then
  node --check static/js/vsp_runs_quick_actions_v1.js
  node --check static/js/vsp_dashboard_luxe_v1.js
  ok "node --check OK"
else
  warn "node missing -> skip"
fi

echo
echo "== [2] HTTP smoke /vsp5 assets =="
HTML="$(curl -fsS "$BASE/vsp5" | head -c 200000)"
echo "$HTML" | grep -oE 'static/js/[^"]+\.js\?v=[0-9]+' | sort -u | sed -n '1,60p' || true
echo "$HTML" | grep -q "static/js/vsp_dashboard_luxe_v1.js" && ok "vsp_dashboard_luxe_v1.js included" || warn "luxe not found in /vsp5 HTML"
echo "$HTML" | grep -q "static/js/vsp_bundle_tabs5_v1.js" && ok "vsp_bundle_tabs5_v1.js included" || warn "bundle_tabs5 not found in /vsp5 HTML"

echo
echo "== [3] API smoke: run_file_allow findings_unified (robust) =="
RID="$(curl -fsS "$BASE/api/vsp/rid_latest" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("rid",""))')"
[ -n "$RID" ] || err "rid_latest empty"
echo "RID=$RID"

TMP="$(mktemp -t vsp_findings_unified.XXXXXX.json)"
HDR="$(mktemp -t vsp_findings_unified.XXXXXX.hdr)"
trap 'rm -f "$TMP" "$HDR"' EXIT

URL="$BASE/api/vsp/run_file_allow?rid=$RID&path=findings_unified.json&limit=3"
HTTP="$(curl -sS -D "$HDR" -o "$TMP" -w "%{http_code}" "$URL" || true)"
echo "HTTP=$HTTP  URL=$URL"

if [ "$HTTP" != "200" ]; then
  echo "[ERR] non-200"
  echo "--- headers ---"; sed -n '1,25p' "$HDR" || true
  echo "--- body(head) ---"; head -c 240 "$TMP" || true; echo
  exit 2
fi

python3 - <<'PY'
import json, sys
p = sys.argv[1]
raw = open(p, "rb").read()
# show early if not JSON
try:
    j = json.loads(raw.decode("utf-8", errors="strict"))
except Exception as e:
    print("[ERR] body is not JSON:", repr(e))
    print("body(head 240)=", raw[:240])
    raise SystemExit(2)

print("keys=", sorted(list(j.keys()))[:30])
print("ok=", j.get("ok"), "from=", j.get("from"))
meta = j.get("meta") or {}
print("meta.keys=", sorted(list(meta.keys()))[:20])
f = j.get("findings") or []
print("findings_len=", len(f))
if f:
    print("first.tool=", f[0].get("tool"), "sev=", f[0].get("severity"))
PY "$TMP"

ok "API run_file_allow wrapper looks OK"

echo
echo "== [4] Optional: restart service =="
if command -v systemctl >/dev/null 2>&1; then
  systemctl restart "$SVC" 2>/dev/null || true
  ok "systemctl restart attempted: $SVC"
else
  warn "systemctl not present -> skip restart"
fi

echo
echo "== [5] Manual browser checklist =="
cat <<EOF
1) Ctrl+Shift+R  /vsp5
   - No spam: "Fetch failed loading: HEAD ..."
   - No banner: "Findings payload mismatch"
2) Click badge RID -> /runs?rid=VSP_CI_...
3) /runs?rid=... must auto highlight + scroll + hide non-matching rows
EOF
