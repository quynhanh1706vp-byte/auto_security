#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

TS="$(date +%Y%m%d_%H%M%S)"
OUT="out_ci/p568_${TS}"
mkdir -p "$OUT"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need bash; need ls; need head; need awk; need wc; need tar; need grep; need sed; need sha256sum || true

cat > bin/legacy/p559_commercial_preflight_audit_v2.sh <<'EOS'
#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
TS="$(date +%Y%m%d_%H%M%S)"
OUT="out_ci/p559_${TS}"
mkdir -p "$OUT"

warn=0; fail=0
ok(){  echo "[OK]   $*" | tee -a "$OUT/RESULT.log"; }
wa(){  echo "[WARN] $*" | tee -a "$OUT/RESULT.log"; warn=$((warn+1)); }
no(){  echo "[FAIL] $*" | tee -a "$OUT/RESULT.log"; fail=$((fail+1)); }

need(){ command -v "$1" >/dev/null 2>&1 || { no "missing cmd: $1"; return 1; }; }
need curl; need awk; need head; need ls; need wc; need grep; need tar

echo "== [P559v2] BASE=$BASE SVC=$SVC OUT=$OUT ==" | tee -a "$OUT/RESULT.log"

# systemd basic
if command -v systemctl >/dev/null 2>&1; then
  if systemctl is-active --quiet "$SVC"; then ok "systemd active: $SVC"; else no "systemd NOT active: $SVC"; fi
  # envfile check: prefer `systemctl cat` (more reliable)
  if systemctl cat "$SVC" 2>/dev/null | grep -qi '^\s*EnvironmentFile='; then
    ok "EnvironmentFile present"
  else
    wa "No EnvironmentFile line found (maybe embedded env)"
  fi
fi

# pages
pages=(/vsp5 /runs /data_source /settings /rule_overrides /c/dashboard /c/runs /c/data_source /c/settings /c/rule_overrides)
for p in "${pages[@]}"; do
  f="$OUT/page_$(echo "$p" | tr '/?' '__').html"
  if curl -fsS --connect-timeout 2 --max-time 6 "$BASE$p" -o "$f"; then
    sz="$(wc -c <"$f" | awk '{print $1}')"
    ok "page $p => 200 body=$sz"
  else
    no "page $p fetch FAIL"
  fi
done

# RID + run_status
rid="$(curl -fsS --connect-timeout 2 --max-time 6 "$BASE/api/ui/runs_v3?limit=1&include_ci=1" \
  | python3 -c 'import sys,json;j=json.load(sys.stdin);print(j.get("items",[{}])[0].get("rid",""))' 2>/dev/null || true)"
[ -n "$rid" ] && ok "latest RID from runs_v3: $rid" || no "cannot get RID from runs_v3"

if [ -n "$rid" ]; then
  st_json="$OUT/run_status.json"
  if curl -fsS --connect-timeout 2 --max-time 6 "$BASE/api/vsp/run_status_v1/$rid" -o "$st_json"; then
    state="$(python3 -c 'import sys,json;j=json.load(open(sys.argv[1]));print(j.get("state",""))' "$st_json" 2>/dev/null || true)"
    reason="$(python3 -c 'import sys,json;j=json.load(open(sys.argv[1]));print(j.get("reason",""))' "$st_json" 2>/dev/null || true)"
    [ -n "$state" ] && ok "run_status_v1: state=$state reason=$reason" || no "run_status_v1 empty state"
  else
    no "run_status_v1 fetch FAIL"
  fi
fi

# P550 result check (latest)
p550_latest="$(ls -1dt out_ci/p550_* 2>/dev/null | head -n1 || true)"
if [ -n "$p550_latest" ] && [ -f "$p550_latest/RESULT.txt" ] && grep -q '^PASS' "$p550_latest/RESULT.txt"; then
  ok "P550 PASS: $p550_latest/RESULT.txt"
else
  wa "P550 PASS not proven (missing out_ci/p550_*/RESULT.txt)"
fi

# release dir (latest)
rel_dir="$(ls -1dt out_ci/releases/RELEASE_UI_* 2>/dev/null | head -n1 || true)"
[ -n "$rel_dir" ] && ok "latest release dir: $rel_dir" || no "no RELEASE_UI_* under out_ci/releases"

pick_report_html(){
  local d="$1"
  # 1) prefer report_*.html
  local f
  f="$(ls -1 "$d"/report_*.html 2>/dev/null | head -n1 || true)"
  [ -n "$f" ] && { echo "$f"; return 0; }
  # 2) else pick largest .html excluding page__*.html
  f="$(ls -1 "$d"/*.html 2>/dev/null | grep -v '/page__' | while read -r x; do echo "$(wc -c <"$x") $x"; done | sort -nr | head -n1 | awk '{print $2}')"
  echo "$f"
}

pick_report_pdf(){
  local d="$1"
  local f
  f="$(ls -1 "$d"/report_*.pdf 2>/dev/null | head -n1 || true)"
  [ -n "$f" ] && { echo "$f"; return 0; }
  f="$(ls -1 "$d"/*.pdf 2>/dev/null | head -n1 || true)"
  echo "$f"
}

