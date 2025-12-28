#!/usr/bin/env bash
set -euo pipefail
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need curl; need grep; need awk; need sed; need sort; need uniq; need mktemp; need date; need python3
command -v node >/dev/null 2>&1 || { echo "[ERR] missing: node (need node --check)"; exit 2; }

tmp="$(mktemp -d /tmp/vsp_gate_ui_XXXXXX)"
trap 'rm -rf "$tmp"' EXIT

ok(){ echo "[OK] $*"; }
warn(){ echo "[WARN] $*" >&2; }
fail(){ echo "[FAIL] $*" >&2; exit 1; }

fetch(){
  local p="$1"; local out="$2"
  local code
  code="$(curl -sS -o "$out" -w "%{http_code}" --connect-timeout 1 --max-time 6 "$BASE$p" || true)"
  echo "$code"
}

echo "== [0] Tabs reachable (5 tabs + /c/* routes) =="
tabs=(/vsp5 /runs /data_source /settings /rule_overrides /c/dashboard /c/runs /c/data_source /c/settings /c/rule_overrides)
for p in "${tabs[@]}"; do
  f="$tmp/$(echo "$p" | tr '/?' '__').html"
  code="$(fetch "$p" "$f")"
  if [ "$code" = "200" ] || [ "$code" = "302" ]; then
    ok "tab $p => $code"
  else
    warn "tab $p => $code"
    fail "tab not reachable: $p"
  fi
done

echo
echo "== [1] API smoke =="
apis=(
  "/api/vsp/runs?limit=5&offset=0"
  "/api/vsp/top_findings_v1?limit=5"
  "/api/vsp/top_findings_v3c?limit=5"
  "/api/vsp/trend_v1"
  "/api/vsp/findings_page_v3?limit=5&offset=0"
  "/api/vsp/rule_overrides_v1"
)
for p in "${apis[@]}"; do
  code="$(curl -sS -o "$tmp/api.json" -w "%{http_code}" --connect-timeout 1 --max-time 6 "$BASE$p" || true)"
  if [ "$code" = "200" ]; then
    ok "api $p => 200"
  else
    warn "api $p => $code"
    cat "$tmp/api.json" 2>/dev/null | head -c 500 || true
    echo
    fail "api fail: $p"
  fi
done

echo
echo "== [2] JS syntax / critical globals =="
JS="static/js/vsp_fill_real_data_5tabs_p1_v1.js"
[ -f "$JS" ] || fail "missing $JS"
node --check "$JS" >/dev/null && ok "node --check $JS OK" || fail "JS syntax fail: $JS"
grep -nE '^\s*(const|let|var)\s+BASE\s*=' "$JS" >/dev/null && ok "BASE defined in JS" || fail "BASE missing in JS"
grep -nE '^\s*(const|let|var)\s+rid\s*=' "$JS" >/dev/null && ok "rid is declared in JS" || warn "rid declare not found (check manually)"

echo
echo "== [3] Find duplicated JS urls across tabs (quick) =="
alljs="$tmp/all_js.txt"; : > "$alljs"
for p in /vsp5 /runs /data_source /settings /rule_overrides; do
  f="$tmp/$(echo "$p" | tr '/?' '__').html"
  grep -oE 'src="/static/js/[^"]+"' "$f" | sed 's/^src="//;s/"$//' >> "$alljs" || true
done
dups="$(sort "$alljs" | uniq -d | head -n 20 || true)"
if [ -n "$dups" ]; then
  warn "duplicated JS (not always bad) sample:"
  echo "$dups" | sed 's/^/  - /'
else
  ok "no duplicate JS src among 5 tabs"
fi

echo
echo "== [4] run_file_allow sanity (best effort) =="
RID="$(curl -fsS "$BASE/api/vsp/rid_latest" 2>/dev/null | python3 -c 'import sys,json; print((json.load(sys.stdin).get("rid") or "").strip())' || true)"
if [ -z "$RID" ]; then
  warn "rid_latest empty (skip run_file_allow checks)"
else
  ok "RID=$RID"
  # try a few common paths
  paths=("reports/findings_unified.json" "findings_unified.json" "reports/run_gate_summary.json" "run_gate_summary.json")
  hit=0
  for pp in "${paths[@]}"; do
    code="$(curl -sS -o "$tmp/rf.json" -w "%{http_code}" --connect-timeout 1 --max-time 6 \
      "$BASE/api/vsp/run_file_allow?rid=$RID&path=$pp&limit=1" || true)"
    if [ "$code" = "200" ]; then
      ok "run_file_allow path=$pp => 200"
      hit=1
      break
    fi
  done
  if [ "$hit" = "0" ]; then
    warn "run_file_allow did not return 200 for common paths (maybe allowlist stricter) - check later"
  fi
fi

echo
ok "COMMERCIAL GATE: GREEN ✅"
