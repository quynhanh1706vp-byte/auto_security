#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
TS="$(date +%Y%m%d_%H%M%S)"
OUT="out_ci/p559_${TS}"
mkdir -p "$OUT"

pass=0; warn=0; fail=0
ok(){  echo "[OK]   $*" | tee -a "$OUT/RESULT.log"; }
wa(){  echo "[WARN] $*" | tee -a "$OUT/RESULT.log"; warn=$((warn+1)); }
no(){  echo "[FAIL] $*" | tee -a "$OUT/RESULT.log"; fail=$((fail+1)); }

need(){ command -v "$1" >/dev/null 2>&1 || { no "missing cmd: $1"; return 1; }; }
need curl
need python3
need grep
need awk
need sed
command -v jq >/dev/null 2>&1 || wa "jq not found (will use python3 for JSON parsing)"

pyget(){ # pyget <json_file> <python_expr_printing_value_or_empty>
  local f="$1"; local expr="$2"
  python3 - "$f" "$expr" <<'PY'
import json,sys
p=sys.argv[1]; expr=sys.argv[2]
try:
    j=json.load(open(p,'r',encoding='utf-8',errors='replace'))
except Exception as e:
    print("")
    sys.exit(0)
# expr is evaluated with 'j' in locals; must print something
try:
    val=eval(expr, {"__builtins__":{}}, {"j":j})
    if val is None: val=""
    print(val)
except Exception:
    print("")
PY
}

http_code(){
  curl -sS -o "$2" -D "$3" --connect-timeout 2 --max-time 8 -w "%{http_code}" "$1" || echo "000"
}

magic_hex(){
  # magic_hex <file> <nbytes>
  python3 - "$1" "$2" <<'PY'
import sys
p=sys.argv[1]; n=int(sys.argv[2])
b=open(p,'rb').read(n)
print(b.hex())
PY
}

filesize(){
  python3 - "$1" <<'PY'
import os,sys
print(os.path.getsize(sys.argv[1]) if os.path.exists(sys.argv[1]) else 0)
PY
}

echo "== [P559] BASE=$BASE SVC=$SVC OUT=$OUT ==" | tee "$OUT/README.txt"

# 0) service quick check (best-effort)
if command -v systemctl >/dev/null 2>&1; then
  if systemctl is-active --quiet "$SVC" 2>/dev/null; then ok "systemd active: $SVC"; else wa "systemd not active (or no permission): $SVC"; fi
  systemctl show -p ExecStart,WorkingDirectory,EnvironmentFile,User,Group "$SVC" 2>/dev/null > "$OUT/systemd_show.txt" || true
  systemctl cat "$SVC" 2>/dev/null > "$OUT/systemd_cat.txt" || true

  if [ -s "$OUT/systemd_show.txt" ]; then
    grep -q "ExecStart=.*bin/" "$OUT/systemd_show.txt" && ok "ExecStart looks like wrapper/bin" || wa "ExecStart not obviously using bin wrapper (check systemd_show.txt)"
    if grep -q "EnvironmentFile=" "$OUT/systemd_show.txt"; then
      envf="$(sed -n 's/^EnvironmentFile=//p' "$OUT/systemd_show.txt" | head -n1 | tr -d '"')"
      [ -n "$envf" ] && [ -f "$envf" ] && ok "EnvironmentFile exists: $envf" || wa "EnvironmentFile missing or unreadable: $envf"
    else
      wa "No EnvironmentFile line found (maybe embedded env)"
    fi
  else
    wa "Cannot read systemd unit details (no permission?)"
  fi
else
  wa "systemctl not found; skip service checks"
fi

# 1) pages must be 200 and not blank
pages=(/vsp5 /runs /data_source /settings /rule_overrides /c/dashboard /c/runs /c/data_source /c/settings /c/rule_overrides)
for p in "${pages[@]}"; do
  b="$OUT/page_$(echo "$p" | tr '/?' '__').html"
  h="$OUT/page_$(echo "$p" | tr '/?' '__').hdr"
  code="$(http_code "$BASE$p" "$b" "$h")"
  if [ "$code" = "200" ]; then
    sz="$(filesize "$b")"
    if [ "$sz" -lt 900 ]; then
      no "page $p 200 but body too small ($sz bytes) => looks blank"
    else
      ok "page $p => 200 body=$sz"
    fi
  else
    no "page $p => HTTP $code"
  fi
