#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
RID="${RID:-VSP_CI_20251218_114312}"
TS="$(date +%Y%m%d_%H%M%S)"
OUT="/home/test/Data/SECURITY_BUNDLE/ui/out_ci/COMMERCE_LOCK_${TS}"
PKG="/home/test/Data/SECURITY_BUNDLE/ui/out_ci/COMMERCE_LOCK_${TS}.tgz"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need curl; need python3; need tar; need mkdir; need sed; need grep; need head; need awk

mkdir -p "$OUT"/{probes,html,code,systemd,notes}

echo "[INFO] OUT=$OUT"
echo "[INFO] BASE=$BASE RID=$RID SVC=$SVC"

fetch_html(){
  local path="$1"
  local file="$2"
  echo "[FETCH] $path -> $(basename "$file")"
  curl -sS --connect-timeout 2 --max-time 10 --range 0-220000 \
    "$BASE$path?rid=$RID" -o "$file" || {
      echo "[WARN] fetch failed: $path" | tee -a "$OUT/probes/tab_fetch_warn.txt"
      return 1
    }
}

fetch_api(){
  local url="$1"
  local outbody="$2"
  local outhdr="$3"
  local outcode="$4"

  # Always write body+headers+code; never pipe into python
  local code
  code="$(curl -sS -D "$outhdr" -o "$outbody" -w "%{http_code}" \
    --connect-timeout 2 --max-time 20 "$url" || true)"
  echo "$code" > "$outcode"
  echo "$code"
}

parse_json_probe(){
  local body="$1"
  local pretty_out="$2"
  local title="$3"

  python3 - "$body" <<'PY' > "$pretty_out" 2>&1 || true
import sys, json, pathlib
path = pathlib.Path(sys.argv[1])
raw = path.read_bytes() if path.exists() else b""
print(f"[INFO] bytes={len(raw)}")
if len(raw) == 0:
    print("[ERR] empty body (not JSON)")
    sys.exit(2)
try:
    j = json.loads(raw.decode("utf-8", errors="replace"))
except Exception as e:
    head = raw[:200].decode("utf-8", errors="replace")
    print("[ERR] JSON parse failed:", repr(e))
    print("[HEAD_200]")
    print(head)
    sys.exit(2)
# Print a small safe summary (generic)
print("keys=", sorted(list(j.keys()))[:60])
print("ok=", j.get("ok"))
print("rid=", j.get("rid") or j.get("rid_used") or j.get("rid_requested"))
print("total=", j.get("total"))
print("limit_applied=", j.get("limit_applied"))
items = j.get("items") or []
print("items_len=", len(items) if isinstance(items, list) else None)
print("from_path=", j.get("from_path"))
print("total_findings=", j.get("total_findings"))
PY
}

# 0) Service sanity
{
  echo "== systemctl is-active =="
  systemctl is-active "$SVC" || true
  echo
  echo "== systemctl status (first 50 lines) =="
  systemctl --no-pager --full status "$SVC" | sed -n '1,50p' || true
} > "$OUT/systemd/status.txt" 2>&1

# 1) Probe 5 tabs (HTML)
tabs=(/vsp5 /runs /data_source /settings /rule_overrides)
for p in "${tabs[@]}"; do
  f="$OUT/html/$(echo "$p" | tr '/?' '__').html"
  fetch_html "$p" "$f" || true
done

# 2) API probes (save raw + parse safely)
echo "[PROBE] findings_page_v3"
U1="$BASE/api/vsp/findings_page_v3?rid=$RID&limit=1&offset=0"
B1="$OUT/probes/findings_page_v3.body"
H1="$OUT/probes/findings_page_v3.hdr"
C1="$OUT/probes/findings_page_v3.code"
code1="$(fetch_api "$U1" "$B1" "$H1" "$C1")"
echo "[INFO] code=$code1 url=$U1" | tee "$OUT/probes/findings_page_v3.meta"
parse_json_probe "$B1" "$OUT/probes/findings_page_v3.summary.txt" "findings_page_v3"