# artifact checks
if [ -n "$rel_dir" ]; then
  html="$(pick_report_html "$rel_dir")"
  if [ -n "$html" ] && [ -f "$html" ]; then
    sz="$(wc -c <"$html" | awk '{print $1}')"
    if [ "$sz" -lt 50000 ]; then
      no "Report HTML too small ($sz) => suspicious: $html"
    else
      ok "Report HTML looks real ($sz bytes): $(basename "$html")"
    fi
  else
    no "No report HTML found in release dir"
  fi

  pdf="$(pick_report_pdf "$rel_dir")"
  if [ -n "$pdf" ] && [ -f "$pdf" ]; then
    sz="$(wc -c <"$pdf" | awk '{print $1}')"
    if head -c 5 "$pdf" | grep -q '%PDF-'; then
      ok "PDF looks real ($sz bytes, %PDF-): $(basename "$pdf")"
    else
      no "PDF magic missing: $pdf"
    fi
  else
    no "No PDF found in release dir"
  fi

  # support bundle (optional but expected)
  bundle="$(ls -1 "$rel_dir"/support_bundle_*.tgz 2>/dev/null | head -n1 || true)"
  if [ -n "$bundle" ] && [ -f "$bundle" ]; then
    bsz="$(wc -c <"$bundle" | awk '{print $1}')"
    if head -c 2 "$bundle" | od -An -tx1 | tr -d ' \n' | grep -qi '^1f8b'; then
      ok "Support bundle TGZ looks real ($bsz bytes, gzip magic 1f8b): $(basename "$bundle")"
    else
      no "Support bundle TGZ magic wrong: $bundle"
    fi
  else
    wa "No support_bundle_*.tgz found in release dir"
  fi

  # code tgz hygiene: VSP_UI_*.tgz
  code_tgz="$(ls -1 "$rel_dir"/VSP_UI_*.tgz 2>/dev/null | head -n1 || true)"
  if [ -n "$code_tgz" ] && [ -f "$code_tgz" ]; then
    csz="$(wc -c <"$code_tgz" | awk '{print $1}')"
    if head -c 2 "$code_tgz" | od -An -tx1 | tr -d ' \n' | grep -qi '^1f8b'; then
      ok "Code TGZ gzip ok ($csz bytes): $(basename "$code_tgz")"
    else
      no "Code TGZ magic wrong: $code_tgz"
    fi

    if tar -tzf "$code_tgz" | egrep -q '(^bin/p[0-9]|\.bak_|^out_ci/)'; then
      no "Code TGZ hygiene FAIL (contains bin/p[0-9]* or *.bak_* or out_ci/)"
    else
      ok "Code TGZ hygiene clean"
    fi
  else
    no "No VSP_UI_*.tgz (code TGZ) found in release dir"
  fi
fi

# entrypoints exist?
for f in bin/ui_gate.sh bin/verify_release_and_customer_smoke.sh bin/pack_release.sh bin/ops.sh; do
  if [ -x "$f" ] || [ -L "$f" ]; then ok "entrypoint present: $f"; else no "missing: $f"; fi
done

# headers hint (optional)
hdr="$OUT/hdr_vsp5.txt"
if curl -fsS -D "$hdr" -o /dev/null --connect-timeout 2 --max-time 6 "$BASE/vsp5"; then
  grep -qi '^content-security-policy:' "$hdr" && ok "CSP present" || wa "CSP missing"
  grep -qi '^x-content-type-options:' "$hdr" && ok "X-Content-Type-Options present" || wa "X-Content-Type-Options missing"
  grep -qi '^x-frame-options:' "$hdr" && wa "X-Frame-Options present (ok) or use CSP frame-ancestors" || ok "X-Frame-Options not present"
fi

if [ "$fail" -gt 0 ]; then
  no "== VERDICT: FAIL (fail=$fail warn=$warn) =="
  echo "RESULT=FAIL" > "$OUT/RESULT.txt"
  exit 1
else
  ok "== VERDICT: PASS (warn=$warn) =="
  echo "RESULT=PASS" > "$OUT/RESULT.txt"
fi
EOS

chmod +x bin/legacy/p559_commercial_preflight_audit_v2.sh
bash -n bin/legacy/p559_commercial_preflight_audit_v2.sh

# Patch preflight wrapper to prefer v2 if present
cat > bin/preflight_audit.sh <<'EOS'
#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
if [ -x bin/legacy/p559_commercial_preflight_audit_v2.sh ]; then
  echo "[preflight] using: bin/legacy/p559_commercial_preflight_audit_v2.sh"
  exec bash bin/legacy/p559_commercial_preflight_audit_v2.sh
fi
p559="$(ls -1t bin/legacy/p559_commercial_preflight_audit_v*.sh 2>/dev/null | head -n1 || true)"
[ -n "$p559" ] || { echo "[FAIL] no legacy p559 found under bin/legacy/"; exit 4; }
echo "[preflight] using: $p559"
exec bash "$p559"
EOS
chmod +x bin/preflight_audit.sh
bash -n bin/preflight_audit.sh

echo "== [P568] run preflight ==" | tee "$OUT/run.log"
bash bin/preflight_audit.sh | tee -a "$OUT/preflight.log"

echo "OUT=$OUT"