done

# 2) get latest RID from runs_v3
runs_json="$OUT/runs_v3.json"
code="$(curl -sS --connect-timeout 2 --max-time 10 "$BASE/api/ui/runs_v3?limit=10&include_ci=1" -o "$runs_json" -w "%{http_code}" || echo "000")"
if [ "$code" != "200" ]; then
  no "API runs_v3 failed HTTP $code"
  RID=""
else
  RID="$(pyget "$runs_json" 'j.get("items",[{}])[0].get("rid","")')"
  [ -n "$RID" ] && ok "latest RID from runs_v3: $RID" || no "runs_v3 returned but RID empty"
fi

# 3) run_status_v1 must not be empty; run_dir must exist
if [ -n "${RID:-}" ]; then
  rs_json="$OUT/run_status_v1_${RID}.json"
  code="$(curl -sS --connect-timeout 2 --max-time 10 "$BASE/api/vsp/run_status_v1/$RID" -o "$rs_json" -w "%{http_code}" || echo "000")"
  if [ "$code" != "200" ]; then
    no "run_status_v1/$RID failed HTTP $code"
  else
    state="$(pyget "$rs_json" 'j.get("state","")')"
    reason="$(pyget "$rs_json" 'j.get("reason","")')"
    run_dir="$(pyget "$rs_json" 'j.get("run_dir","")')"
    if [ -z "$state" ]; then
      no "run_status_v1 state is EMPTY (should be FINISHED/DEGRADED/FAILED/RUNNING)"
    else
      ok "run_status_v1: state=$state reason=$reason"
      case "$state" in
        FINISHED|DEGRADED|FAILED|RUNNING) ok "state enum looks valid" ;;
        *) wa "state is non-standard: $state" ;;
      esac
    fi
    if [ -n "$run_dir" ] && [ -d "$run_dir" ]; then
      ok "run_dir exists: $run_dir"
    else
      wa "run_dir missing or not a dir: $run_dir"
    fi
  fi
fi

# 4) P550 gate must be PASS
p550_latest="$(ls -1dt out_ci/p550_* 2>/dev/null | head -n1 || true)"
if [ -n "$p550_latest" ]; then
  if [ -f "$p550_latest/RESULT.txt" ]; then
    if grep -q "^PASS" "$p550_latest/RESULT.txt"; then
      ok "P550 PASS: $p550_latest/RESULT.txt"
    else
      no "P550 not PASS: $p550_latest/RESULT.txt"
    fi
  else
    wa "P550 RESULT.txt missing under $p550_latest"
  fi
else
  wa "No out_ci/p550_* found (cannot prove pack gating)"
fi

# 5) locate latest release dir and check HTML/PDF/TGZ real
rel_dir="$(ls -1dt out_ci/releases/RELEASE_UI_* 2>/dev/null | head -n1 || true)"
if [ -z "$rel_dir" ]; then
  wa "No release dir out_ci/releases/RELEASE_UI_* found"
else
  ok "latest release dir: $rel_dir"
  html="$(ls -1 "$rel_dir"/*.html 2>/dev/null | head -n1 || true)"
  pdf="$(ls -1 "$rel_dir"/*.pdf 2>/dev/null | head -n1 || true)"
  tgz="$(ls -1 "$rel_dir"/*.tgz 2>/dev/null | head -n1 || true)"

  if [ -n "$html" ]; then
    sz="$(filesize "$html")"
    if [ "$sz" -lt 50000 ]; then
      no "HTML too small ($sz) => suspicious: $html"
    else
      if grep -qi "<html" "$html"; then ok "HTML looks real ($sz bytes): $(basename "$html")"
      else wa "HTML missing <html tag (still may be ok): $html"; fi
    fi
  else
    wa "No HTML found in release dir"
  fi

  if [ -n "$pdf" ]; then
    sz="$(filesize "$pdf")"
    mg="$(python3 - <<PY
