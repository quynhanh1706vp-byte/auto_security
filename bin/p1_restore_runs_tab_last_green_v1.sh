#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing cmd: $1"; exit 2; }; }
need python3; need sudo; need systemctl; need curl; need jq; need ls; need awk; need sed

SVC="vsp-ui-8910.service"
BASE="${BASE_URL:-http://127.0.0.1:8910}"
TS="$(date +%Y%m%d_%H%M%S)"
echo "[INFO] TS=$TS BASE=$BASE"

pick_backup(){
  local base="$1"     # e.g. wsgi_vsp_ui_gateway.py
  local want_re="$2"  # optional marker regex
  local f
  for f in $(ls -1t "${base}".bak_* 2>/dev/null || true); do
    [ -f "$f" ] || continue
    if [ -n "${want_re}" ]; then
      grep -qE "${want_re}" "$f" || continue
    fi
    python3 -m py_compile "$f" >/dev/null 2>&1 || continue
    echo "$f"; return 0
  done
  echo ""; return 0
}

restore_from_backup(){
  local base="$1"
  local want_re="$2"
  local bak
  bak="$(pick_backup "$base" "$want_re")"
  if [ -z "$bak" ]; then
    bak="$(pick_backup "$base" "")"
  fi
  [ -n "$bak" ] || { echo "[ERR] no usable backup for $base"; exit 2; }
  cp -f "$base" "${base}.restorebak_${TS}" 2>/dev/null || true
  cp -f "$bak" "$base"
  echo "[RESTORE] $base <= $bak"
}

echo "== (1) stop service =="
sudo systemctl stop "$SVC" || true

echo "== (2) restore PY files to last known-green =="
restore_from_backup "wsgi_vsp_ui_gateway.py" "VSP_P1_FIX_SHA256SUMS_COMPAT_V2|VSP_P1_GW_RUNFILE_ANCHOR_ALLOW_SHA_V3|VSP_P1_ALLOW_SHA256SUMS"
restore_from_backup "vsp_runs_reports_bp.py" "VSP_P1_FIX_RUNS500_SPEED_V1|VSP_RUNS_REPORTS_BP_SAFE_P0_V1|VSP_RUNS_HAS_DETECT_P0_V1|VSP_P1_RUNS_500_GUARD"

# vsp_demo_app.py đôi khi bị patch hỏng (SyntaxError) -> nếu py_compile fail thì restore backup compilable gần nhất
if ! python3 -m py_compile vsp_demo_app.py >/dev/null 2>&1; then
  echo "[WARN] vsp_demo_app.py currently broken -> try restore a compilable backup"
  restore_from_backup "vsp_demo_app.py" ""
fi

echo "== (3) restore RUN tab JS (prefer limit=50 version) =="
JS="static/js/vsp_runs_tab_resolved_v1.js"
if [ -f "$JS" ]; then
  # pick JS backup that already has limit=50 marker (if exists)
  JSBAK=""
  for f in $(ls -1t "${JS}".bak_* 2>/dev/null || true); do
    [ -f "$f" ] || continue
    grep -qE "VSP_P1_UI_RUNS_LIMIT_50_V1" "$f" || continue
    JSBAK="$f"; break
  done
  if [ -n "$JSBAK" ]; then
    cp -f "$JS" "${JS}.restorebak_${TS}" || true
    cp -f "$JSBAK" "$JS"
    echo "[RESTORE] $JS <= $JSBAK"
  else
    # fallback: patch runs fetch URL to limit=50 (idempotent-ish)
    cp -f "$JS" "${JS}.bak_autopatch_limit50_${TS}"
    python3 - <<'PY'
from pathlib import Path
import re
p=Path("static/js/vsp_runs_tab_resolved_v1.js")
s=p.read_text(encoding="utf-8", errors="replace")
MARK="VSP_P1_UI_RUNS_LIMIT_50_V1"
if MARK not in s:
    # upgrade .../api/vsp/runs?limit=1 -> limit=50
    s2=re.sub(r'(/api/vsp/runs\?limit=)(\d+)', r'\g<1>50', s)
    if s2==s:
        # if no explicit limit, add it
        s2=re.sub(r'(/api/vsp/runs)(["\'])', r'\1?limit=50\2', s)
    if s2!=s:
        s = s2 + "\n/* "+MARK+" */\n"
p.write_text(s, encoding="utf-8")
print("[OK] JS limit=50 ensured:", MARK)
PY
  fi
fi

echo "== (4) sanity py_compile =="
python3 -m py_compile wsgi_vsp_ui_gateway.py vsp_runs_reports_bp.py vsp_demo_app.py

echo "== (5) start service =="
sudo systemctl start "$SVC"
sleep 1.2

echo "== (6) smoke /vsp5 =="
curl -sS -o /dev/null -w "code=%{http_code}\n" "$BASE/vsp5" | sed 's/^/[HTTP] /'

echo "== (7) get runs JSON & pick real RID (skip A2Z_INDEX) =="
J="$(curl -sS "$BASE/api/vsp/runs?limit=50" || true)"
echo "$J" | jq . >/dev/null 2>&1 || { echo "[ERR] runs not JSON"; echo "$J" | head -c 240; echo; exit 3; }

RID="$(echo "$J" | jq -r '
  .items[]?
  | select(.run_id!="A2Z_INDEX")
  | select((.has.html // false)==true or (.has.html_path//"")!="")
  | .run_id
' | head -n1)"
if [ -z "$RID" ] || [ "$RID" = "null" ]; then
  RID="$(echo "$J" | jq -r '.items[0].run_id // empty')"
fi
echo "RID=$RID"
[ -n "$RID" ] || { echo "[ERR] cannot pick RID"; exit 4; }

echo "== (8) verify required reports via run_file2 (must be 200) =="
chk(){
  local rel="$1"
  local code
  code="$(curl -sS -I -G "$BASE/api/vsp/run_file2" --data-urlencode "rid=$RID" --data-urlencode "name=$rel" | awk 'toupper($1)=="HTTP/1.1"{print $2; exit}')"
  echo "$rel -> ${code:-n/a}"
  [ "${code:-}" = "200" ]
}

FAIL=0
chk "reports/index.html" || FAIL=1
chk "reports/run_gate_summary.json" || FAIL=1
chk "reports/findings_unified.json" || FAIL=1
chk "reports/SUMMARY.txt" || FAIL=1
chk "reports/SHA256SUMS.txt" || FAIL=1

if [ "$FAIL" = "0" ]; then
  echo "== PASS: RUN tab backend contract OK (runs + run_file2 + sha256sums) =="
  exit 0
fi

echo "== FAIL: still missing/blocked. Quick diagnosis =="
echo "[HINT] Check:"
echo "  sudo systemctl status $SVC --no-pager"
echo "  tail -n 80 out_ci/ui_8910.error.log"
exit 10
