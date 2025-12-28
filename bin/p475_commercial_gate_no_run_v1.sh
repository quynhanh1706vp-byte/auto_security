#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
TS="$(date +%Y%m%d_%H%M%S)"
OUT="out_ci/p475_${TS}"
mkdir -p "$OUT"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1" | tee -a "$OUT/log.txt"; exit 2; }; }
need curl; need python3; need date; need awk; need grep; need sed; need head
command -v systemctl >/dev/null 2>&1 || true

log(){ echo "$*" | tee -a "$OUT/log.txt"; }
ok(){ log "[OK] $*"; }
warn(){ log "[WARN] $*"; }
fail(){ log "[FAIL] $*"; exit 2; }

log "== [P475] commercial gate (NO-RUN) =="
log "BASE=$BASE SVC=$SVC OUT=$OUT"

# 1) service
if command -v systemctl >/dev/null 2>&1; then
  st="$(systemctl is-active "$SVC" 2>/dev/null || true)"
  [ "$st" = "active" ] && ok "service active" || warn "service not active: $st"
else
  warn "systemctl not found; skip service check"
fi

# 2) endpoints /c/*
pages=(/c/dashboard /c/runs /c/data_source /c/settings /c/rule_overrides)
for p in "${pages[@]}"; do
  code="$(curl -sS -o "$OUT/$(echo "$p"|tr '/?' '__').html" -w "%{http_code}" \
          --connect-timeout 2 --max-time 6 "$BASE$p" || true)"
  [ "$code" = "200" ] && ok "page $p => 200" || warn "page $p => $code"
done

# 3) static sidebar asset (should exist)
code="$(curl -sS -o /dev/null -w "%{http_code}" --connect-timeout 2 --max-time 6 "$BASE/static/js/vsp_c_sidebar_v1.js" || true)"
[ "$code" = "200" ] && ok "static sidebar js => 200" || warn "static sidebar js => $code"

# 4) local code invariants (no UI-run)
# 4.1 shared module markers present
python3 - <<'PY' >"$OUT/markers.txt"
from pathlib import Path
p=Path("static/js/vsp_c_sidebar_v1.js")
s=p.read_text(encoding="utf-8", errors="replace") if p.exists() else ""
marks=[
  "VSP_P473_SIDEBAR_FRAME_ALL_TABS_V1",
  "VSP_P474_GLOBAL_POLISH_NO_RUN_V1",
]
print("sidebar_exists", p.exists())
for m in marks:
  print(m, ("YES" if m in s else "NO"))
PY

cat "$OUT/markers.txt" | tee -a "$OUT/log.txt"
grep -q "sidebar_exists True" "$OUT/markers.txt" && ok "sidebar module exists" || warn "sidebar module missing"
grep -q "VSP_P473_SIDEBAR_FRAME_ALL_TABS_V1 YES" "$OUT/markers.txt" && ok "P473 in sidebar" || warn "P473 missing in sidebar"
grep -q "VSP_P474_GLOBAL_POLISH_NO_RUN_V1 YES" "$OUT/markers.txt" && ok "P474 in sidebar" || warn "P474 missing in sidebar"

# 4.2 loader injected into all c_* js files
cnt_all="$(ls -1 static/js/vsp_c_*v*.js 2>/dev/null | wc -l | tr -d ' ')"
cnt_mark="$(grep -R --line-number "VSP_P473_LOADER_SNIPPET_V1" static/js/vsp_c_*v*.js 2>/dev/null | wc -l | tr -d ' ')"
log "loader_files_total=$cnt_all loader_snippet_hits=$cnt_mark"
if [ "$cnt_all" -gt 0 ] && [ "$cnt_mark" -ge "$cnt_all" ]; then
  ok "loader present in all vsp_c_*v*.js"
else
  warn "loader not fully present (need re-run P473b)"
fi

# 5) API sanity (read-only)
code="$(curl -sS -o "$OUT/runs.json" -w "%{http_code}" --connect-timeout 2 --max-time 6 "$BASE/api/vsp/runs_v3?limit=3&include_ci=1" || true)"
if [ "$code" = "200" ]; then
  ok "api runs_v3 => 200"
  python3 - <<'PY' "$OUT/runs.json" | tee -a "$OUT/log.txt"
import json,sys
p=sys.argv[1]
j=json.load(open(p,"r",encoding="utf-8",errors="replace"))
items=j.get("items") or []
print("[INFO] ver=", j.get("ver"), "items=", len(items))
if items:
  print("[INFO] sample rid=", items[0].get("rid"), "ts=", items[0].get("ts") or items[0].get("time") or "")
PY
else
  warn "api runs_v3 => $code"
fi

# Verdict (simple)
# FAIL if any /c/* not 200? -> AMBER instead (commercial gate wants stable, but allow local issues)
bad_pages="$(for p in "${pages[@]}"; do
  f="$OUT/$(echo "$p"|tr '/?' '__').html"
  # if file empty, count bad
  [ -s "$f" ] || echo "$p"
done | wc -l | tr -d ' ')"

verdict="GREEN"
[ "$bad_pages" -gt 0 ] && verdict="AMBER"
grep -q "P474 missing" "$OUT/log.txt" && verdict="AMBER" || true
[ "$code" != "200" ] && verdict="AMBER" || true

log "== VERDICT: $verdict =="
log "[OK] log: $OUT/log.txt"
echo "$verdict" > "$OUT/VERDICT.txt"