import sys
p="$pdf"
b=open(p,'rb').read(5)
print(b.decode('latin1',errors='ignore'))
PY
)"
    if [ "$mg" = "%PDF-" ] && [ "$sz" -ge 2000 ]; then
      ok "PDF looks real ($sz bytes, %PDF-): $(basename "$pdf")"
    else
      no "PDF suspicious (size=$sz magic='$mg'): $pdf"
    fi
  else
    wa "No PDF found in release dir"
  fi

  if [ -n "$tgz" ]; then
    sz="$(filesize "$tgz")"
    hx="$(magic_hex "$tgz" 2)"
    if [ "$hx" = "1f8b" ] && [ "$sz" -ge 200000 ]; then
      ok "TGZ looks real ($sz bytes, gzip magic 1f8b): $(basename "$tgz")"
    else
      no "TGZ suspicious (size=$sz magic=$hx): $tgz"
    fi

    sha256sum "$tgz" "$html" "$pdf" 2>/dev/null | tee "$OUT/SHA256SUMS.txt" || true

    # 5.1) TGZ must NOT contain bin/p* or out_ci or *.bak_*
    if command -v tar >/dev/null 2>&1; then
      tar -tzf "$tgz" > "$OUT/tgz_list.txt" || { no "Cannot list tgz content"; }
      if grep -Eq '(^|/)bin/p[0-9]' "$OUT/tgz_list.txt"; then
        no "TGZ contains bin/p* scripts => ship hygiene FAIL"
      else
        ok "TGZ does NOT contain bin/p*"
      fi
      if grep -Eq '(^|/)out_ci/' "$OUT/tgz_list.txt"; then
        no "TGZ contains out_ci/ => ship hygiene FAIL"
      else
        ok "TGZ does NOT contain out_ci/"
      fi
      if grep -Eq '\.bak_' "$OUT/tgz_list.txt"; then
        wa "TGZ contains *.bak_* (should be excluded)"
      else
        ok "TGZ does NOT contain *.bak_*"
      fi
    else
      wa "tar not found; skip tgz content checks"
    fi
  else
    wa "No TGZ found in release dir"
  fi
fi

# 6) bin hygiene (local workspace)
if [ -d bin ]; then
  execs="$(find bin -maxdepth 2 -type f -perm -111 2>/dev/null | sed 's|^\./||')"
  echo "$execs" > "$OUT/bin_executables.txt"
  if grep -Eq '^bin/p[0-9].*\.sh$' "$OUT/bin_executables.txt"; then
    wa "Found executable bin/p*.sh (should move to bin/legacy and chmod -x)"
  else
    ok "No executable bin/p*.sh found"
  fi
  for f in ui_gate.sh verify_release_and_customer_smoke.sh pack_release.sh ops.sh; do
    if [ -x "bin/$f" ]; then ok "entrypoint executable: bin/$f"
    else wa "missing or not executable: bin/$f"; fi
  done
else
  no "missing bin/ directory"
fi

# 7) security headers quick spot-check (best-effort)
hdr="$OUT/headers_vsp5.txt"
curl -sS -D "$hdr" -o /dev/null --connect-timeout 2 --max-time 8 "$BASE/vsp5" || true
if [ -s "$hdr" ]; then
  grep -qi '^Content-Security-Policy:' "$hdr" && ok "CSP present" || wa "CSP header missing (maybe intentional)"
  grep -qi '^X-Content-Type-Options:' "$hdr" && ok "X-Content-Type-Options present" || wa "X-Content-Type-Options missing"
  grep -qi '^X-Frame-Options:' "$hdr" && wa "X-Frame-Options present (ok) or you may use frame-ancestors in CSP" || true
fi

# final verdict
if [ "$fail" -eq 0 ]; then
  echo "PASS" > "$OUT/RESULT.txt"
  ok "== VERDICT: PASS (warn=$warn) =="
else
  echo "FAIL" > "$OUT/RESULT.txt"
  no "== VERDICT: FAIL (fail=$fail warn=$warn) =="
fi

echo
echo "OUT=$OUT"
echo "RESULT=$(cat "$OUT/RESULT.txt")"