echo "[PROBE] top_findings_v3c"
U2="$BASE/api/vsp/top_findings_v3c?rid=$RID&limit=200"
B2="$OUT/probes/top_findings_v3c.body"
H2="$OUT/probes/top_findings_v3c.hdr"
C2="$OUT/probes/top_findings_v3c.code"
code2="$(fetch_api "$U2" "$B2" "$H2" "$C2")"
echo "[INFO] code=$code2 url=$U2" | tee "$OUT/probes/top_findings_v3c.meta"
parse_json_probe "$B2" "$OUT/probes/top_findings_v3c.summary.txt" "top_findings_v3c"

echo "[PROBE] trend_v1"
U3="$BASE/api/vsp/trend_v1"
B3="$OUT/probes/trend_v1.body"
H3="$OUT/probes/trend_v1.hdr"
C3="$OUT/probes/trend_v1.code"
code3="$(fetch_api "$U3" "$B3" "$H3" "$C3")"
echo "[INFO] code=$code3 url=$U3" | tee "$OUT/probes/trend_v1.meta"
parse_json_probe "$B3" "$OUT/probes/trend_v1.summary.txt" "trend_v1"

echo "[PROBE] runs"
U4="$BASE/api/vsp/runs?limit=5&offset=0"
B4="$OUT/probes/runs.body"
H4="$OUT/probes/runs.hdr"
C4="$OUT/probes/runs.code"
code4="$(fetch_api "$U4" "$B4" "$H4" "$C4")"
echo "[INFO] code=$code4 url=$U4" | tee "$OUT/probes/runs.meta"
parse_json_probe "$B4" "$OUT/probes/runs.summary.txt" "runs"

# 3) JS checks
JS="static/js/vsp_dashboard_luxe_v1.js"
{
  echo "== JS checks =="
  if [ -f "$JS" ]; then
    echo "[OK] $JS exists"
    echo "-- top_findings_v3c lines:"
    grep -n "top_findings_v3c" "$JS" | head -n 20 || true
    echo "-- top_findings_v3cc lines (must be none):"
    grep -n "top_findings_v3cc" "$JS" || echo "OK: no v3cc"
  else
    echo "[WARN] missing $JS"
  fi
} > "$OUT/probes/js_checks.txt" 2>&1

# 4) Snapshot code + systemd
cp -f vsp_demo_app.py "$OUT/code/vsp_demo_app.py" 2>/dev/null || true
cp -f wsgi_vsp_ui_gateway.py "$OUT/code/wsgi_vsp_ui_gateway.py" 2>/dev/null || true
cp -rf templates "$OUT/code/templates" 2>/dev/null || true
mkdir -p "$OUT/code/static_js"
ls -1 static/js/vsp_* 2>/dev/null | head -n 250 | while read -r f; do cp -f "$f" "$OUT/code/static_js/" 2>/dev/null || true; done

(systemctl cat "$SVC" || true) > "$OUT/systemd/unit_and_dropins.txt" 2>&1
sudo journalctl -u "$SVC" -n 120 --no-pager > "$OUT/systemd/journal_tail.txt" 2>&1 || true

# 5) Proofnote (best-effort from summaries)
FP="$(grep -m1 '^from_path=' "$OUT/probes/findings_page_v3.summary.txt" 2>/dev/null | sed 's/^from_path=//')"
TF="$(grep -m1 '^total_findings=' "$OUT/probes/findings_page_v3.summary.txt" 2>/dev/null | sed 's/^total_findings=//')"
TOPLEN="$(grep -m1 '^items_len=' "$OUT/probes/top_findings_v3c.summary.txt" 2>/dev/null | sed 's/^items_len=//')"

cat > "$OUT/notes/PROOFNOTE.txt" <<EOF
VSP COMMERCE LOCK (P0)
TS: $TS
BASE: $BASE
RID(open): $RID

findings_page_v3:
- from_path: ${FP:-"(see probes/findings_page_v3.*)"}
- total_findings: ${TF:-"(see probes/findings_page_v3.*)"}

top_findings_v3c:
- items_len: ${TOPLEN:-"(see probes/top_findings_v3c.*)"} (limit=200)

NOTE:
- If any *.summary.txt contains [ERR] JSON parse failed / empty body:
  open the corresponding *.body + *.hdr + *.code in OUT/probes to see what happened.
EOF

# 6) Pack
tar -czf "$PKG" -C "$(dirname "$OUT")" "$(basename "$OUT")"
echo "[OK] PACKED: $PKG"
echo "[OK] OUTDIR: $OUT"
