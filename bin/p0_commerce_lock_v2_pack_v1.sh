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

# 0) Service sanity
{
  echo "== systemctl is-active =="
  systemctl is-active "$SVC" || true
  echo
  echo "== systemctl status (first 40 lines) =="
  systemctl --no-pager --full status "$SVC" | sed -n '1,40p' || true
} > "$OUT/systemd/status.txt" 2>&1

# 1) Probe 5 tabs (HTML) + quick markers
tabs=(/vsp5 /runs /data_source /settings /rule_overrides)
for p in "${tabs[@]}"; do
  f="$OUT/html/$(echo "$p" | tr '/?' '__').html"
  echo "[FETCH] $p -> $(basename "$f")"
  curl -fsS --connect-timeout 2 --max-time 8 --range 0-220000 "$BASE$p?rid=$RID" -o "$f" || {
    echo "[WARN] fetch failed: $p" | tee -a "$OUT/probes/tab_fetch_warn.txt"
    continue
  }
done

# 2) API probes (commercial contract)
echo "[PROBE] findings_page_v3"
curl -sS "$BASE/api/vsp/findings_page_v3?rid=$RID&limit=1&offset=0" \
| python3 - <<'PY' > "$OUT/probes/findings_page_v3.txt"
import sys, json
j=json.load(sys.stdin)
print("ok=",j.get("ok"))
print("rid_requested=",j.get("rid_requested"))
print("rid_used=",j.get("rid_used"))
print("from_path=",j.get("from_path"))
print("total_findings=",j.get("total_findings"))
print("items_len=",len(j.get("items") or []))
PY

echo "[PROBE] top_findings_v3c"
curl -sS "$BASE/api/vsp/top_findings_v3c?rid=$RID&limit=200" \
| python3 - <<'PY' > "$OUT/probes/top_findings_v3c.txt"
import sys, json
j=json.load(sys.stdin)
print("ok=",j.get("ok"))
print("api=",j.get("api"))
print("rid=",j.get("rid"))
print("rid_used=",j.get("rid_used"))
print("total=",j.get("total"))
print("limit_applied=",j.get("limit_applied"))
print("items_len=",len(j.get("items") or []))
print("items_truncated=",j.get("items_truncated"))
PY

echo "[PROBE] trend_v1 (first point)"
curl -sS "$BASE/api/vsp/trend_v1" \
| python3 - <<'PY' > "$OUT/probes/trend_v1.txt"
import sys, json
j=json.load(sys.stdin)
pts=j.get("points") or []
print("ok=",j.get("ok"))
print("points_len=",len(pts))
print("first=",pts[0] if pts else None)
PY

echo "[PROBE] runs (first item)"
curl -sS "$BASE/api/vsp/runs?limit=5&offset=0" \
| python3 - <<'PY' > "$OUT/probes/runs.txt"
import sys, json
j=json.load(sys.stdin)
runs=j.get("runs") or []
print("ok=",j.get("ok"))
print("runs_len=",len(runs))
print("first=",runs[0] if runs else None)
PY

# 3) JS correctness checks (no v3cc, must contain v3c)
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

# 4) Snapshot code + systemd config (for audit/compliance)
cp -f vsp_demo_app.py "$OUT/code/vsp_demo_app.py" 2>/dev/null || true
cp -f wsgi_vsp_ui_gateway.py "$OUT/code/wsgi_vsp_ui_gateway.py" 2>/dev/null || true
cp -rf templates "$OUT/code/templates" 2>/dev/null || true
mkdir -p "$OUT/code/static_js"
ls -1 static/js/vsp_* 2>/dev/null | head -n 200 | while read -r f; do cp -f "$f" "$OUT/code/static_js/" 2>/dev/null || true; done

# systemd drop-ins + unit
(systemctl cat "$SVC" || true) > "$OUT/systemd/unit_and_dropins.txt" 2>&1
sudo journalctl -u "$SVC" -n 120 --no-pager > "$OUT/systemd/journal_tail.txt" 2>&1 || true

# 5) Proof note (what to tell sếp)
FP="$(sed -n 's/^from_path= //p' "$OUT/probes/findings_page_v3.txt" 2>/dev/null | head -n 1 || true)"
TF="$(sed -n 's/^total_findings= //p' "$OUT/probes/findings_page_v3.txt" 2>/dev/null | head -n 1 || true)"
TOPLEN="$(sed -n 's/^items_len=//p' "$OUT/probes/top_findings_v3c.txt" 2>/dev/null | head -n 1 | tr -d ' ' || true)"

cat > "$OUT/notes/PROOFNOTE.txt" <<EOF
VSP COMMERCE LOCK (P0)
TS: $TS
BASE: $BASE
RID(open): $RID

FINDINGS_PAGE_V3:
- from_path: $FP
- total_findings: $TF

TOP_FINDINGS_V3C:
- items_len: $TOPLEN (limit=200)

UI:
- /vsp5 uses commercial dataset fallback (GLOBAL_BEST if rid is thin)
- Top findings via /api/vsp/top_findings_v3c
EOF

# 6) Pack
tar -czf "$PKG" -C "$(dirname "$OUT")" "$(basename "$OUT")"
echo "[OK] PACKED: $PKG"
echo "[OK] OUTDIR: $OUT"
